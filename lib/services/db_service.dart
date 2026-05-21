import '../models/cell_edit.dart';
import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'introspector.dart';
import 'postgres_service.dart';

export '../models/cell_edit.dart' show EditBatch, PendingInsert;
export 'introspector.dart' show Introspector;
export 'table_repository.dart'
    show TableRepository, StaleRowException, EditFailureException;

/// Called for every SQL statement that crosses a driver — successful or not.
/// Lives on a single channel so each engine reports queries to the activity
/// log through the same shape.
typedef QueryLogger =
    void Function({
      required String sql,
      required Duration elapsed,
      required int? affectedRows,
      required String? error,
    });

/// Called after every applied cell-edit batch.
typedef EditLogger =
    void Function({
      required int statementCount,
      required Duration elapsed,
      required String? error,
    });

/// Engine-neutral facade over a single live database connection. The
/// workspace, catalog loader, and session controller talk only to this
/// surface; [PostgresService] and [SqliteService] provide the concrete
/// implementations and decide what `runQuery`, introspection, and cell
/// editing mean for their engine.
abstract interface class DbService {
  /// The connection this service was built for.
  ConnectionConfig get config;

  bool get isConnected;

  /// Opens the connection. Throws on failure — callers translate the error
  /// through `friendlyConnectError`.
  Future<void> connect();

  Future<void> close();

  /// Catalog introspector bound to this connection.
  Introspector get introspector;

  /// Executes a user-supplied statement and shapes the outcome into a
  /// [QueryResult]. Bare `SELECT`s without a `LIMIT` are capped.
  Future<QueryResult> runQuery(String sql);

  /// Total row count for a relation under the active filter.
  Future<int> countRows(DbTable table, {String filter = ''});

  /// One page of rows from a relation, for the table grid.
  Future<QueryResult> fetchTablePage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  });

  /// Every row of a relation under the active filter/order — used by export.
  Future<QueryResult> fetchAllTableRows(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  });

  /// A readable `CREATE TABLE …` reconstruction for the schema viewer.
  Future<String> loadTableDdl(DbTable table);

  /// Applies a batch of pending cell edits in one transaction; returns the
  /// total affected row count.
  Future<int> applyTableEdits(DbTable table, EditBatch batch);

  /// The exact SQL [applyTableEdits] would send for [batch], for the
  /// pending-edits preview modal.
  List<String> previewEditStatements(DbTable table, EditBatch batch);

  /// Short version tag for the sidebar header, e.g. `v16.4` / `v3.45`.
  /// Null when the engine reports no version or the probe failed.
  Future<String?> fetchVersionTag();
}

/// Builds the right [DbService] for [config]'s engine. The session
/// controller calls this instead of constructing a service directly so the
/// rest of the app never branches on engine.
DbService createDbService(
  ConnectionConfig config, {
  QueryLogger? onQueryRun,
  EditLogger? onEditApplied,
}) => switch (config.engine) {
  DbEngine.postgres => PostgresService(
    config,
    onQueryRun: onQueryRun,
    onEditApplied: onEditApplied,
  ),
  // SqliteService is wired into this branch once the SQLite driver lands.
  DbEngine.sqlite => throw UnimplementedError('SQLite engine not yet wired'),
};
