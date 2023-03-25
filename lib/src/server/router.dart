import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_doc_bot/src/database/database.dart';
import 'package:dart_doc_bot/src/search/search_service.dart';
import 'package:multiline/multiline.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'middleware/errors.dart';

final Handler $router = Router(notFoundHandler: notFound)
  ..get('/stat', stat)
  ..get('/search', search)
  ..get('/health', healthCheck);

Response healthCheck(Request request) => Response.ok(
      '{"data": {"status": "ok"}}',
      headers: <String, String>{
        'Content-Type': io.ContentType.json.value,
      },
    );

Future<Response> stat(Request request) async {
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
            if (stat.data.containsKey('k'))
              stat.data['k'].toString(): stat.data['v'],
        },
      },
    ),
    headers: <String, String>{
      'Content-Type': io.ContentType.json.value,
    },
  );
}

Future<Response> search(Request request) async {
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

Future<Response> notFound(Request request) async => Response.notFound(
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

extension on Request {
  /// Returns the database instance from the request context.
  Database get database => context['db'] as Database;

  /// Returns the search service instance from the request context.
  SearchService get searchService => context['search'] as SearchService;
}
