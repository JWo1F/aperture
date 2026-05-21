import '../models/db_object.dart';
import 'introspector.dart';
import 'postgres_service.dart';

/// Runs catalog-wide introspection queries against an open Postgres
/// connection.
///
/// Each public method is a single SQL round-trip that fans out across every
/// user relation — far cheaper than the per-relation calls we used to make
/// lazily, and the single source of truth once a connection is live.
///
/// All identifier columns from `pg_catalog` are cast to `text` because their
/// native `name` type (OID 19) has no codec in the postgres driver and would
/// otherwise come back as `UndecodedBytes`. Every query runs through
/// [PostgresService.execute] so it shows up in the activity log.
class PostgresIntrospector implements Introspector {
  PostgresIntrospector(this._db);

  final PostgresService _db;

  static const String _systemSchemaFilter =
      "n.nspname NOT IN ('pg_catalog', 'information_schema') "
      "AND n.nspname NOT LIKE 'pg_toast%' "
      "AND n.nspname NOT LIKE 'pg_temp_%'";

  /// Loads every user schema with its relations (tables, views, matviews) in
  /// one query. Equivalent to the legacy `loadSchemas` but enriched with
  /// `oid` and table comments so the result can serve as the catalog spine.
  @override
  Future<List<DbSchema>> loadSchemas() async {
    final result = await _db.execute(
      'SELECT n.nspname::text AS schema, '
      '       c.oid::bigint AS oid, '
      '       c.relname::text AS name, '
      '       c.relkind::text AS kind, '
      "       obj_description(c.oid, 'pg_class') AS comment "
      'FROM pg_class c '
      'JOIN pg_namespace n ON n.oid = c.relnamespace '
      "WHERE c.relkind IN ('r', 'v', 'm', 'p') "
      '  AND $_systemSchemaFilter '
      'ORDER BY n.nspname, c.relname',
    );

    final grouped = <String, List<DbTable>>{};
    for (final row in result) {
      final schema = row[0] as String;
      final oid = (row[1] as int);
      final name = row[2] as String;
      final kind = row[3] as String;
      final comment = row[4] as String?;
      grouped
          .putIfAbsent(schema, () => [])
          .add(
            DbTable(
              oid: oid,
              schema: schema,
              name: name,
              kind: _kindFromRelkind(kind),
              comment: comment,
            ),
          );
    }

    return grouped.entries
        .map((e) => DbSchema(name: e.key, tables: e.value))
        .toList();
  }

  /// Every column of every user relation, keyed by parent relation oid.
  /// Folds in primary-key membership via a LATERAL lookup against
  /// `pg_constraint` so the catalog can answer "is this column a PK?"
  /// without a second query.
  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async {
    final result = await _db.execute(
      'SELECT a.attrelid::bigint, '
      '       a.attname::text, '
      '       format_type(a.atttypid, a.atttypmod), '
      '       NOT a.attnotnull AS nullable, '
      '       a.atthasdef AS has_default, '
      '       a.attnum::int AS ordinal, '
      '       col_description(a.attrelid, a.attnum) AS comment, '
      '       EXISTS ('
      '         SELECT 1 FROM pg_constraint pk '
      "         WHERE pk.contype = 'p' "
      '           AND pk.conrelid = a.attrelid '
      '           AND a.attnum = ANY(pk.conkey)'
      '       ) AS is_pk '
      'FROM pg_attribute a '
      'JOIN pg_class c ON c.oid = a.attrelid '
      'JOIN pg_namespace n ON n.oid = c.relnamespace '
      'WHERE a.attnum > 0 '
      '  AND NOT a.attisdropped '
      "  AND c.relkind IN ('r', 'v', 'm', 'p') "
      '  AND $_systemSchemaFilter '
      'ORDER BY a.attrelid, a.attnum',
    );

    final out = <int, List<DbColumn>>{};
    for (final row in result) {
      final relOid = row[0] as int;
      out
          .putIfAbsent(relOid, () => [])
          .add(
            DbColumn(
              name: row[1] as String,
              dataType: row[2] as String,
              nullable: row[3] as bool,
              hasDefault: row[4] as bool,
              ordinal: row[5] as int,
              comment: row[6] as String?,
              isPrimaryKey: row[7] as bool,
            ),
          );
    }
    return out;
  }

  /// All foreign keys across all user relations, grouped by source relation
  /// oid. Multi-column FKs come back as a single [DbForeignKey] with parallel
  /// `localColumns` / `refColumns` arrays.
  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async {
    // For each FK, expand `conkey` / `confkey` into ordered column name
    // arrays via correlated subqueries — keeps everything in one round trip.
    final result = await _db.execute(
      'SELECT c.conrelid::bigint AS src_oid, '
      '       c.conname::text AS name, '
      '       c.confrelid::bigint AS ref_oid, '
      '       refns.nspname::text AS ref_schema, '
      '       refcls.relname::text AS ref_table, '
      '       c.confupdtype::text AS on_update, '
      '       c.confdeltype::text AS on_delete, '
      '       ('
      '         SELECT array_agg(att.attname::text ORDER BY u.ord) '
      '         FROM unnest(c.conkey) WITH ORDINALITY AS u(att_num, ord) '
      '         JOIN pg_attribute att '
      '           ON att.attrelid = c.conrelid '
      '          AND att.attnum = u.att_num'
      '       ) AS local_cols, '
      '       ('
      '         SELECT array_agg(att.attname::text ORDER BY u.ord) '
      '         FROM unnest(c.confkey) WITH ORDINALITY AS u(att_num, ord) '
      '         JOIN pg_attribute att '
      '           ON att.attrelid = c.confrelid '
      '          AND att.attnum = u.att_num'
      '       ) AS ref_cols '
      'FROM pg_constraint c '
      'JOIN pg_class srccls ON srccls.oid = c.conrelid '
      'JOIN pg_namespace srcns ON srcns.oid = srccls.relnamespace '
      'JOIN pg_class refcls ON refcls.oid = c.confrelid '
      'JOIN pg_namespace refns ON refns.oid = refcls.relnamespace '
      "WHERE c.contype = 'f' "
      "  AND srcns.nspname NOT IN ('pg_catalog', 'information_schema') "
      "  AND srcns.nspname NOT LIKE 'pg_toast%' "
      "  AND srcns.nspname NOT LIKE 'pg_temp_%' "
      'ORDER BY c.conrelid, c.conname',
    );

    final out = <int, List<DbForeignKey>>{};
    for (final row in result) {
      final srcOid = row[0] as int;
      final localCols = _stringList(row[7]);
      final refCols = _stringList(row[8]);
      if (localCols.isEmpty || refCols.isEmpty) continue;
      out
          .putIfAbsent(srcOid, () => [])
          .add(
            DbForeignKey(
              constraintName: row[1] as String,
              localColumns: localCols,
              refTableOid: row[2] as int,
              refSchema: row[3] as String,
              refTable: row[4] as String,
              refColumns: refCols,
              onUpdate: _fkAction(row[5] as String?),
              onDelete: _fkAction(row[6] as String?),
            ),
          );
    }
    return out;
  }

  /// Non-constraint indexes for every relation, keyed by relation oid. PK
  /// and UNIQUE-constraint-backed indexes are filtered out (we already model
  /// those via columns / future unique constraints), leaving the "extra"
  /// indexes that are meaningful in DDL view.
  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async {
    final result = await _db.execute(
      'SELECT c.oid::bigint AS rel_oid, '
      '       i.relname::text AS index_name, '
      '       ix.indisunique AS is_unique, '
      '       pg_get_indexdef(ix.indexrelid) AS def, '
      '       ('
      '         SELECT array_agg(att.attname::text ORDER BY u.ord) '
      '         FROM unnest(ix.indkey::int2[]) WITH ORDINALITY AS u(att_num, ord) '
      '         JOIN pg_attribute att '
      '           ON att.attrelid = c.oid '
      '          AND att.attnum = u.att_num '
      '         WHERE u.att_num > 0'
      '       ) AS columns '
      'FROM pg_index ix '
      'JOIN pg_class c ON c.oid = ix.indrelid '
      'JOIN pg_class i ON i.oid = ix.indexrelid '
      'JOIN pg_namespace n ON n.oid = c.relnamespace '
      'WHERE $_systemSchemaFilter '
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM pg_constraint cn '
      '    WHERE cn.conindid = ix.indexrelid '
      "      AND cn.contype IN ('p', 'u', 'x')"
      '  ) '
      'ORDER BY c.oid, i.relname',
    );

    final out = <int, List<DbIndex>>{};
    for (final row in result) {
      final relOid = row[0] as int;
      out
          .putIfAbsent(relOid, () => [])
          .add(
            DbIndex(
              name: row[1] as String,
              unique: row[2] as bool,
              def: row[3] as String,
              columns: _stringList(row[4]),
            ),
          );
    }
    return out;
  }

  /// All user-defined enum types with their labels in `enumsortorder`.
  @override
  Future<List<DbEnum>> loadAllEnums() async {
    final result = await _db.execute(
      'SELECT n.nspname::text AS schema, '
      '       t.typname::text AS name, '
      '       array_agg(e.enumlabel::text ORDER BY e.enumsortorder) AS labels '
      'FROM pg_type t '
      'JOIN pg_enum e ON e.enumtypid = t.oid '
      'JOIN pg_namespace n ON n.oid = t.typnamespace '
      "WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') "
      "  AND n.nspname NOT LIKE 'pg_toast%' "
      "  AND n.nspname NOT LIKE 'pg_temp_%' "
      'GROUP BY n.nspname, t.typname '
      'ORDER BY n.nspname, t.typname',
    );
    return [
      for (final row in result)
        DbEnum(
          schema: row[0] as String,
          name: row[1] as String,
          labels: _stringList(row[2]),
        ),
    ];
  }

  /// All user-defined domain types.
  @override
  Future<List<DbDomain>> loadAllDomains() async {
    final result = await _db.execute(
      'SELECT n.nspname::text AS schema, '
      '       t.typname::text AS name, '
      '       format_type(t.typbasetype, t.typtypmod) AS base_type, '
      '       t.typnotnull AS not_null '
      'FROM pg_type t '
      'JOIN pg_namespace n ON n.oid = t.typnamespace '
      "WHERE t.typtype = 'd' "
      "  AND n.nspname NOT IN ('pg_catalog', 'information_schema') "
      "  AND n.nspname NOT LIKE 'pg_toast%' "
      "  AND n.nspname NOT LIKE 'pg_temp_%' "
      'ORDER BY n.nspname, t.typname',
    );
    return [
      for (final row in result)
        DbDomain(
          schema: row[0] as String,
          name: row[1] as String,
          baseType: row[2] as String,
          notNull: row[3] as bool,
        ),
    ];
  }

  static DbRelationKind _kindFromRelkind(String k) {
    switch (k) {
      case 'v':
        return DbRelationKind.view;
      case 'm':
        return DbRelationKind.materializedView;
      case 'r':
      case 'p':
      default:
        return DbRelationKind.table;
    }
  }

  /// Maps pg_constraint's single-char action codes to human-readable strings
  /// matching the SQL action clause names.
  static String? _fkAction(String? code) {
    switch (code) {
      case 'a':
        return null; // NO ACTION — default, suppress
      case 'r':
        return 'RESTRICT';
      case 'c':
        return 'CASCADE';
      case 'n':
        return 'SET NULL';
      case 'd':
        return 'SET DEFAULT';
      default:
        return null;
    }
  }

  /// Coerces a Postgres array result into a `List<String>`. The driver can
  /// return either a Dart `List` (with mixed runtime types) or null when the
  /// underlying array was NULL.
  static List<String> _stringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return [
        for (final v in value)
          if (v != null) v.toString(),
      ];
    }
    return const [];
  }
}
