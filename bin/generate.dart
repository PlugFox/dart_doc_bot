import 'dart:async';
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:collection/collection.dart';
import 'package:dart_doc_bot/src/database/database.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';

// dart run bin/generate.dart
void main(List<String> args) => runZonedGuarded<void>(() async {
      final tempDir = io.Directory('.temp').absolute;
      /* if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      tempDir.createSync(); */
      //final packageDir = io.Directory(p.join(tempDir.absolute.path, 'package'));
      //await _cloneTo(packageDir);
      final dbFile = io.File(p.join(tempDir.absolute.path, 'db.sqlite'));
      final db = Database.lazy(
        file: dbFile,
        dropDatabase: true,
      );
      await db.customStatement('PRAGMA journal_mode = WAL;');
      await _extract(
        <String>[
          // Cloned package:
          //packageDir.absolute.path,

          // Dart SDK from brew:
          '/opt/homebrew/opt/dart/libexec/lib',

          // Dart SDK from fvm:
          //'/Users/mm/fvm/versions/stable/bin/cache/dart-sdk/lib',

          // Flutter SDK from fvm:
          '/Users/mm/fvm/versions/stable/packages/flutter/lib',
        ],
      ).bufferCount(500).asyncMap<void>((chunk) => _write(db, chunk)).drain();
      await db.customStatement('VACUUM;');
      // Add stat info:
      await _addStats(
        db,
        <String, int>{
          'size': dbFile.lengthSync(),
        },
      );
      io.exit(0);
    }, (error, stackTrace) {
      print('Error: $error\n$stackTrace');
      io.exit(1);
    });

/*
Future<void> _cloneTo(io.Directory packageDir, String url) async {
  final result = await io.Process.run(
    'git',
    <String>[
      'clone',
      '--branch=master',
      '--depth=1',
      url,
      packageDir.absolute.path,
    ],
    runInShell: true,
  );
  switch (result.exitCode) {
    case 0:
      print('Repository cloned successfully');
      break;
    default:
      print('Error cloning repository\n'
          'Exit code: ${result.exitCode}\n'
          'Standard output: ${result.stdout}\n'
          'Standard error: ${result.stderr}');
      io.exit(result.exitCode);
  }
}
*/

Stream<Insertable> _extract(List<String> includedPaths) =>
    Stream<AnalysisContextCollection>.value(
      AnalysisContextCollection(
        includedPaths: includedPaths,
      ),
    )
        .expand<AnalysisContext>((collection) => collection.contexts)
        .asyncExpand<SomeResolvedLibraryResult>((context) =>
            Stream<String>.fromIterable(context.contextRoot
                    .analyzedFiles()
                    .map<String>((e) => e.trim())
                    .where((e) => e.endsWith('.dart'))
                    .where((e) => !e.endsWith('_test.dart')))
                .asyncMap<SomeResolvedLibraryResult>(
                    (path) => context.currentSession.getResolvedLibrary(path)))
        .where((result) => result is! NotLibraryButPartResult)
        .where((result) => result is ResolvedLibraryResult)
        .cast<ResolvedLibraryResult>()
        .map<LibraryElement>((result) => result.element)
        .where((lib) => lib.name.isNotEmpty)
        .expand<Insertable>(_processLibrary);

Iterable<Insertable> _processLibrary(LibraryElement library) =>
    library.source.fullName.isEmpty
        ? <Insertable>[]
        : library.exportNamespace.definedNames.values
            .expand<Insertable>((element) => _processElement(library, element));

Iterable<Insertable> _processElement(
  LibraryElement library,
  Element element, [
  String? parentId,
]) sync* {
  final name = element.name?.trim();
  var path = element.source?.fullName.trim();
  final libPath = library.source.fullName.trim();
  if (path == null ||
      name == null ||
      name.isEmpty ||
      Identifier.isPrivateName(name) ||
      element.isPrivate) return;
  final dirName = p.dirname(libPath);
  if (!p.isWithin(dirName, path)) return;
  path = p.relative(path, from: dirName);
  final id = _generateId(path, name, parentId);
  final description = _formatDescription(element.documentationComment);
  var libraryName = library.name;
  if (libraryName.startsWith('dart.')) {
    libraryName = libraryName.replaceRange(0, 5, 'dart:');
  }
  yield EntityCompanion.insert(
    id: id,
    library: libraryName,
    name: name,
    kind: element.kind.displayName,
    path: path,
    parentId: Value<String?>(parentId),
    description: Value<String?>(description),
  );

  //final isInterface = element is InterfaceElement;
  // Tokenize name
  final lowerName = name.toLowerCase();
  final tokens = _tokenize(lowerName)
      .groupFoldBy<String, int>((e) => e, (p, n) => (p ?? 0) + 1)
      .entries
      .toList(growable: false);
  if (tokens.isNotEmpty) {
    yield PrefixCompanion.insert(
      token: tokens.first.key,
      entityId: id,
      len: lowerName.length,
      name: lowerName,
    );
    yield* tokens.map<Insertable>(
      (e) => TrigramCompanion.insert(
        token: e.key,
        entityId: id,
        count: e.value,
      ),
    );
  }

  yield* element.children
      .expand<Insertable>((element) => _processElement(library, element, id));
}

String _generateId(String path, String name, String? parentId) =>
    parentId == null
        ? '${path.hashCode.toRadixString(36)}/$name'
        : '$parentId/$name';

final RegExp _$exp = RegExp(r'[^a-zA-Z0-9a-яА-ЯёЁ]+');
Iterable<String> _tokenize(String? text) {
  if (text == null || text.length < 3) return const <String>[];
  return text.toLowerCase().split(_$exp).expand((word) sync* {
    if (word.length < 3) return;
    for (int i = 0; i <= word.length - 3; i++) {
      yield word.substring(i, i + 3);
    }
  });
}

Future<void> _write(Database db, List<Insertable> companions) =>
    db.batch((batch) {
      final entities = companions
          .whereType<EntityCompanion>()
          .groupFoldBy<String, EntityCompanion>((e) => e.id.value, (_, n) => n)
          .values
          .toList();
      final trigrams = companions
          .whereType<TrigramCompanion>()
          .groupFoldBy<String, TrigramCompanion>(
              (e) => '${e.entityId.value}/${e.token}',
              (p, n) => p == null || p.count.value <= n.count.value ? n : p)
          .values
          .toList();
      final prefixes = companions
          .whereType<PrefixCompanion>()
          .groupFoldBy<String, PrefixCompanion>(
              (e) => e.entityId.value, (_, n) => n)
          .values
          .toList();
      if (entities.isNotEmpty)
        batch.insertAll(db.entity, entities, mode: InsertMode.insertOrIgnore);
      if (trigrams.isNotEmpty)
        batch.insertAll(db.trigram, trigrams, mode: InsertMode.insertOrIgnore);
      if (prefixes.isNotEmpty)
        batch.insertAll(db.prefix, prefixes, mode: InsertMode.insertOrIgnore);
    });

final _$buffer = StringBuffer();
final _$md = RegExp(r'[#`\[\]()]');
String? _formatDescription(String? description) {
  if (description == null) return null;
  _$buffer.clear();
  final lines = description.split('\n');
  int counter = 0;
  for (var line in lines) {
    if (line.contains('```')) break;
    if (line.contains('{@')) continue;
    if (line.startsWith('///')) {
      line = line.substring(3);
    } else if (line.startsWith('/*') ||
        line.startsWith(' *') ||
        line.startsWith('*/') ||
        line.startsWith('//')) {
      line = line.substring(2);
    } else if (line.startsWith('*')) {
      line = line.substring(1);
    }
    line = line.trim();
    if (line.isEmpty) {
      counter++;
      if (counter > 5) break;
    } else if (line.contains('See also')) {
      break;
    } else {
      line = line.replaceAll('](', ' ').replaceAll(_$md, '');
    }
    _$buffer.writeln(line);
  }
  var string = _$buffer.toString().trim().replaceAll('\r\n', '\n');
  while (string.contains('\n\n\n')) {
    string = string.replaceAll('\n\n\n', '\n\n');
  }
  return string.isEmpty ? null : string;
}

Future<void> _addStats(Database db,
        [Map<String, int> custom = const <String, int>{}]) =>
    db.customStatement('''
INSERT OR REPLACE INTO kv (k, v)
SELECT
	k, v
FROM (
	-- Libraries
	SELECT 'libraries' AS k, COUNT(1) AS v
	FROM (SELECT 1 FROM entity GROUP BY library)

	UNION ALL

	-- Entities
	SELECT 'entities', COUNT(1)
	FROM entity

	UNION ALL

	-- Prefixes
	SELECT 'prefixes', COUNT(1)
	FROM prefix

	UNION ALL

	-- Trigrams
	SELECT 'trigrams', COUNT(1)
	FROM trigram

	UNION ALL

	-- Updated at
	SELECT 'updated', MAX(updated_at)
	FROM entity

  ${custom.entries.map<String>((e) => '	UNION ALL SELECT \'${e.key}\', ${e.value}').join('\n')}
)
''');
