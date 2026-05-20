/// A SQL query stored under a connection's profile. Persisted to
/// `connections.json` so queries survive restarts.
class SavedQuery {
  SavedQuery({
    required this.id,
    required this.name,
    required this.sql,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String sql;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sql': sql,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory SavedQuery.fromJson(Map<String, dynamic> j) => SavedQuery(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Query',
        sql: j['sql'] as String? ?? '',
        updatedAt: j['updatedAt'] is String
            ? DateTime.tryParse(j['updatedAt'] as String)
            : null,
      );

  SavedQuery copyWith({String? name, String? sql, DateTime? updatedAt}) =>
      SavedQuery(
        id: id,
        name: name ?? this.name,
        sql: sql ?? this.sql,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
