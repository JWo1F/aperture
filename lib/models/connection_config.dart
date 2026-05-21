import 'query_message.dart';
import 'saved_query.dart';

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
  final String password;
  final bool useSsl;

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
    'password': password,
    'useSsl': useSsl,
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

  factory ConnectionConfig.fromJson(Map<String, dynamic> j) => ConnectionConfig(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    host: j['host'] as String? ?? 'localhost',
    port: (j['port'] as num?)?.toInt() ?? 5432,
    database: j['database'] as String? ?? '',
    username: j['username'] as String? ?? 'postgres',
    password: j['password'] as String? ?? '',
    useSsl: j['useSsl'] as bool? ?? false,
    readOnly: j['readOnly'] as bool? ?? false,
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

  ConnectionConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    bool? useSsl,
    bool? readOnly,
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
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      favoriteTables: favoriteTables ?? this.favoriteTables,
      savedQueries: savedQueries ?? this.savedQueries,
      recentTables: recentTables ?? this.recentTables,
      columnWidths: columnWidths ?? this.columnWidths,
      queryMessages: queryMessages ?? this.queryMessages,
    );
  }
}
