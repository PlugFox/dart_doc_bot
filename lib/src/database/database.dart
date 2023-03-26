import 'dart:developer';
import 'dart:io' as io;

import 'package:drift/drift.dart';
import 'package:drift/native.dart' as ffi;
import 'package:meta/meta.dart';

import 'queries.dart';

export 'package:drift/drift.dart' hide DatabaseOpener;
export 'package:drift/isolate.dart';

part 'database.g.dart';

/// Drop database on start
/// --dart-define=DROP_DATABASE=true
const _kDropTables = bool.fromEnvironment('DROP_DATABASE');

/// Key-value storage interface for SQLite database
abstract class IKeyValueStorage {
  Future<void> refresh();

  String? getKey(String key);

  void addKey(String key, String value);

  void removeKey(String key);

  Map<String, String> getAll([Set<String>? keys]);

  void addAll(Map<String, String> data);

  void removeAll([Set<String>? keys]);
}

@DriftDatabase(
  include: <String>{
    'ddl/kv.drift',
    'ddl/entity.drift',
  },
  tables: <Type>[],
  daos: <Type>[],
  queries: $queries,
)
class Database extends _$Database
    with DatabaseKeyValueMixin
    implements GeneratedDatabase, DatabaseConnectionUser, QueryExecutorUser, IKeyValueStorage {
  /// Creates a database that will store its result in the [path], creating it
  /// if it doesn't exist.
  ///
  /// If [logStatements] is true (defaults to `false`), generated sql statements
  /// will be printed before executing. This can be useful for debugging.
  /// The optional [setup] function can be used to perform a setup just after
  /// the database is opened, before moor is fully ready. This can be used to
  /// add custom user-defined sql functions or to provide encryption keys in
  /// SQLCipher implementations.
  Database.lazy({
    required io.File file,
    ffi.DatabaseSetup? setup,
    bool logStatements = false,
    bool dropDatabase = false,
  }) : super(
          LazyDatabase(
            () => _opener(
              file: file,
              setup: setup,
              logStatements: logStatements,
              dropDatabase: dropDatabase,
            ),
          ),
        );

  /// Creates a database from an existing [executor].
  Database.connect(super.connection);

  static Future<QueryExecutor> _opener({
    required io.File file,
    ffi.DatabaseSetup? setup,
    bool logStatements = false,
    bool dropDatabase = false,
  }) async {
    try {
      if ((dropDatabase || _kDropTables) && file.existsSync()) {
        await file.delete();
      }
    } on Object catch (e, st) {
      log(
        "Can't delete database file: $file",
        level: 900,
        name: 'database',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
    return ffi.NativeDatabase.createInBackground(
      file,
      logStatements: logStatements,
      setup: setup,
    );
  }

  /// Creates an in-memory database won't persist its changes on disk.
  ///
  /// If [logStatements] is true (defaults to `false`), generated sql statements
  /// will be printed before executing. This can be useful for debugging.
  /// The optional [setup] function can be used to perform a setup just after
  /// the database is opened, before moor is fully ready. This can be used to
  /// add custom user-defined sql functions or to provide encryption keys in
  /// SQLCipher implementations.
  Database.memory({
    ffi.DatabaseSetup? setup,
    bool logStatements = false,
  }) : super(
          ffi.NativeDatabase.memory(
            logStatements: logStatements,
            setup: setup,
          ),
        );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => DatabaseMigrationStrategy(
        database: this,
      );
}

/// Handles database migrations by delegating work to [OnCreate] and [OnUpgrade]
/// methods.
@immutable
class DatabaseMigrationStrategy implements MigrationStrategy {
  /// Construct a migration strategy from the provided [onCreate] and
  /// [onUpgrade] methods.
  const DatabaseMigrationStrategy({
    required Database database,
  }) : _db = database;

  /// Database to use for migrations.
  final Database _db;

  /// Executes when the database is opened for the first time.
  @override
  OnCreate get onCreate => (m) async {
        //await _db.customStatement('PRAGMA writable_schema=ON;');
        await m.createAll();
      };

  /// Executes when the database has been opened previously, but the last access
  /// happened at a different [GeneratedDatabase.schemaVersion].
  /// Schema version upgrades and downgrades will both be run here.
  @override
  OnUpgrade get onUpgrade => (m, from, to) async {
        //await _db.customStatement('PRAGMA writable_schema=ON;');
        return _update(_db, m, from, to);
      };

  /// Executes after the database is ready to be used (ie. it has been opened
  /// and all migrations ran), but before any other queries will be sent. This
  /// makes it a suitable place to populate data after the database has been
  /// created or set sqlite `PRAGMAS` that you need.
  @override
  OnBeforeOpen get beforeOpen => (details) async {};

  /// https://moor.simonbinder.eu/docs/advanced-features/migrations/
  static Future<void> _update(Database db, Migrator m, int from, int to) async {
    m.createAll();
    if (from >= to) return;
  }
}

mixin DatabaseKeyValueMixin on _$Database implements IKeyValueStorage {
  bool _$isInitialized = false;
  final Map<String, String> _$store = <String, String>{};

  @override
  Future<void> refresh() => select(kv).get().then<void>((values) {
        _$isInitialized = true;
        _$store
          ..clear()
          ..addAll(<String, String>{for (final kv in values) kv.k: kv.v});
      });

  @override
  String? getKey(String key) {
    assert(_$isInitialized, 'Database is not initialized');
    return _$store[key];
  }

  @override
  void addKey(String key, String value) {
    assert(_$isInitialized, 'Database is not initialized');
    _$store[key] = value;
    into(kv).insertOnConflictUpdate(KvCompanion.insert(k: key, v: value)).ignore();
  }

  @override
  void removeKey(String key) {
    assert(_$isInitialized, 'Database is not initialized');
    _$store.remove(key);
    (delete(kv)..where((tbl) => tbl.k.equals(key))).go().ignore();
  }

  @override
  Map<String, String> getAll([Set<String>? keys]) {
    assert(_$isInitialized, 'Database is not initialized');
    return keys == null
        ? Map<String, String>.of(_$store)
        : keys.isEmpty
            ? <String, String>{}
            : <String, String>{
                for (final e in _$store.entries)
                  if (keys.contains(e.key)) e.key: e.value,
              };
  }

  @override
  void addAll(Map<String, String> data) {
    assert(_$isInitialized, 'Database is not initialized');
    if (data.isEmpty) return;
    _$store.addAll(data);
    batch(
      (b) => b.insertAllOnConflictUpdate(
        kv,
        [for (final e in data.entries) KvCompanion.insert(k: e.key, v: e.value)],
      ),
    ).ignore();
  }

  @override
  void removeAll([Set<String>? keys]) {
    assert(_$isInitialized, 'Database is not initialized');
    if (keys == null) {
      _$store.clear();
      delete(kv).go().ignore();
    } else if (keys.isNotEmpty) {
      _$store.removeWhere((k, v) => keys.contains(k));
      (delete(kv)..where((tbl) => tbl.k.isIn(keys))).go().ignore();
    }
  }
}
