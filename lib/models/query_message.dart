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

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'sql': sql,
    if (elapsedMs != null) 'ms': elapsedMs,
    if (affectedRows != null) 'affected': affectedRows,
    if (error != null) 'error': error,
  };

  factory QueryMessage.fromJson(Map<String, dynamic> j) => QueryMessage(
    timestamp:
        DateTime.tryParse(j['ts'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    sql: j['sql'] as String? ?? '',
    elapsedMs: j['ms'] is int ? j['ms'] as int : null,
    affectedRows: j['affected'] is int ? j['affected'] as int : null,
    error: j['error'] as String?,
  );
}
