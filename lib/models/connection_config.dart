import 'query_message.dart';
import 'saved_query.dart';

/// Where a connection's password comes from.
///
/// - [plain]: stored verbatim in the JSON config file.
/// - [encrypted]: stored as AES-GCM ciphertext in the JSON config file,
///   gated by the app-level master passphrase.
/// - [onePassword]: resolved on demand via the `op` CLI from
///   [ConnectionConfig.opSecretRef].
enum CredentialSource {
  plain,
  encrypted,
  onePassword;

  static CredentialSource fromName(String? raw) => switch (raw) {
    'encrypted' => encrypted,
    'onePassword' => onePassword,
    _ => plain,
  };
}

/// User-supplied details for one Postgres endpoint.
class ConnectionConfig {
  ConnectionConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    this.useSsl = false,
    this.readOnly = false,
    this.credentialSource = CredentialSource.plain,
    this.passwordCipher,
    this.opSecretRef,
    this.lastConnectedAt,
    Set<String>? favoriteTables,
    List<SavedQuery>? savedQueries,
    List<String>? recentTables,
    Map<String, Map<String, double>>? columnWidths,
    Map<String, List<QueryMessage>>? queryMessages,
  }) : favoriteTables = favoriteTables ?? const {},
       savedQueries = savedQueries ?? const [],
       recentTables = recentTables ?? const [],
       columnWidths = columnWidths ?? const {},
       queryMessages = queryMessages ?? const {};

  final String id;
  final String name;
  final String host;
  final int port;
  final String database;
  final String username;

  /// Runtime plaintext. Populated for [CredentialSource.plain] from the
  /// JSON file, for [CredentialSource.encrypted] only after the master
  /// passphrase unlocks the session, and for [CredentialSource.onePassword]
  /// after `op read` resolves the reference.
  final String password;
  final bool useSsl;

  final CredentialSource credentialSource;

  /// Base64 `nonce || ciphertext || tag` produced by [MasterPassphrase.encrypt].
  /// Non-null only when [credentialSource] is [CredentialSource.encrypted].
  final String? passwordCipher;

  /// `op://Vault/Item/password`-style reference resolved through the `op`
  /// CLI when [credentialSource] is [CredentialSource.onePassword].
  final String? opSecretRef;

  /// When true, the workspace blocks cell edits and DDL/UPDATE/DELETE
  /// gestures. The flag is purely client-side — it does not change the
  /// session role at the Postgres end.
  final bool readOnly;

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

  /// User-set column widths, keyed by `schema.table` then by column name.
  /// Rehydrated into the open tab's columnWidths on openTable.
  final Map<String, Map<String, double>> columnWidths;

  /// Per-query-tab message log, keyed by tab/SavedQuery id. The list grows
  /// newest-last; [TabsController] trims to [PerConnectionStore.maxMessages]
  /// after every append.
  final Map<String, List<QueryMessage>> queryMessages;

  String get summary => '$username@$host:$port/$database';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    if (credentialSource == CredentialSource.plain) 'password': password,
    'useSsl': useSsl,
    if (credentialSource != CredentialSource.plain)
      'credentialSource': credentialSource.name,
    if (credentialSource == CredentialSource.encrypted &&
        passwordCipher != null &&
        passwordCipher!.isNotEmpty)
      'passwordCipher': passwordCipher,
    if (credentialSource == CredentialSource.onePassword &&
        opSecretRef != null &&
        opSecretRef!.isNotEmpty)
      'opSecretRef': opSecretRef,
    if (readOnly) 'readOnly': true,
    if (lastConnectedAt != null)
      'lastConnectedAt': lastConnectedAt!.toIso8601String(),
    if (favoriteTables.isNotEmpty) 'favorites': favoriteTables.toList()..sort(),
    if (savedQueries.isNotEmpty)
      'queries': [for (final q in savedQueries) q.toJson()],
    if (recentTables.isNotEmpty) 'recentTables': recentTables,
    if (columnWidths.isNotEmpty) 'columnWidths': columnWidths,
    if (queryMessages.isNotEmpty)
      'queryMessages': {
        for (final e in queryMessages.entries)
          e.key: [for (final m in e.value) m.toJson()],
      },
  };

  factory ConnectionConfig.fromJson(Map<String, dynamic> j) {
    // Legacy: connections written before the master-passphrase rewrite
    // had credentialSource=keychain and the password living in the
    // macOS keychain. The keychain is gone now — those configs surface
    // as plain with no stored password, and the user re-enters it.
    final raw = j['credentialSource'] as String?;
    final source = raw == 'keychain'
        ? CredentialSource.plain
        : CredentialSource.fromName(raw);
    return ConnectionConfig(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      host: j['host'] as String? ?? 'localhost',
      port: (j['port'] as num?)?.toInt() ?? 5432,
      database: j['database'] as String? ?? '',
      username: j['username'] as String? ?? 'postgres',
      password: source == CredentialSource.plain
          ? (j['password'] as String? ?? '')
          : '',
      useSsl: j['useSsl'] as bool? ?? false,
      readOnly: j['readOnly'] as bool? ?? false,
      credentialSource: source,
      passwordCipher: source == CredentialSource.encrypted
          ? j['passwordCipher'] as String?
          : null,
      opSecretRef: source == CredentialSource.onePassword
          ? j['opSecretRef'] as String?
          : null,
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
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    bool? useSsl,
    bool? readOnly,
    CredentialSource? credentialSource,
    Object? passwordCipher = _unset,
    Object? opSecretRef = _unset,
    DateTime? lastConnectedAt,
    Set<String>? favoriteTables,
    List<SavedQuery>? savedQueries,
    List<String>? recentTables,
    Map<String, Map<String, double>>? columnWidths,
    Map<String, List<QueryMessage>>? queryMessages,
  }) {
    return ConnectionConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      readOnly: readOnly ?? this.readOnly,
      credentialSource: credentialSource ?? this.credentialSource,
      passwordCipher: identical(passwordCipher, _unset)
          ? this.passwordCipher
          : passwordCipher as String?,
      opSecretRef: identical(opSecretRef, _unset)
          ? this.opSecretRef
          : opSecretRef as String?,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      favoriteTables: favoriteTables ?? this.favoriteTables,
      savedQueries: savedQueries ?? this.savedQueries,
      recentTables: recentTables ?? this.recentTables,
      columnWidths: columnWidths ?? this.columnWidths,
      queryMessages: queryMessages ?? this.queryMessages,
    );
  }
}

const Object _unset = Object();
