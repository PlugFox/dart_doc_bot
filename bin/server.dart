import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dart_doc_bot/src/database/database.dart';
import 'package:dart_doc_bot/src/server/logger.dart';
import 'package:dart_doc_bot/src/server/shared_server.dart';
import 'package:path/path.dart' as p;

@pragma('vm:entry-point')
void main([List<String>? args]) => runZonedGuarded<Future<void>>(() async {
      final cpuCount = math.max(io.Platform.numberOfProcessors ~/ 2, 1);
      final tempDir = io.Directory('.temp').absolute;
      final db = Database.lazy(
        file: io.File(p.join(tempDir.absolute.path, 'db.sqlite')),
      );
      for (var i = 1; i <= cpuCount; i++) {
        final receivePort = ReceivePort();
        // ignore: unused_local_variable
        SendPort? sendPort;
        final server = SharedServer(
          httpAddress:
              io.InternetAddress.anyIPv4, //io.InternetAddress.loopbackIPv4,
          httpPort: 8080,
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
    }, (error, stackTrace) {
      //Error.safeToString(error);
      //stackTrace.toString();
      severe('Error: error, stackTrace: stackTrace');
      io.exit(2);
    });
