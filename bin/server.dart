import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dart_doc_bot/src/database/database.dart';
import 'package:dart_doc_bot/src/server/logger.dart';
import 'package:dart_doc_bot/src/server/shared_server.dart';
import 'package:rxdart/rxdart.dart';

@pragma('vm:entry-point')
void main([List<String>? args]) => runZonedGuarded<Future<void>>(() async {
      fine('Starting server...');
      final cpuCount = math.max(io.Platform.numberOfProcessors, 2);
      final Database db;
      try {
        final dbFile = await io.Directory.current
            .list(recursive: true)
            .whereType<io.File>()
            .where((e) => e.path.endsWith('.sqlite'))
            .first;
        fine('Using database: ${dbFile.absolute.path}');
        db = Database.lazy(
          file: io.File(dbFile.absolute.path),
        );
      } on StateError {
        severe('Database not found, try to generate it first.');
        rethrow;
      } on Object {
        severe('Problem with database initialization.');
        rethrow;
      }
      const httpPort = 8080;
      fine('Starting $cpuCount server(s) on port $httpPort');
      for (var i = 1; i <= cpuCount; i++) {
        final receivePort = ReceivePort();
        // ignore: unused_local_variable
        SendPort? sendPort;
        final server = SharedServer(
          httpAddress: io.InternetAddress.anyIPv4, // io.InternetAddress.loopbackIPv4
          httpPort: httpPort,
          sendPort: receivePort.sendPort,
          label: 'Server#$i',
          database: await db.serializableConnection(),
        );
        await server();
        receivePort.listen(
          (message) {
            if (message is SendPort) sendPort = message;
          },
          cancelOnError: false,
        );
      }
      config('Server started on port $httpPort');
    }, (error, stackTrace) {
      severe('Error: $error\n\n$stackTrace');
      io.exit(2);
    });
