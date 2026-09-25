import '../models/db_object.dart';
import 'introspector.dart';
import 'postgres_service.dart';
import 'sql_render.dart';

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
      "       obj_description(c.oid, 'pg_class') AS comment, "
      '       c.reltuples::bigint AS row_est, '
      '       pg_total_relation_size(c.oid) AS size_bytes '
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
      // `reltuples` is -1 for never-analyzed relations and a meaningless 0 for
      // plain views (no storage) — normalize both to null.
      final rowEst = row[5] as int?;
      final sizeBytes = row[6] as int?;
      final hasRowEstimate = kind != 'v' && rowEst != null && rowEst >= 0;
      grouped
          .putIfAbsent(schema, () => [])
          .add(
            DbTable(
              oid: oid,
              schema: schema,
              name: name,
              kind: _kindFromRelkind(kind),
              comment: comment,
              rowEstimate: hasRowEstimate ? rowEst : null,
              sizeBytes: sizeBytes != null && sizeBytes > 0 ? sizeBytes : null,
              partitioned: kind == 'p',
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

  /// Primary-key and UNIQUE constraints for every relation, keyed by relation
  /// oid. `conkey` is expanded into an ordered column-name array the same way
  /// the FK sweep does it.
  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async {
    final result = await _db.execute(
      'SELECT c.conrelid::bigint AS rel_oid, '
      '       c.conname::text AS name, '
      '       c.contype::text AS kind, '
      '       ('
      '         SELECT array_agg(att.attname::text ORDER BY u.ord) '
      '         FROM unnest(c.conkey) WITH ORDINALITY AS u(att_num, ord) '
      '         JOIN pg_attribute att '
      '           ON att.attrelid = c.conrelid '
      '          AND att.attnum = u.att_num'
      '       ) AS cols '
      'FROM pg_constraint c '
      'JOIN pg_class cls ON cls.oid = c.conrelid '
      'JOIN pg_namespace n ON n.oid = cls.relnamespace '
      "WHERE c.contype IN ('p', 'u') "
      '  AND $_systemSchemaFilter '
      'ORDER BY c.conrelid, c.contype, c.conname',
    );

    final out = <int, List<DbKey>>{};
    for (final row in result) {
      final relOid = row[0] as int;
      final cols = _stringList(row[3]);
      if (cols.isEmpty) continue;
      out
          .putIfAbsent(relOid, () => [])
          .add(
            DbKey(
              name: row[1] as String,
              kind: (row[2] as String) == 'p'
                  ? DbKeyKind.primary
                  : DbKeyKind.unique,
              columns: cols,
            ),
          );
    }
    return out;
  }

  /// Every index for every relation, keyed by relation oid — including the
  /// indexes that back primary-key / UNIQUE constraints.
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

  /// Functions (plain and window) and procedures. Aggregates are left out —
  /// `pg_get_functiondef` can't render them — and so is everything an
  /// extension installed, which would otherwise bury the user's own
  /// routines under hundreds of pgcrypto / PostGIS entries.
  @override
  Future<List<DbRoutine>> loadAllRoutines() async {
    final result = await _db.execute(
      'SELECT p.oid::bigint, n.nspname::text, p.proname::text, '
      '       p.prokind::text, '
      '       pg_get_function_identity_arguments(p.oid), '
      "       CASE WHEN p.prokind = 'p' THEN NULL "
      '            ELSE pg_get_function_result(p.oid) END '
      'FROM pg_proc p '
      'JOIN pg_namespace n ON n.oid = p.pronamespace '
      "WHERE p.prokind IN ('f', 'w', 'p') "
      '  AND $_systemSchemaFilter '
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM pg_depend d '
      "    WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid "
      "      AND d.deptype = 'e'"
      '  ) '
      'ORDER BY n.nspname, p.proname, 5',
    );
    return [
      for (final row in result)
        DbRoutine(
          oid: row[0] as int,
          schema: row[1] as String,
          name: row[2] as String,
          kind: row[3] == 'p'
              ? DbRoutineKind.procedure
              : DbRoutineKind.function,
          arguments: row[4] as String? ?? '',
          result: row[5] as String?,
        ),
    ];
  }

  /// Sequences that stand on their own. Identity-column sequences
  /// (`deptype = 'i'`) and extension members are skipped; a `serial`
  /// column's sequence (`deptype = 'a'`) stays, since it is a real,
  /// separately-named object the user can call `nextval` on.
  @override
  Future<List<DbSequence>> loadAllSequences() async {
    final result = await _db.execute(
      'SELECT c.oid::bigint, n.nspname::text, c.relname::text '
      'FROM pg_class c '
      'JOIN pg_namespace n ON n.oid = c.relnamespace '
      "WHERE c.relkind = 'S' "
      '  AND $_systemSchemaFilter '
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM pg_depend d '
      "    WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid "
      "      AND d.deptype IN ('i', 'e')"
      '  ) '
      'ORDER BY n.nspname, c.relname',
    );
    return [
      for (final row in result)
        DbSequence(
          oid: row[0] as int,
          schema: row[1] as String,
          name: row[2] as String,
        ),
    ];
  }

  @override
  Future<String> loadRoutineDdl(DbRoutine routine) async {
    final result = await _db.execute(
      'SELECT pg_get_functiondef(${routine.oid})',
    );
    final def = (result.first[0] as String).trimRight();
    return '$def;\n';
  }

  @override
  Future<String> loadSequenceDdl(DbSequence sequence) async {
    final result = await _db.execute(
      'SELECT format_type(s.seqtypid, NULL), s.seqincrement, s.seqmin, '
      '       s.seqmax, s.seqstart, s.seqcache, s.seqcycle, '
      "       CASE WHEN has_sequence_privilege(s.seqrelid, 'SELECT') "
      '            THEN pg_sequence_last_value(s.seqrelid) END, '
      "       (SELECT quote_ident(tn.nspname) || '.' "
      "               || quote_ident(t.relname) || '.' "
      '               || quote_ident(a.attname) '
      '        FROM pg_depend d '
      '        JOIN pg_class t ON t.oid = d.refobjid '
      '        JOIN pg_namespace tn ON tn.oid = t.relnamespace '
      '        JOIN pg_attribute a '
      '          ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid '
      "        WHERE d.classid = 'pg_class'::regclass "
      '          AND d.objid = s.seqrelid '
      "          AND d.refclassid = 'pg_class'::regclass "
      "          AND d.deptype = 'a' LIMIT 1) "
      'FROM pg_sequence s WHERE s.seqrelid = ${sequence.oid}',
    );
    final r = result.first;
    final lastValue = r[7];
    final ownedBy = r[8] as String?;
    final lines = [
      if (lastValue != null) '-- last value: $lastValue',
      'CREATE SEQUENCE ${sequence.qualifiedName}',
      '  AS ${r[0]}',
      '  INCREMENT BY ${r[1]}',
      '  MINVALUE ${r[2]}',
      '  MAXVALUE ${r[3]}',
      '  START WITH ${r[4]}',
      '  CACHE ${r[5]}',
      (r[6] as bool) ? '  CYCLE' : '  NO CYCLE',
      if (ownedBy != null) '  OWNED BY $ownedBy',
    ];
    return '${lines.join('\n')};\n';
  }

  @override
  Future<String> loadEnumDdl(DbEnum type) async {
    final labels = [for (final l in type.labels) '  ${literalSql(l)}'];
    return 'CREATE TYPE ${type.qualifiedName} AS ENUM (\n'
        '${labels.join(',\n')}\n'
        ');\n';
  }

  @override
  Future<String> loadDomainDdl(DbDomain domain) async {
    final result = await _db.execute(
      'SELECT format_type(t.typbasetype, t.typtypmod), t.typdefault, '
      '       t.typnotnull, '
      "       (SELECT array_agg('CONSTRAINT ' || quote_ident(c.conname) "
      "                         || ' ' || pg_get_constraintdef(c.oid) "
      '                         ORDER BY c.conname) '
      '        FROM pg_constraint c '
      "        WHERE c.contypid = t.oid AND c.contype = 'c') "
      'FROM pg_type t '
      'WHERE t.oid = ${literalSql(domain.qualifiedName)}::regtype',
    );
    final r = result.first;
    final def = r[1] as String?;
    final lines = [
      'CREATE DOMAIN ${domain.qualifiedName} AS ${r[0]}',
      if (def != null) '  DEFAULT $def',
      if (r[2] as bool) '  NOT NULL',
      for (final c in _stringList(r[3])) '  $c',
    ];
    return '${lines.join('\n')};\n';
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
