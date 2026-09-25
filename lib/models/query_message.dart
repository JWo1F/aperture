/// One entry in a query tab's message log.
///
/// Captures the SQL the tab actually sent, how long it took, what came
/// back (row count for SELECTs, affected count for DML), and the error
/// string if the run failed. Persisted per-query-id on the active
/// connection so the log survives restart.
class QueryMessage {
  QueryMessage({
    required this.timestamp,
    required this.sql,
    this.elapsedMs,
    this.affectedRows,
    this.error,
  });

  final DateTime timestamp;
  final String sql;
  final int? elapsedMs;
  final int? affectedRows;
  final String? error;

  bool get isError => error != null;
}
