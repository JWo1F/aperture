/// Outcome of a single executed statement: either a row set or an error.
class QueryResult {
  QueryResult.rows({
    required this.columns,
    required this.rows,
    required this.elapsed,
    this.affectedRows,
    this.rowIds,
    this.columnSchemas,
  })  : error = null,
        isError = false;

  QueryResult.command({
    required this.affectedRows,
    required this.elapsed,
  })  : columns = const [],
        rows = const [],
        rowIds = null,
        columnSchemas = null,
        error = null,
        isError = false;

  QueryResult.failure({required this.error, required this.elapsed})
      : columns = const [],
        rows = const [],
        rowIds = null,
        columnSchemas = null,
        affectedRows = null,
        isError = true;

  final List<String> columns;
  final List<List<dynamic>> rows;

  /// Per-row Postgres `ctid`, present only for single-relation table pages.
  /// Used to target rows in UPDATE statements.
  final List<String>? rowIds;

  /// Per-column source metadata from the Postgres wire protocol. Parallel to
  /// [columns] when present. Missing for command results / failures; entries
  /// may carry null table/column oids for expression columns (e.g. count(*)).
  final List<ResultColumnSchema>? columnSchemas;

  final int? affectedRows;
  final Duration elapsed;
  final String? error;
  final bool isError;

  bool get hasColumns => columns.isNotEmpty;
}

/// Source-side identity of a single column in a [QueryResult]. Populated
/// directly from the driver's RowDescription frame.
class ResultColumnSchema {
  ResultColumnSchema({
    required this.name,
    this.tableOid,
    this.columnAttNum,
  });

  final String name;

  /// `pg_class.oid` of the relation this column came from. Null or 0 for
  /// expression columns (count(*), a + b, function calls, …).
  final int? tableOid;

  /// `pg_attribute.attnum` of the column within its source relation. Null
  /// for expression columns.
  final int? columnAttNum;

  bool get hasSourceRelation => tableOid != null && tableOid != 0;
}
