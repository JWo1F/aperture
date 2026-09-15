import 'query_message.dart';
import 'saved_query.dart';

/// How a connection's password is stored on disk and resolved at connect
/// time. The sealed hierarchy makes illegal states unrepresentable —
/// every variant carries exactly the field it needs.
sealed class Credential {
  const Credential();

  /// Discriminator written to JSON.
  String get kind;

  Map<String, dynamic> toJson();

  /// Round-trip from `connections.json`. Unknown kinds (including the
  /// legacy `keychain` source) fall back to an empty plain credential
  /// — the user re-enters the password on next edit.
  factory Credential.fromJson(Object? raw) {
    if (raw is! Map) return const PlainCredential('');
    final kind = raw['kind'];
    return switch (kind) {
      'encrypted' => EncryptedCredential((raw['cipher'] as String?) ?? ''),
      'onePassword' => OnePasswordCredential((raw['ref'] as String?) ?? ''),
      _ => PlainCredential((raw['password'] as String?) ?? ''),
    };
  }
}

/// Password is stored verbatim in the JSON file.
class PlainCredential extends Credential {
  const PlainCredential(this.password);
  final String password;
  @override
  String get kind => 'plain';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'password': password};
}

/// Password is stored as AES-GCM ciphertext, gated by the app-level master
/// passphrase. [cipher] is base64 `nonce || ciphertext || tag`.
class EncryptedCredential extends Credential {
  const EncryptedCredential(this.cipher);
  final String cipher;
  @override
  String get kind => 'encrypted';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'cipher': cipher};
}

/// Password is resolved on demand via the `op` CLI from [secretRef]
/// (`op://Vault/Item/password`-style reference).
class OnePasswordCredential extends Credential {
  const OnePasswordCredential(this.secretRef);
  final String secretRef;
  @override
  String get kind => 'onePassword';
  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'ref': secretRef};
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
    this.credential = const PlainCredential(''),
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
  /// present in `store.json`.
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (engine != DbEngine.postgres) 'engine': engine.name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    if (filePath.isNotEmpty) 'filePath': filePath,
    'credential': credential.toJson(),
    'useSsl': useSsl,
    if (color != null) 'color': color,
    if (readOnly) 'readOnly': true,
    if (lastConnectedAt != null)
      'lastConnectedAt': lastConnectedAt!.toIso8601String(),
    if (favoriteTables.isNotEmpty) 'favorites': favoriteTables.toList()..sort(),
    if (savedQueries.isNotEmpty)
      'queries': [for (final q in savedQueries) q.toJson()],
    if (recentTables.isNotEmpty) 'recentTables': recentTables,
    if (tableUseCounts.isNotEmpty) 'tableUseCounts': tableUseCounts,
    if (columnWidths.isNotEmpty) 'columnWidths': columnWidths,
    if (queryMessages.isNotEmpty)
      'queryMessages': {
        for (final e in queryMessages.entries)
          e.key: [for (final m in e.value) m.toJson()],
      },
  };

  factory ConnectionConfig.fromJson(Map<String, dynamic> j) {
    return ConnectionConfig(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      engine: DbEngine.fromName(j['engine'] as String?),
      host: j['host'] as String? ?? 'localhost',
      port: (j['port'] as num?)?.toInt() ?? 5432,
      database: j['database'] as String? ?? '',
      username: j['username'] as String? ?? 'postgres',
      filePath: j['filePath'] as String? ?? '',
      credential: Credential.fromJson(j['credential']),
      useSsl: j['useSsl'] as bool? ?? false,
      readOnly: j['readOnly'] as bool? ?? false,
      color: (j['color'] as num?)?.toInt(),
      lastConnectedAt: j['lastConnectedAt'] is String
          ? DateTime.tryParse(j['lastConnectedAt'] as String)
          : null,
      favoriteTables: j['favorites'] is List
          ? {for (final v in j['favorites'] as List) v as String}
          : null,
      savedQueries: j['queries'] is List
          ? [
              for (final q in j['queries'] as List)
                SavedQuery.fromJson(q as Map<String, dynamic>),
            ]
          : null,
      recentTables: j['recentTables'] is List
          ? [for (final v in j['recentTables'] as List) v as String]
          : null,
      tableUseCounts: j['tableUseCounts'] is Map
          ? <String, int>{
              for (final e in (j['tableUseCounts'] as Map).entries)
                e.key as String: (e.value as num).toInt(),
            }
          : null,
      columnWidths: j['columnWidths'] is Map
          ? <String, Map<String, double>>{
              for (final e in (j['columnWidths'] as Map).entries)
                e.key as String: <String, double>{
                  for (final ee in (e.value as Map).entries)
                    ee.key as String: (ee.value as num).toDouble(),
                },
            }
          : null,
      queryMessages: j['queryMessages'] is Map
          ? <String, List<QueryMessage>>{
              for (final e in (j['queryMessages'] as Map).entries)
                e.key as String: [
                  for (final m in (e.value as List))
                    QueryMessage.fromJson(m as Map<String, dynamic>),
                ],
            }
          : null,
    );
  }

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
