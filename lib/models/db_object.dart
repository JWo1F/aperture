/// Schema-tree model: a schema owning a set of tables and views.
class DbSchema {
  DbSchema({required this.name, required this.tables});

  final String name;
  final List<DbTable> tables;
}

enum DbRelationKind { table, view }

class DbTable {
  DbTable({
    required this.schema,
    required this.name,
    required this.kind,
  });

  final String schema;
  final String name;
  final DbRelationKind kind;

  String get qualifiedName => '"$schema"."$name"';

  /// Stable, unquoted identifier used as a key in persisted maps/sets
  /// (e.g. favorites). Distinct from `qualifiedName` which is SQL-safe.
  String get qualifiedKey => '$schema.$name';

  bool get isView => kind == DbRelationKind.view;
}

/// A single-column foreign key from this table to another. Multi-column FKs
/// are ignored for v1 — they're rare in app schemas and the UX would need
/// per-column value selection.
class DbForeignKey {
  DbForeignKey({
    required this.column,
    required this.refSchema,
    required this.refTable,
    required this.refColumn,
  });

  final String column;
  final String refSchema;
  final String refTable;
  final String refColumn;

  String get refQualified => '$refSchema.$refTable';
}

class DbColumn {
  DbColumn({
    required this.name,
    required this.dataType,
    required this.nullable,
    required this.isPrimaryKey,
  });

  final String name;
  final String dataType;
  final bool nullable;
  final bool isPrimaryKey;
}
