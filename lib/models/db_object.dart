import '../services/sql_identifier.dart';

/// Schema-tree model: a schema owning a set of tables and views.
class DbSchema {
  DbSchema({required this.name, required this.tables, this.comment});

  final String name;
  final List<DbTable> tables;
  final String? comment;
}

enum DbRelationKind { table, view, materializedView }

/// A relation (table / view / materialized view). The `oid` is the
/// authoritative identity inside the catalog; names are used for display
/// and SQL rendering. Two relations with the same name in different
/// databases will of course have different oids.
class DbTable {
  DbTable({
    required this.oid,
    required this.schema,
    required this.name,
    required this.kind,
    this.comment,
    this.rowEstimate,
    this.sizeBytes,
  });

  /// Sentinel oid used when a [DbTable] is constructed without going through
  /// catalog introspection (e.g. a placeholder before connect completes).
  /// Anything that pivots on `oid` should treat 0 as "unknown".
  static const int unknownOid = 0;

  final int oid;
  final String schema;
  final String name;
  final DbRelationKind kind;
  final String? comment;

  /// Planner row estimate (`pg_class.reltuples`). Null when the engine
  /// exposes no estimate or the relation has never been analyzed — never
  /// negative, unlike the raw catalog value.
  final int? rowEstimate;

  /// Total on-disk footprint in bytes, including indexes and TOAST. Null when
  /// the engine doesn't report it (SQLite) or the relation has no storage.
  final int? sizeBytes;

  String get qualifiedName => qualify(schema, name);

  /// Stable, unquoted identifier used as a key in persisted maps/sets
  /// (e.g. favorites). Distinct from `qualifiedName` which is SQL-safe.
  String get qualifiedKey => '$schema.$name';

  bool get isView =>
      kind == DbRelationKind.view || kind == DbRelationKind.materializedView;
}

/// A foreign key constraint from this relation to another. Supports multi-
/// column constraints — `localColumns` and `refColumns` are parallel arrays
/// of the same length, in `pg_constraint` ordering.
class DbForeignKey {
  DbForeignKey({
    required this.constraintName,
    required this.localColumns,
    required this.refSchema,
    required this.refTable,
    required this.refTableOid,
    required this.refColumns,
    this.onUpdate,
    this.onDelete,
  });

  final String constraintName;
  final List<String> localColumns;
  final String refSchema;
  final String refTable;
  final int refTableOid;
  final List<String> refColumns;
  final String? onUpdate;
  final String? onDelete;

  bool get isSingleColumn => localColumns.length == 1;

  /// Convenience for the single-column case; throws for multi-column FKs so
  /// the caller is forced to acknowledge the wider shape.
  String get localColumn {
    if (!isSingleColumn) {
      throw StateError(
        'localColumn is only defined for single-column FKs; '
        'this constraint spans ${localColumns.length} columns',
      );
    }
    return localColumns.first;
  }

  String get refColumn {
    if (!isSingleColumn) {
      throw StateError(
        'refColumn is only defined for single-column FKs; '
        'this constraint spans ${refColumns.length} columns',
      );
    }
    return refColumns.first;
  }

  String get refQualified => '$refSchema.$refTable';
}

class DbColumn {
  DbColumn({
    required this.name,
    required this.dataType,
    required this.nullable,
    required this.isPrimaryKey,
    required this.hasDefault,
    required this.ordinal,
    this.comment,
  });

  final String name;
  final String dataType;
  final bool nullable;
  final bool isPrimaryKey;
  final bool hasDefault;

  /// 1-based ordinal position in the relation (matches pg_attribute.attnum
  /// for user columns).
  final int ordinal;

  final String? comment;
}

/// A non-PK / non-UNIQUE-constraint index. The `def` is the verbatim
/// `CREATE INDEX` statement from `pg_indexes.indexdef`.
class DbIndex {
  DbIndex({
    required this.name,
    required this.columns,
    required this.unique,
    required this.def,
  });

  final String name;
  final List<String> columns;
  final bool unique;
  final String def;
}

/// A user-defined enum type with its ordered labels.
class DbEnum {
  DbEnum({required this.schema, required this.name, required this.labels});

  final String schema;
  final String name;
  final List<String> labels;

  String get qualifiedName => qualify(schema, name);

  String get qualifiedKey => '$schema.$name';
}

/// A user-defined domain (a type alias with optional constraints/default).
class DbDomain {
  DbDomain({
    required this.schema,
    required this.name,
    required this.baseType,
    required this.notNull,
  });

  final String schema;
  final String name;
  final String baseType;
  final bool notNull;

  String get qualifiedName => qualify(schema, name);
}
