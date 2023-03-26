import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:collection/collection.dart';
import 'package:dart_doc_bot/src/database/database.dart';
import 'package:dart_doc_bot/src/search/search_service.dart';
import 'package:multiline/multiline.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'middleware/errors.dart';

final Handler $router = Router(notFoundHandler: $notFound)
  ..get('/stat', $stat)
  ..get('/search', $search)
  ..get('/health', $healthCheck)
  ..post('/telegram', $telegram);

Response $healthCheck(Request request) => Response.ok(
      '{"data": {"status": "ok"}}',
      headers: <String, String>{
        'Content-Type': io.ContentType.json.value,
      },
    );

Future<Response> $stat(Request request) async {
  final result = await request.database
      .customSelect('''
      |SELECT 'database' AS k, 'ok' AS v
      |UNION ALL SELECT 'libraries', v FROM kv WHERE k = 'libraries'
      |UNION ALL SELECT 'entities',  v FROM kv WHERE k = 'entities'
      |UNION ALL SELECT 'prefixes',  v FROM kv WHERE k = 'prefixes'
      |UNION ALL SELECT 'trigrams',  v FROM kv WHERE k = 'trigrams'
      |UNION ALL SELECT 'updated',   v FROM kv WHERE k = 'updated'
      |UNION ALL SELECT 'size',      v FROM kv WHERE k = 'size'
      '''
          .multiline()
          .trim())
      .get();

  return Response.ok(
    jsonEncode(
      <String, Object?>{
        'data': <String, Object?>{
          for (final stat in result)
            if (stat.data.containsKey('k')) stat.data['k'].toString(): stat.data['v'],
        },
      },
    ),
    headers: <String, String>{
      'Content-Type': io.ContentType.json.value,
    },
  );
}

Future<Response> $search(Request request) async {
  final query = request.url.queryParameters['q'];
  if (query == null || query.isEmpty) {
    throw BadRequestException(
      detail: 'Missing query parameter "q"',
      data: <String, Object?>{
        'path': request.url.path,
        'method': request.method,
        'headers': request.headers,
      },
    );
  }
  final result = await request.searchService.search(query);
  return Response.ok(
    jsonEncode(
      <String, Object?>{
        'data': result,
      },
    ),
    headers: <String, String>{
      'Content-Type': io.ContentType.json.value,
    },
  );
}

FutureOr<Response> $telegram(Request request) async {
  if (request.headers['content-type']?.contains('application/json') != true) {
    throw BadRequestException(
      detail: 'Invalid content-type',
      data: <String, Object?>{
        'path': request.url.path,
        'method': request.method,
        'headers': request.headers,
      },
    );
  } else if (request.isEmpty) {
    throw BadRequestException(
      detail: 'Empty request body',
      data: <String, Object?>{
        'path': request.url.path,
        'method': request.method,
        'headers': request.headers,
      },
    );
  }
  final body = await request.readAsString();
  final Map<String, Object?> data;
  try {
    data = jsonDecode(body);
  } on Object {
    throw BadRequestException(
      detail: 'Invalid JSON',
      data: <String, Object?>{
        'path': request.url.path,
        'method': request.method,
        'headers': request.headers,
        'body': body,
      },
    );
  }

  @pragma('vm:prefer-inline')
  FutureOr<Map<String, Object?>?> inlineQuery(Map<String, Object?> data) async {
    final query = data['query']?.toString().trim();
    if (query == null || query.length < 3) return null;
    final results = await request.searchService.search(query, limit: 50);
    if (results.isEmpty) return null;
    return <String, Object?>{
      'inline_query_id': data['id'],
      'results': results.mapIndexed<Map<String, Object?>>(_mapSearchResult2InlineQueryResponse).toList(),
    };
  }

  final Map<String, FutureOr<Map<String, Object?>?> Function(Map<String, Object?> data)> actions =
      <String, FutureOr<Map<String, Object?>?> Function(Map<String, Object?> data)>{
    //'message': doNothing,
    //'edited_message': doNothing,
    'inline_query': inlineQuery,
    //'chosen_inline_result': doNothing,
    //'callback_query': doNothing,
  };

  for (final action in actions.entries) {
    final updated = data[action.key];
    if (updated is! Map<String, Object?>) continue;
    final response = await action.value(updated);
    if (response == null) break;
    return Response.ok(
      jsonEncode(response),
      headers: <String, String>{
        'Content-Type': io.ContentType.json.value,
      },
    );
  }

  return Response.ok(
    '{"data": {"status": "ok"}}',
    headers: <String, String>{
      'Content-Type': io.ContentType.json.value,
    },
  );
}

Response $notFound(Request request) => Response.notFound(
      jsonEncode(<String, Object?>{
        'error': <String, Object?>{
          'status': io.HttpStatus.notFound,
          'message': 'Not Found',
          'details': <String, Object?>{
            'path': request.url.path,
            'method': request.method,
            'headers': request.headers,
          },
        },
      }),
      headers: <String, String>{
        'Content-Type': io.ContentType.json.value,
      },
    );

/// Escape all HTML special characters `<` & `>` in [text].
String _escape(String text) => text.replaceAll('<', '&lt;').replaceAll('>', '&gt;');

final _$buffer = StringBuffer();
Map<String, Object?> _mapSearchResult2InlineQueryResponse(int index, Map<String, Object?> data) {
  final id = index + 1;
  final title = data['name'];
  final subtitle = '${data['kind']} in ${data['library']}';
  _$buffer
    ..clear()
    ..write('<b>${data['name']}</b>')
    ..write(' (<i>${data['kind']} in ${data['library']}</i>)');
  final description = data['description'];
  if (description != null) {
    _$buffer
      ..writeln()
      ..writeln()
      ..writeln('<pre>\n${_escape(description.toString())}\n</pre>');
  }
  return <String, Object?>{
    'type': 'article',
    'id': id,
    'title': title,
    'description': subtitle,
    'input_message_content': <String, Object?>{
      'message_text': _$buffer.toString(),
      // Telegram does not escape some markdown characters with MarkdownV2
      // https://stackoverflow.com/questions/40626896/telegram-does-not-escape-some-markdown-characters
      'parse_mode': 'HTML', // HTML, Markdown, MarkdownV2
      'disable_web_page_preview': true,
      // https://core.telegram.org/bots/api#messageentity
      //'entities': <Map<String, Object?>>[],
    },
    'reply_markup': <String, Object?>{
      'inline_keyboard': <List<Map<String, Object?>>>[
        <Map<String, Object?>>[
          <String, Object?>{
            'text': 'Stable API',
            'url': 'https://api.flutter.dev/flutter/search.html?' 'q=$title',
          },
          <String, Object?>{
            'text': 'Master API',
            'url': 'https://master-api.flutter.dev/flutter/search.html?'
                'q=$title',
          },
        ],
        <Map<String, Object?>>[
          /* Add "Ask Chat GPT" button */
          <String, Object?>{
            'text': 'Google',
            'url': 'https://www.google.com/search?'
                'q=site%3Aapi.flutter.dev+$title',
          },
          <String, Object?>{
            'text': 'Bing',
            'url': 'https://www.bing.com/search?'
                'q=Flutter+$title',
          },
        ],
      ],
    },
  };
}

/// Extension on [Request] to provide access to the database and search service.
extension on Request {
  /// Returns the database instance from the request context.
  Database get database => context['db'] as Database;

  /// Returns the search service instance from the request context.
  SearchService get searchService => context['search'] as SearchService;
}
