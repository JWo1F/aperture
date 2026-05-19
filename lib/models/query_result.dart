/// Outcome of a single executed statement: either a row set or an error.
class QueryResult {
  QueryResult.rows({
    required this.columns,
    required this.rows,
    required this.elapsed,
    this.affectedRows,
    this.rowIds,
  })  : error = null,
        isError = false;

  QueryResult.command({
    required this.affectedRows,
    required this.elapsed,
  })  : columns = const [],
        rows = const [],
        rowIds = null,
        error = null,
        isError = false;

  QueryResult.failure({required this.error, required this.elapsed})
      : columns = const [],
        rows = const [],
        rowIds = null,
        affectedRows = null,
        isError = true;

  final List<String> columns;
  final List<List<dynamic>> rows;

  /// Per-row Postgres `ctid`, present only for single-relation table pages.
  /// Used to target rows in UPDATE statements.
  final List<String>? rowIds;

  final int? affectedRows;
  final Duration elapsed;
  final String? error;
  final bool isError;

  bool get hasColumns => columns.isNotEmpty;
}
