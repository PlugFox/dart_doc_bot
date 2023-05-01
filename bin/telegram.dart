import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;

const String apiUrl = 'https://api.telegram.org/bot';
final String botToken = io.Platform.environment['TG_BOT_TOKEN'] ?? (throw Exception('No bot token provided'));

void main() async {
  int lastUpdateId = 0;

  while (true) {
    var updates = await getUpdates(lastUpdateId + 1);

    for (var update in updates) {
      final updateId = update['update_id'];
      if (updateId is int) lastUpdateId = updateId;

      final inlineQuery = update['inline_query'];
      if (inlineQuery is Map<String, Object?>) {
        handleInlineQuery(inlineQuery);
      }
    }

    await Future<void>.delayed(Duration(seconds: 1));
  }
}

Future<List<Map<String, Object?>>> getUpdates(int offset) async {
  final response = await http.get(Uri.parse('${apiUrl}${botToken}/getUpdates?offset=$offset'));
  const $empty = <Map<String, Object?>>[];
  if (response.statusCode != 200) return $empty;
  var jsonResponse = jsonDecode(response.body) as Object?;
  if (jsonResponse is! Map<String, Object?>) return $empty;
  if (jsonResponse['ok'] != true) return $empty;
  final result = jsonResponse['result'];
  if (result is! List) return $empty;
  return result.whereType<Map<String, Object?>>().toList();
}

Future<void> handleInlineQuery(Map<String, Object?> inlineQuery) async {
  final queryId = inlineQuery['id'];
  final queryText = inlineQuery['query'];

  // Prepare your results based on the queryText
  final results = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'article',
      'id': '1',
      'title': 'Example Result',
      'description': 'This is an example result',
      'input_message_content': <String, Object?>{
        'message_text': 'You searched for: $queryText',
        'parse_mode': 'MarkdownV2',
        'disable_web_page_preview': false,
        // https://core.telegram.org/bots/api#messageentity
        //'entities': <Map<String, Object?>>[],
      },
      'reply_markup': <String, Object?>{
        'inline_keyboard': <List<Map<String, Object?>>>[
          <Map<String, Object?>>[
            <String, Object?>{
              'text': 'Stable Flutter',
              'url': 'https://api.flutter.dev/flutter/search.html?' 'q=$queryText',
            },
            <String, Object?>{
              'text': 'Master Flutter',
              'url': 'https://master-api.flutter.dev/flutter/search.html?'
                  'q=$queryText',
            },
          ],
          <Map<String, Object?>>[
            /* Add "Ask Chat GPT" button */
            <String, Object?>{
              'text': 'Google',
              'url': 'https://www.google.com/search?'
                  'q=site%3Aapi.flutter.dev+$queryText',
            },
            <String, Object?>{
              'text': 'Bing',
              'url': 'https://www.bing.com/search?'
                  'q=Flutter+$queryText',
            },
          ],
        ],
      },
    },
  ];

  final response = await http.post(
    Uri.parse('${apiUrl}${botToken}/answerInlineQuery'),
    headers: <String, String>{'Content-Type': 'application/json'},
    body: jsonEncode(
      <String, Object?>{
        'inline_query_id': queryId,
        'cache_time': 3600,
        'results': results,
      },
    ),
  );

  if (response.statusCode != 200) {
    print('Failed to answer inline query: ${response.body}');
  }
}
