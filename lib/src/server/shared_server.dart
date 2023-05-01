import 'dart:io' as io;
import 'dart:isolate';

import 'package:dart_doc_bot/src/search/search_service.dart';
import 'package:dart_doc_bot/src/server/middleware/cors.dart';
import 'package:dart_doc_bot/src/server/middleware/injector.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../database/database.dart';
import 'logger.dart';
import 'middleware/errors.dart';
import 'router.dart';

class SharedServer {
  SharedServer({
    required this.httpAddress,
    required this.httpPort,
    required this.sendPort,
    required this.label,
    required this.database,
  });

  final io.InternetAddress httpAddress;
  final int httpPort;
  final SendPort sendPort;
  final String label;
  final DriftIsolate database;

  Future<Isolate> call() => Isolate.spawn<SharedServer>(
        _endpoint,
        this,
        debugName: 'Isolate($label)',
        errorsAreFatal: true,
      );

  /// The entry point for the isolate.
  static void _endpoint(SharedServer args) => Future<void>(() async {
        fine('Starting isolate ${Isolate.current.debugName ?? 'unknown'}');
        final receivePort = ReceivePort();
        args.sendPort.send(receivePort.sendPort);
        receivePort.listen((Object? message) {/* ... */});
        final database = Database.connect(await args.database.connect());
        final searchService = SearchService(database: database);
        final pipeline = Pipeline()
            .addMiddleware(
              handleErrors(),
            )
            .addMiddleware(
              logRequests(
                logger: (msg, isError) => isError ? warning(msg) : fine(msg),
              ),
            )
            .addMiddleware(cors())
            .addMiddleware(
              injector(
                <String, Object>{
                  'db': database,
                  'search': searchService,
                },
              ),
            )
            .addHandler($router);
        final server = await shelf_io.serve(
          pipeline,
          args.httpAddress,
          args.httpPort,
          poweredByHeader: 'Fox\'s Dart Doc Bot',
          shared: true,
        );
        config('Server running on ${server.address}:${server.port}');
      });
}
