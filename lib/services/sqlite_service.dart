import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'db_service.dart';
import 'safe_query.dart';
import 'sqlite_introspector.dart';
import 'sqlite_table_repository.dart';

/// [DbService] implementation backed by a local SQLite database file.
///
/// The `sqlite3` driver is synchronous FFI; the async surface here just
/// wraps those calls. For a single-user tool pointed at local files the
/// queries are fast enough that blocking the UI isolate is acceptable —
/// there is no isolate offload.
class SqliteService implements DbService {
  SqliteService(this.config, {this.onQueryRun, this.onEditApplied});

  @override
  final ConnectionConfig config;

  /// Fires for every statement that crosses the driver. Chatty `PRAGMA`
  /// introspection passes `log: false` so it stays out of the activity log.
  final QueryLogger? onQueryRun;

  /// Called after every applied cell-edit batch.
  final EditLogger? onEditApplied;

  /// Mirrors [PostgresService.defaultSelectLimit]: bare `SELECT`s without a
  /// `LIMIT` are capped so an unbounded scan can't materialise a huge table.
  static const defaultSelectLimit = 10000;

  /// Creates a fresh, empty SQLite database file at [path], replacing any
  /// file already there. The header write forces SQLite to materialise the
  /// file on disk so [connect]'s existence check passes afterwards.
  static void createDatabaseFile(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    sqlite3.open(path)
      ..execute('PRAGMA user_version = 0;')
      ..dispose();
  }

  Database? _db;
  SqliteTableRepository? _repository;

  @override
  bool get isConnected => _db != null;

  /// The open handle. Throws [StateError] before [connect] / after [close].
  Database get conn {
    final d = _db;
    if (d == null) throw StateError('Not connected');
    return d;
  }

  @override
  Future<void> connect() async {
    final path = config.filePath.trim();
    if (path.isEmpty) {
      throw Exception('No SQLite database file was specified.');
    }
    if (!File(path).existsSync()) {
      throw Exception('SQLite database file not found: $path');
    }
    _db = sqlite3.open(
      path,
      mode: config.readOnly ? OpenMode.readOnly : OpenMode.readWrite,
    );
    _repository = SqliteTableRepository(this);
  }

  @override
  Future<void> close() async {
    _db?.dispose();
    _db = null;
    _repository = null;
  }

  TableRepository get tableRepository {
    final r = _repository;
    if (r == null) throw StateError('Not connected');
    return r;
  }

  @override
  Introspector get introspector => SqliteIntrospector(this);

  /// Runs a row-returning statement and reports it to [onQueryRun]. Internal
  /// introspection passes `log: false` to keep the activity log uncluttered.
  ResultSet select(
    String sql, {
    List<Object?> params = const [],
    bool log = true,
  }) {
    final watch = Stopwatch()..start();
    try {
      final rs = conn.select(sql, params);
      watch.stop();
      if (log) {
        onQueryRun?.call(
          sql: sql,
          elapsed: watch.elapsed,
          affectedRows: rs.columnNames.isEmpty ? conn.updatedRows : null,
          error: null,
        );
      }
      return rs;
    } catch (e) {
      watch.stop();
      if (log) {
        onQueryRun?.call(
          sql: sql,
          elapsed: watch.elapsed,
          affectedRows: null,
          error: e.toString(),
        );
      }
      rethrow;
    }
  }

  /// Runs a statement with no result set (used for the edit-batch
  /// mutations), reporting it to [onQueryRun].
  void run(String sql, {List<Object?> params = const []}) {
    final watch = Stopwatch()..start();
    try {
      conn.execute(sql, params);
      watch.stop();
      onQueryRun?.call(
        sql: sql,
        elapsed: watch.elapsed,
        affectedRows: conn.updatedRows,
        error: null,
      );
    } catch (e) {
      watch.stop();
      onQueryRun?.call(
        sql: sql,
        elapsed: watch.elapsed,
        affectedRows: null,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Rows changed by the most recent INSERT/UPDATE/DELETE.
  int get updatedRows => conn.updatedRows;

  @override
  Future<QueryResult> runQuery(String sql) async {
    final safe = applyDefaultLimit(sql, limit: defaultSelectLimit);
    final watch = Stopwatch()..start();
    try {
      final rs = select(safe.sql);
      watch.stop();
      if (rs.columnNames.isEmpty) {
        return QueryResult.command(
          affectedRows: updatedRows,
          elapsed: watch.elapsed,
        );
      }
      final columns = List<String>.from(rs.columnNames);
      return QueryResult.rows(
        columns: columns,
        rows: [for (final r in rs.rows) List<Object?>.from(r)],
        elapsed: watch.elapsed,
        columnSchemas: [
          for (final n in columns) ResultColumnSchema(name: n),
        ],
        truncatedAt: safe.appliedLimit ? defaultSelectLimit : null,
      );
    } on SqliteException catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.message, elapsed: watch.elapsed);
    } catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.toString(), elapsed: watch.elapsed);
    }
  }

  @override
  Future<int> countRows(DbTable table, {String filter = ''}) =>
      tableRepository.countRows(table, filter: filter);

  @override
  Future<QueryResult> fetchTablePage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) => tableRepository.fetchPage(
    table,
    limit: limit,
    offset: offset,
    filter: filter,
    orderBy: orderBy,
    selectList: selectList,
  );

  @override
  Future<QueryResult> fetchAllTableRows(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) => tableRepository.fetchAll(
    table,
    filter: filter,
    orderBy: orderBy,
    selectList: selectList,
  );

  @override
  Future<String> loadTableDdl(DbTable table) =>
      tableRepository.loadDdl(table);

  @override
  List<String> previewEditStatements(DbTable table, EditBatch batch) =>
      buildSqliteEditStatements(table, batch);

  @override
  Future<int> applyTableEdits(DbTable table, EditBatch batch) async {
    final watch = Stopwatch()..start();
    try {
      final affected = await tableRepository.applyEdits(table, batch);
      watch.stop();
      onEditApplied?.call(
        statementCount: batch.statementCount,
        elapsed: watch.elapsed,
        error: null,
      );
      return affected;
    } catch (e) {
      watch.stop();
      onEditApplied?.call(
        statementCount: batch.statementCount,
        elapsed: watch.elapsed,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Reduces `sqlite_version()` (e.g. `3.45.1`) to a `vMAJOR.MINOR` tag.
  @override
  Future<String?> fetchVersionTag() async {
    try {
      final rs = select('SELECT sqlite_version()', log: false);
      if (rs.rows.isEmpty) return null;
      final s = rs.rows.first.first?.toString().trim() ?? '';
      if (s.isEmpty) return null;
      final parts = s.split('.');
      return parts.length >= 2
          ? 'v${parts[0]}.${parts[1]}'
          : 'v${parts.first}';
    } catch (_) {
      return null;
    }
  }
}
