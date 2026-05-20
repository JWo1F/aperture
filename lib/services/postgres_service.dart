import 'package:postgres/postgres.dart';

import '../models/cell_edit.dart';
import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'driver_decoder.dart';
import 'introspector.dart';
import 'safe_query.dart';
import 'table_repository.dart';

export 'table_repository.dart'
    show
        TableRepository,
        StaleRowException,
        EditFailureException,
        buildEditStatements;

List<Object?> _decodeRow(List<Object?> raw) =>
    [for (final v in raw) decodeDriverValue(v)];

/// Facade over a single live Postgres connection. Owns the connection
/// lifecycle ([connect] / [close]) and free-form statement execution
/// ([runQuery]). Per-relation operations live on [TableRepository];
/// catalog introspection lives on [Introspector] — both bound to the
/// same open connection.
class PostgresService {
  PostgresService(this.config);

  final ConnectionConfig config;
  Connection? _connection;
  TableRepository? _repository;

  bool get isConnected => _connection?.isOpen ?? false;

  Future<void> connect() async {
    _connection = await Connection.open(
      Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
      ),
      settings: ConnectionSettings(
        sslMode: config.useSsl ? SslMode.require : SslMode.disable,
        connectTimeout: const Duration(seconds: 10),
        applicationName: 'dbv',
      ),
    );
    _repository = TableRepository(_connection!);
  }

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
    _repository = null;
  }

  Connection get _conn {
    final c = _connection;
    if (c == null || !c.isOpen) {
      throw StateError('Not connected');
    }
    return c;
  }

  TableRepository get tableRepository {
    final r = _repository;
    if (r == null) throw StateError('Not connected');
    return r;
  }

  /// Catalog introspector bound to this connection.
  Introspector get introspector => Introspector(_conn);

  // --- Delegations preserved so existing call sites compile ----------

  Future<int> countRows(DbTable table, {String filter = ''}) =>
      tableRepository.countRows(table, filter: filter);

  Future<QueryResult> fetchTablePage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) =>
      tableRepository.fetchPage(
        table,
        limit: limit,
        offset: offset,
        filter: filter,
        orderBy: orderBy,
        selectList: selectList,
      );

  Future<QueryResult> fetchAllTableRows(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) =>
      tableRepository.fetchAll(
        table,
        filter: filter,
        orderBy: orderBy,
        selectList: selectList,
      );

  Future<String> loadTableDdl(DbTable table) =>
      tableRepository.loadDdl(table);

  Future<int> applyTableEdits(
    DbTable table,
    Map<String, Map<String, CellEditValue>> updatesByCtid,
  ) =>
      tableRepository.applyEdits(table, updatesByCtid);

  /// Default cap applied to bare top-level `SELECT` statements that don't
  /// carry their own LIMIT. Prevents an unbounded `SELECT *` from
  /// materialising an entire billion-row table in the isolate. Statements
  /// that aren't a plain SELECT — anything starting with `WITH`, `INSERT`,
  /// DDL, etc. — pass through untouched.
  static const defaultSelectLimit = 10000;

  /// Executes an arbitrary statement, capturing timing and errors so the UI
  /// never has to deal with raised exceptions directly.
  Future<QueryResult> runQuery(String sql) async {
    final safe = applyDefaultLimit(sql, limit: defaultSelectLimit);
    final watch = Stopwatch()..start();
    try {
      final result = await _conn.execute(safe.sql);
      watch.stop();

      if (result.schema.columns.isEmpty) {
        return QueryResult.command(
          affectedRows: result.affectedRows,
          elapsed: watch.elapsed,
        );
      }

      final columns = result.schema.columns
          .map((c) => c.columnName ?? 'column')
          .toList();
      final columnSchemas = result.schema.columns
          .map(
            (c) => ResultColumnSchema(
              name: c.columnName ?? 'column',
              tableOid: c.tableOid,
              columnAttNum: c.columnOid,
            ),
          )
          .toList();
      final rows = [for (final row in result) _decodeRow(row.toList())];

      return QueryResult.rows(
        columns: columns,
        rows: rows,
        elapsed: watch.elapsed,
        affectedRows: result.affectedRows,
        columnSchemas: columnSchemas,
        truncatedAt: safe.appliedLimit ? defaultSelectLimit : null,
      );
    } on ServerException catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.message, elapsed: watch.elapsed);
    } catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.toString(), elapsed: watch.elapsed);
    }
  }
}
