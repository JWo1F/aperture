import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'db_service.dart';
import 'mysql_decoder.dart';
import 'mysql_introspector.dart';
import 'mysql_table_repository.dart';
import 'safe_query.dart';

/// The rows of a statement, decoded, with the column names they came under.
/// [columns] is empty for a statement that returns no result set.
class MysqlRows {
  MysqlRows({
    required this.columns,
    required this.rows,
    required this.affectedRows,
  });

  final List<String> columns;
  final List<List<Object?>> rows;
  final int affectedRows;
}

/// Statements run inside [MysqlService.runTx]. They log through the same
/// channel as standalone ones but skip the command queue, which the
/// transaction already holds.
class MysqlTx {
  MysqlTx._(this._service, this._conn);

  final MysqlService _service;
  final MySQLConnection _conn;

  Future<MysqlRows> execute(String sql) => _service._run(_conn, sql, log: true);
}

/// [DbService] implementation backed by a single MySQL or MariaDB
/// connection through `mysql_dart`.
///
/// One connection, not a pool: the query editor is a session, and a `USE`,
/// `SET` or temporary table has to be there for the next statement. The
/// driver refuses a second command while one is in flight ("connection is
/// busy"), and the catalog loader fires its sweeps in parallel, so every
/// command goes through [_serial], which queues them on the one socket.
class MysqlService implements DbService {
  MysqlService(this.config, {this.onQueryRun, this.onEditApplied});

  @override
  final ConnectionConfig config;

  /// Fires for every statement the user or an edit sends. Catalog
  /// introspection passes `log: false` so it stays out of the activity log.
  final QueryLogger? onQueryRun;

  /// Called after every applied cell-edit batch.
  final EditLogger? onEditApplied;

  /// Mirrors [PostgresService.defaultSelectLimit].
  static const defaultSelectLimit = 10000;

  static const _connectTimeout = Duration(seconds: 10);
  static const _pingTimeout = Duration(seconds: 10);

  MySQLConnection? _connection;
  int? _connectionId;
  MysqlTableRepository? _repository;
  MysqlIntrospector? _introspector;

  /// Tail of the command queue; see [_serial].
  Future<void> _queue = Future.value();

  /// Commands queued or running. The keepalive skips its probe while one is
  /// in flight rather than queue behind it.
  int _pending = 0;

  @override
  bool get isConnected => _connection?.connected ?? false;

  MySQLConnection get _conn {
    final c = _connection;
    if (c == null || !c.connected) throw StateError('Not connected');
    return c;
  }

  @override
  Future<void> connect() async {
    final conn = await _open();
    _connection = conn;
    final id = await _run(conn, 'SELECT CONNECTION_ID()', log: false);
    _connectionId = id.rows.first.first as int?;
    _repository = MysqlTableRepository(this);
    _introspector = MysqlIntrospector(this);
  }

  /// Opens and authenticates a fresh connection with this config.
  ///
  /// `caching_sha2_password`, the default since MySQL 8, will only send the
  /// password over plain TCP encrypted with the server's RSA key, so a
  /// connection with TLS off asks the server for that key. Without it the
  /// handshake fails with an error that names neither TLS nor the key.
  Future<MySQLConnection> _open() async {
    final conn = await MySQLConnection.createConnection(
      host: config.host,
      port: config.port,
      userName: config.username,
      password: config.runtimePassword,
      databaseName: config.database,
      secure: config.tls != TlsMode.off,
      onBadCertificate: switch (config.tls) {
        TlsMode.off || TlsMode.verify => (_) => false,
        TlsMode.require => (_) => true,
      },
      allowPublicKeyRetrieval: config.tls == TlsMode.off,
    ).timeout(_connectTimeout);
    await conn.connect(timeoutMs: _connectTimeout.inMilliseconds);
    return conn;
  }

  /// A connection that died under the driver can no longer send `QUIT`, and
  /// the driver throws rather than skip it; there is nothing left to close.
  @override
  Future<void> close() async {
    final conn = _connection;
    _connection = null;
    _connectionId = null;
    _repository = null;
    _introspector = null;
    if (conn == null || !conn.connected) return;
    try {
      await conn.close();
    } on MySQLClientException {
      // Already closing.
    }
  }

  TableRepository get tableRepository {
    final r = _repository;
    if (r == null) throw StateError('Not connected');
    return r;
  }

  @override
  Introspector get introspector {
    final i = _introspector;
    if (i == null) throw StateError('Not connected');
    return i;
  }

  /// Runs [action] once every command queued before it has finished.
  Future<T> _serial<T>(Future<T> Function(MySQLConnection conn) action) {
    _pending++;
    final run = _queue.then((_) => action(_conn));
    _queue = run
        .then<void>((_) {}, onError: (_) {})
        .whenComplete(() => _pending--);
    return run;
  }

  /// The single SQL channel: queues [sql], runs it, and reports it to
  /// [onQueryRun] unless [log] is false.
  Future<MysqlRows> execute(String sql, {bool log = true}) =>
      _serial((conn) => _run(conn, sql, log: log));

  /// Runs [action] inside a transaction holding the command queue, so no
  /// other statement lands between its statements. A failed `ROLLBACK`
  /// never replaces the error that caused it: on a dead connection the
  /// server has already discarded the transaction.
  Future<T> runTx<T>(Future<T> Function(MysqlTx tx) action) =>
      _serial((conn) async {
        await _run(conn, 'START TRANSACTION', log: true);
        try {
          final result = await action(MysqlTx._(this, conn));
          await _run(conn, 'COMMIT', log: true);
          return result;
        } catch (_) {
          try {
            await _run(conn, 'ROLLBACK', log: true);
          } catch (_) {
            // The original error is the one worth reporting.
          }
          rethrow;
        }
      });

  Future<MysqlRows> _run(
    MySQLConnection conn,
    String sql, {
    required bool log,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final rows = _shape(await conn.execute(sql));
      watch.stop();
      if (log) {
        onQueryRun?.call(
          sql: sql,
          elapsed: watch.elapsed,
          affectedRows: rows.columns.isEmpty ? rows.affectedRows : null,
          error: null,
        );
      }
      return rows;
    } catch (e) {
      watch.stop();
      if (log) {
        onQueryRun?.call(
          sql: sql,
          elapsed: watch.elapsed,
          affectedRows: null,
          error: errorMessage(e),
        );
      }
      rethrow;
    }
  }

  /// A multi-statement text yields one result set per statement; the last
  /// one is what the statement "returned", matching how the editor's
  /// run-all shows the last statement's result.
  static MysqlRows _shape(IResultSet result) {
    var last = result;
    for (final rs in result) {
      last = rs;
    }
    final types = [for (final c in last.cols) c.type];
    return MysqlRows(
      columns: [for (final c in last.cols) c.name],
      rows: [
        for (final row in last.rows)
          [
            for (var i = 0; i < types.length; i++)
              decodeMysqlValue(row.colAt(i), types[i]),
          ],
      ],
      affectedRows: last.affectedRows.toInt(),
    );
  }

  /// The server's own message for a server error, without the driver's
  /// `MySQLServerException [1054]:` prefix.
  static String errorMessage(Object e) =>
      e is MySQLException ? e.message : e.toString();

  /// The keepalive. A statement already in flight proves the socket is
  /// alive, and queueing behind it would time the probe out on any query
  /// longer than [_pingTimeout] and mark a healthy session lost; if the
  /// socket is in fact dead, that statement fails on its own.
  @override
  Future<void> ping() async {
    if (_pending > 0) {
      if (!isConnected) throw StateError('Not connected');
      return;
    }
    await _serial(
      (conn) => conn.execute('SELECT 1', null, false, _pingTimeout),
    );
  }

  /// MySQL cancels a statement from a second connection: `KILL QUERY` with
  /// the first one's id ends the statement and leaves the session open.
  /// Errors are swallowed — cancelling a statement that already finished
  /// isn't a failure the caller can act on.
  @override
  Future<void> cancelCurrent() async {
    final id = _connectionId;
    if (id == null || _pending == 0) return;
    try {
      final killer = await _open();
      try {
        await killer.execute('KILL QUERY $id');
      } finally {
        await killer.close();
      }
    } catch (_) {}
  }

  @override
  Future<QueryResult> runQuery(String sql) async {
    final safe = applyDefaultLimit(sql, limit: defaultSelectLimit);
    final watch = Stopwatch()..start();
    try {
      final result = await execute(safe.sql);
      watch.stop();
      if (result.columns.isEmpty) {
        return QueryResult.command(
          affectedRows: result.affectedRows,
          elapsed: watch.elapsed,
        );
      }
      return QueryResult.rows(
        columns: result.columns,
        rows: result.rows,
        elapsed: watch.elapsed,
        columnSchemas: [
          for (final n in result.columns) ResultColumnSchema(name: n),
        ],
        truncatedAt: safe.appliedLimit ? defaultSelectLimit : null,
      );
    } catch (e) {
      watch.stop();
      return QueryResult.failure(
        error: errorMessage(e),
        elapsed: watch.elapsed,
      );
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
  Future<String> loadTableDdl(DbTable table) => tableRepository.loadDdl(table);

  @override
  List<String> previewEditStatements(DbTable table, EditBatch batch) =>
      buildMysqlEditStatements(table, batch);

  @override
  Future<EditResult> applyTableEdits(DbTable table, EditBatch batch) =>
      timedEdit(
        batch: batch,
        logger: onEditApplied,
        apply: () => tableRepository.applyEdits(table, batch),
      );

  /// Reduces `VERSION()` — `8.4.11`, `11.8.9-MariaDB-ubu2404` — to a
  /// `vMAJOR.MINOR` tag via [versionTag].
  @override
  Future<String?> fetchVersionTag() async {
    try {
      final result = await execute('SELECT VERSION()', log: false);
      if (result.rows.isEmpty) return null;
      return versionTag(result.rows.first.first?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}
