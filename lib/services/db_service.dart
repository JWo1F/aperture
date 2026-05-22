import '../models/cell_edit.dart';
import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'introspector.dart';
import 'postgres_service.dart';
import 'sqlite_service.dart';

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

/// Reduces a raw engine version string (Postgres `16.4 (Homebrew)`, SQLite
/// `3.45.1`) to a short `vMAJOR.MINOR` tag for the sidebar header. Strips a
/// trailing parenthetical (Postgres' build label) and keeps only the first
/// two dotted segments. Returns null for an empty or whitespace-only input.
String? versionTag(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final head = s.split(' ').first;
  final parts = head.split('.');
  return parts.length >= 2 ? 'v${parts[0]}.${parts[1]}' : 'v${parts.first}';
}

/// Times [apply] and reports the outcome to [logger]. Returns the affected
/// row count from `apply` on success; on failure reports the elapsed time +
/// error to [logger] and rethrows so the caller still sees the original
/// driver/engine exception. Shared timing skin around the per-engine
/// `TableRepository.applyEdits` paths.
Future<int> timedEdit({
  required EditBatch batch,
  required EditLogger? logger,
  required Future<int> Function() apply,
}) async {
  final watch = Stopwatch()..start();
  try {
    final affected = await apply();
    watch.stop();
    logger?.call(
      statementCount: batch.statementCount,
      elapsed: watch.elapsed,
      error: null,
    );
    return affected;
  } catch (e) {
    watch.stop();
    logger?.call(
      statementCount: batch.statementCount,
      elapsed: watch.elapsed,
      error: e.toString(),
    );
    rethrow;
  }
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
  DbEngine.sqlite => SqliteService(
    config,
    onQueryRun: onQueryRun,
    onEditApplied: onEditApplied,
  ),
};
