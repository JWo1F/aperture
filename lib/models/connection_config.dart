import 'query_message.dart';
import 'saved_query.dart';

/// Where a connection's password comes from at connect time.
sealed class Credential {
  const Credential();
}

/// The password itself, kept with the rest of the settings.
class PasswordCredential extends Credential {
  const PasswordCredential(this.password);
  final String password;
}

/// A shell command whose output is the password, run on every connect —
/// `op read 'op://Vault/Item/password'`, `security find-generic-password
/// -w -s db`, `pass show db`.
class CommandCredential extends Credential {
  const CommandCredential(this.command);
  final String command;
}

/// Which database engine a connection targets.
enum DbEngine {
  postgres,
  sqlite;

  static DbEngine fromName(String? raw) =>
      raw == 'sqlite' ? sqlite : postgres;
}

/// User-supplied details for one database connection — a Postgres endpoint
/// or a local SQLite file, distinguished by [engine].
class ConnectionConfig {
  ConnectionConfig({
    required this.id,
    required this.name,
    this.engine = DbEngine.postgres,
    this.host = '',
    this.port = 5432,
    this.database = '',
    this.username = '',
    this.credential = const PasswordCredential(''),
    this.runtimePassword = '',
    this.filePath = '',
    this.useSsl = false,
    this.readOnly = false,
    this.color,
    this.lastConnectedAt,
    Set<String>? favoriteTables,
    List<SavedQuery>? savedQueries,
    List<String>? recentTables,
    Map<String, int>? tableUseCounts,
    Map<String, Map<String, double>>? columnWidths,
    Map<String, List<QueryMessage>>? queryMessages,
  }) : favoriteTables = favoriteTables ?? const {},
       savedQueries = savedQueries ?? const [],
       recentTables = recentTables ?? const [],
       tableUseCounts = tableUseCounts ?? const {},
       columnWidths = columnWidths ?? const {},
       queryMessages = queryMessages ?? const {};

  final String id;
  final String name;

  /// Selects which driver/service backs this connection.
  final DbEngine engine;

  final String host;
  final int port;
  final String database;
  final String username;

  /// Absolute path to the SQLite database file. Empty for Postgres
  /// connections; the sole address for [DbEngine.sqlite] connections.
  final String filePath;

  /// How the password is stored and resolved.
  final Credential credential;

  /// Transient plaintext for the driver — populated by AppState after
  /// resolving [credential], wiped by AppStore before any save. Never
  /// present in the settings store.
  final String runtimePassword;

  final bool useSsl;

  /// When true, the workspace blocks cell edits and DDL/UPDATE/DELETE
  /// gestures. The flag is purely client-side — it does not change the
  /// session role at the Postgres end.
  final bool readOnly;

  /// True when [other] addresses the same database over the same
  /// transport — everything a live socket was opened against.
  ///
  /// Name, colour and credential are excluded: renaming a connection or
  /// switching where its password comes from doesn't change which server
  /// the open session is talking to. `readOnly` is included because the
  /// workspace gates edit gestures on it, so a stale value would offer to
  /// write to a connection the user just marked read-only.
  bool sameTarget(ConnectionConfig other) =>
      engine == other.engine &&
      host == other.host &&
      port == other.port &&
      database == other.database &&
      username == other.username &&
      filePath == other.filePath &&
      useSsl == other.useSsl &&
      readOnly == other.readOnly;

  /// User-chosen identity color, stored as a 0xAARRGGBB int. Tints the
  /// sidebar header, active-row markers, and connection chips so multiple
  /// open databases stay visually distinct. Null falls back to the app
  /// accent.
  final int? color;

  final DateTime? lastConnectedAt;

  /// Per-connection favourite tables, stored as unquoted `schema.table` keys.
  final Set<String> favoriteTables;

  /// Per-connection saved query texts. Tab ids match SavedQuery ids so
  /// opening a saved query reuses the same tab slot.
  final List<SavedQuery> savedQueries;

  /// Recently-opened tables for this connection, most-recent first, stored
  /// as unquoted `schema.table` keys. Rehydrated into [DbTable]s once the
  /// catalog is loaded on connect.
  final List<String> recentTables;

  /// Count of times each table has been opened, keyed by `schema.table`.
  /// Drives the "Frequent" section in the sidebar — top-N most-used tables,
  /// minus anything already pinned as a favourite.
  final Map<String, int> tableUseCounts;

  /// User-set column widths, keyed by `schema.table` then by column name.
  /// Rehydrated into the open tab's columnWidths on openTable.
  final Map<String, Map<String, double>> columnWidths;

  /// Per-query-tab message log, keyed by tab/SavedQuery id. The list grows
  /// newest-last; trimmed to [AppStore.maxMessagesPerQuery] on append.
  final Map<String, List<QueryMessage>> queryMessages;

  String get summary => switch (engine) {
    DbEngine.sqlite => filePath.isEmpty ? 'sqlite' : filePath,
    DbEngine.postgres => '$username@$host:$port/$database',
  };

  ConnectionConfig copyWith({
    String? name,
    DbEngine? engine,
    String? host,
    int? port,
    String? database,
    String? username,
    Credential? credential,
    String? runtimePassword,
    String? filePath,
    bool? useSsl,
    bool? readOnly,
    Object? color = _unset,
    DateTime? lastConnectedAt,
    Set<String>? favoriteTables,
    List<SavedQuery>? savedQueries,
    List<String>? recentTables,
    Map<String, int>? tableUseCounts,
    Map<String, Map<String, double>>? columnWidths,
    Map<String, List<QueryMessage>>? queryMessages,
  }) {
    return ConnectionConfig(
      id: id,
      name: name ?? this.name,
      engine: engine ?? this.engine,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      credential: credential ?? this.credential,
      runtimePassword: runtimePassword ?? this.runtimePassword,
      filePath: filePath ?? this.filePath,
      useSsl: useSsl ?? this.useSsl,
      readOnly: readOnly ?? this.readOnly,
      color: identical(color, _unset) ? this.color : color as int?,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      favoriteTables: favoriteTables ?? this.favoriteTables,
      savedQueries: savedQueries ?? this.savedQueries,
      recentTables: recentTables ?? this.recentTables,
      tableUseCounts: tableUseCounts ?? this.tableUseCounts,
      columnWidths: columnWidths ?? this.columnWidths,
      queryMessages: queryMessages ?? this.queryMessages,
    );
  }
}

const Object _unset = Object();
