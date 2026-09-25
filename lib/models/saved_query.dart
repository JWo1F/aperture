/// A SQL query stored under a connection's profile, persisted with the
/// rest of the settings so it survives restarts.
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

  SavedQuery copyWith({String? name, String? sql, DateTime? updatedAt}) =>
      SavedQuery(
        id: id,
        name: name ?? this.name,
        sql: sql ?? this.sql,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
