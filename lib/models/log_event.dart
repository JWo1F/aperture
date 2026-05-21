/// One entry in the app's event log.
///
/// The log surfaces what the app did and when so the user can answer
/// "what happened at 14:32?" without re-running anything. Captures the
/// SQL on the wire (truncated for display), how long it took, the
/// connection that ran it, and any error.
enum LogEventKind { connect, disconnect, lost, query, edit, error }

class LogEvent {
  LogEvent({
    required this.timestamp,
    required this.kind,
    this.connectionName,
    this.sql,
    this.elapsed,
    this.affectedRows,
    this.error,
  });

  final DateTime timestamp;
  final LogEventKind kind;
  final String? connectionName;
  final String? sql;
  final Duration? elapsed;
  final int? affectedRows;
  final String? error;

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'kind': kind.name,
    if (connectionName != null) 'connection': connectionName,
    if (sql != null) 'sql': sql,
    if (elapsed != null) 'ms': elapsed!.inMilliseconds,
    if (affectedRows != null) 'affected': affectedRows,
    if (error != null) 'error': error,
  };
}
