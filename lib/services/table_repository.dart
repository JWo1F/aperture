import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';

export '../models/cell_edit.dart' show EditResult;

/// Engine-neutral per-relation database operations: paging, exporting,
/// applying cell edits, and building the DDL for the schema viewer.
///
/// The Postgres and SQLite services each return their own implementation;
/// row identity differs (Postgres `ctid` vs SQLite `rowid`) but the surface
/// the workspace talks to does not.
abstract interface class TableRepository {
  /// Total row count for a relation under the active filter.
  Future<int> countRows(DbTable table, {String filter = ''});

  /// One page of rows. For editable relations each row carries an opaque
  /// row-identity token in [QueryResult.rowIds]; relations with no usable
  /// identity (views, `WITHOUT ROWID` tables) return a null `rowIds`.
  Future<QueryResult> fetchPage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  });

  /// Every row under the active filter/order, with no pagination. Used by
  /// exporters; materialises the whole result in memory.
  Future<QueryResult> fetchAll(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  });

  /// A readable `CREATE TABLE …` reconstruction for the schema viewer.
  Future<String> loadDdl(DbTable table);

  /// Applies a batch of pending UPDATEs/DELETEs/INSERTs in one transaction.
  /// Returns an [EditResult] carrying applied-vs-total counts plus the
  /// engine's error message on failure.
  Future<EditResult> applyEdits(DbTable table, EditBatch batch);
}

/// Thrown when an UPDATE/DELETE batch hits a row whose identity no longer
/// matches exactly one row — the row moved or was removed by a concurrent
/// writer. When this fires the transaction has already rolled back, so no
/// partial edit is committed; the caller should reload and retry.
class StaleRowException implements Exception {
  StaleRowException({
    required this.rowId,
    required this.affectedRows,
    required this.table,
  });

  /// The opaque row-identity token (Postgres `ctid`, SQLite `rowid`).
  final String rowId;
  final int affectedRows;
  final DbTable table;

  @override
  String toString() =>
      'Row no longer matches in ${table.qualifiedName} '
      '(row $rowId affected $affectedRows rows). Reload and retry.';
}

