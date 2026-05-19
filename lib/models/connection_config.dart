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
    this.lastConnectedAt,
    Set<String>? favoriteTables,
  }) : favoriteTables = favoriteTables ?? const {};

  final String id;
  final String name;
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool useSsl;
  final DateTime? lastConnectedAt;

  /// Per-connection favourite tables, stored as unquoted `schema.table` keys.
  final Set<String> favoriteTables;

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
        if (lastConnectedAt != null)
          'lastConnectedAt': lastConnectedAt!.toIso8601String(),
        if (favoriteTables.isNotEmpty)
          'favorites': favoriteTables.toList()..sort(),
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
        lastConnectedAt: j['lastConnectedAt'] is String
            ? DateTime.tryParse(j['lastConnectedAt'] as String)
            : null,
        favoriteTables: j['favorites'] is List
            ? {for (final v in j['favorites'] as List) v as String}
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
    DateTime? lastConnectedAt,
    Set<String>? favoriteTables,
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
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      favoriteTables: favoriteTables ?? this.favoriteTables,
    );
  }
}
