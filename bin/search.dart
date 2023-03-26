import 'dart:async';
import 'dart:io' as io;

import 'package:dart_doc_bot/src/database/database.dart';
import 'package:dart_doc_bot/src/search/search_service.dart';
import 'package:dart_doc_bot/src/server/logger.dart';
import 'package:path/path.dart' as p;

// dart compile exe ./bin/search.dart -o ./.temp/search > /dev/null
// time ./.temp/search "ListTile"
void main(List<String> args) => runZonedGuarded<void>(() async {
      final tempDir = io.Directory('.temp').absolute;
      final db = Database.lazy(
        file: io.File(p.join(tempDir.absolute.path, 'db.sqlite')),
        dropDatabase: false,
      );
      final stopwatch = Stopwatch()..start();
      final result = await SearchService(database: db).search(args.join(' '));
      config('Elapsed: ${(stopwatch..stop()).elapsedMilliseconds} ms\n');
      _output(result);
      io.exit(0);
    }, (error, stackTrace) {
      severe('Error: $error\n$stackTrace');
      io.exit(1);
    });

void _output(List<Map<String, Object?>> results) {
  final buffer = StringBuffer();
  String name, kind, library;
  for (final result in results) {
    name = result['name']! as String;
    kind = result['kind']! as String;
    library = result['library']! as String;
    name = name.length > 40 ? '${name.substring(0, 40 - 3)}...' : name.padRight(40);
    kind = kind.length > 12 ? '${kind.substring(0, 12 - 3)}...' : kind.padRight(12);
    library = library.length > 24 ? '${library.substring(0, 24 - 3)}...' : library.padRight(24);
    buffer.writeln('$name | $kind | $library');
  }
  config(buffer.toString());
}
