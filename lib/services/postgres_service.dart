import 'package:postgres/postgres.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'db_service.dart';
import 'driver_decoder.dart';
import 'postgres_introspector.dart';
import 'postgres_table_repository.dart';
import 'safe_query.dart';

List<Object?> _decodeRow(List<Object?> raw) => [
  for (final v in raw) decodeDriverValue(v),
];

/// Runs [sql] on [session], times it, and reports the outcome to [logger]
/// before either returning the [Result] or rethrowing. The single point
/// every Postgres statement in the app flows through.
Future<Result> _logged(
  Session session,
  String sql, {
  Map<String, dynamic>? parameters,
  Duration? timeout,
  required QueryLogger? logger,
}) async {
  final watch = Stopwatch()..start();
  try {
    final result = parameters == null
        ? await session.execute(sql, timeout: timeout)
        : await session.execute(
            Sql.named(sql),
            parameters: parameters,
            timeout: timeout,
          );
    watch.stop();
    logger?.call(
      sql: sql,
      elapsed: watch.elapsed,
      affectedRows: result.affectedRows,
      error: null,
    );
    return result;
  } catch (e) {
    watch.stop();
    logger?.call(
      sql: sql,
      elapsed: watch.elapsed,
      affectedRows: null,
      error: e.toString(),
    );
    rethrow;
  }
}

/// Transaction-scoped view of the SQL channel. Every [execute] inside a
/// transaction logs through the same [QueryLogger] as standalone calls.
class TxScope {
  TxScope._(this._session, this._logger);

  final Session _session;
  final QueryLogger? _logger;

  Future<Result> execute(
    String sql, {
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) => _logged(
    _session,
    sql,
    parameters: parameters,
    timeout: timeout,
    logger: _logger,
  );
}

/// [DbService] implementation backed by a single live Postgres connection.
/// Owns the connection lifecycle ([connect] / [close]) and is the single
/// SQL channel for the Postgres path — [PostgresTableRepository] and
/// [PostgresIntrospector] both run their statements through [execute] /
/// [runTx] so every query passes the same logging point.
class PostgresService implements DbService {
  PostgresService(this.config, {this.onQueryRun, this.onEditApplied});

  @override
  final ConnectionConfig config;

  /// Fires for every SQL statement executed through this service, whether
  /// it originated in [runQuery], in [PostgresTableRepository], in
  /// [PostgresIntrospector], or inside a transaction via [runTx].
  final QueryLogger? onQueryRun;

  /// Called after every UPDATE batch from cell editing.
  final EditLogger? onEditApplied;

  Connection? _connection;
  PostgresTableRepository? _repository;

  @override
  bool get isConnected => _connection?.isOpen ?? false;

  @override
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
        applicationName: 'aperture',
      ),
    );
    _repository = PostgresTableRepository(this);
  }

  @override
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
  @override
  Introspector get introspector => PostgresIntrospector(this);

  /// The single SQL channel. Every statement issued by the app flows
  /// through here so [onQueryRun] sees it before it hits the wire.
  Future<Result> execute(
    String sql, {
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) => _logged(
    _conn,
    sql,
    parameters: parameters,
    timeout: timeout,
    logger: onQueryRun,
  );

  /// Runs [action] inside a real transaction. Statements executed on the
  /// supplied [TxScope] log through the same channel as standalone calls.
  Future<T> runTx<T>(
    Future<T> Function(TxScope) action, {
    TransactionSettings? settings,
  }) => _conn.runTx<T>(
    (session) => action(TxScope._(session, onQueryRun)),
    settings: settings,
  );

  // --- Delegations preserved so existing call sites compile ----------

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
      buildPostgresEditStatements(table, batch);

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

  /// Reads `SHOW server_version` and reduces it to a `vMAJOR.MINOR` tag.
  /// Postgres returns something like `16.4 (Homebrew)`; we strip the
  /// parenthetical and keep the first two segments.
  @override
  Future<String?> fetchVersionTag() async {
    try {
      final res = await runQuery('SHOW server_version');
      if (res.isError || res.rows.isEmpty) return null;
      final s = res.rows.first.first?.toString().trim() ?? '';
      if (s.isEmpty) return null;
      final head = s.split(' ').first;
      final parts = head.split('.');
      return parts.length >= 2
          ? 'v${parts[0]}.${parts[1]}'
          : 'v${parts.first}';
    } catch (_) {
      return null;
    }
  }

  /// Default cap applied to bare top-level `SELECT` statements that don't
  /// carry their own LIMIT. Prevents an unbounded `SELECT *` from
  /// materialising an entire billion-row table in the isolate. Statements
  /// that aren't a plain SELECT — anything starting with `WITH`, `INSERT`,
  /// DDL, etc. — pass through untouched.
  static const defaultSelectLimit = 10000;

  /// Executes a user-supplied statement, applying [defaultSelectLimit]
  /// to bare SELECTs and shaping the driver result into a [QueryResult].
  /// Logging happens in [execute] so this method just translates the
  /// outcome — no separate log entry is emitted here.
  @override
  Future<QueryResult> runQuery(String sql) async {
    final safe = applyDefaultLimit(sql, limit: defaultSelectLimit);
    final watch = Stopwatch()..start();
    try {
      final result = await execute(safe.sql);
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
