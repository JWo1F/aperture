import '../models/db_object.dart';
import 'introspector.dart';
import 'mysql_service.dart';
import 'sql_identifier.dart';

const _sql = SqlDialect.mysql;

/// Catalog introspection for a MySQL or MariaDB database, read from
/// `information_schema`.
///
/// The catalog shows the connection's database as its one schema: a MySQL
/// connection names a database the way a Postgres one does, and sweeping
/// every database on a shared server would load columns nobody asked for.
/// The name comes from the config, not `DATABASE()`, so a `USE` typed in
/// the editor doesn't move the sidebar.
///
/// MySQL has no relation oid. Ids are handed out per name on first sight
/// and kept for the introspector's life — one connection — so they stay
/// put across catalog refreshes and a table created mid-session gets a
/// fresh one instead of shifting its neighbours.
///
/// Sweeps run unlogged, like SQLite's PRAGMAs, so the activity log keeps
/// to the statements the user and the grid sent.
class MysqlIntrospector implements Introspector {
  MysqlIntrospector(this._db);

  final MysqlService _db;

  final Map<String, int> _relationIds = {};
  final Map<String, int> _routineIds = {};

  String get _schema => _db.config.database;

  String get _schemaLiteral => _sql.literal(_schema);

  int _relationId(String name) =>
      _relationIds.putIfAbsent(name, () => _relationIds.length + 1);

  Future<List<List<Object?>>> _rows(String sql) async =>
      (await _db.execute(sql, log: false)).rows;

  @override
  Future<List<DbSchema>> loadSchemas() async {
    final rows = await _rows(
      'SELECT TABLE_NAME, TABLE_TYPE, TABLE_COMMENT, TABLE_ROWS, '
      '       DATA_LENGTH + INDEX_LENGTH '
      'FROM information_schema.TABLES '
      'WHERE TABLE_SCHEMA = $_schemaLiteral '
      "  AND TABLE_TYPE IN ('BASE TABLE', 'VIEW') "
      'ORDER BY TABLE_NAME',
    );
    final tables = [
      for (final r in rows)
        _table(
          name: r[0] as String,
          isView: r[1] == 'VIEW',
          comment: r[2] as String?,
          rows: r[3] as int?,
          bytes: r[4] as int?,
        ),
    ];
    if (tables.isEmpty) return const [];
    return [DbSchema(name: _schema, tables: tables)];
  }

  /// `TABLE_COMMENT` is the word `VIEW` for every view, and InnoDB's
  /// `TABLE_ROWS` is an estimate — which is what [DbTable.rowEstimate]
  /// holds anyway.
  DbTable _table({
    required String name,
    required bool isView,
    required String? comment,
    required int? rows,
    required int? bytes,
  }) => DbTable(
    oid: _relationId(name),
    schema: _schema,
    name: name,
    kind: isView ? DbRelationKind.view : DbRelationKind.table,
    dialect: _sql,
    comment: isView || comment == null || comment.isEmpty ? null : comment,
    rowEstimate: isView ? null : rows,
    sizeBytes: bytes != null && bytes > 0 ? bytes : null,
  );

  /// `isPrimaryKey` comes from the `PRIMARY` index rather than
  /// `COLUMN_KEY = 'PRI'`, which MySQL also prints for the columns of a
  /// unique not-null index on a table without a primary key.
  @override
  Future<Map<int, List<DbColumn>>> loadAllColumns() async {
    final primary = await _primaryKeyColumns();
    final rows = await _rows(
      'SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, '
      '       COLUMN_DEFAULT, EXTRA, ORDINAL_POSITION, COLUMN_COMMENT '
      'FROM information_schema.COLUMNS '
      'WHERE TABLE_SCHEMA = $_schemaLiteral '
      'ORDER BY TABLE_NAME, ORDINAL_POSITION',
    );
    final out = <int, List<DbColumn>>{};
    for (final r in rows) {
      final table = r[0] as String;
      final name = r[1] as String;
      final extra = ((r[5] as String?) ?? '').toLowerCase();
      final comment = r[7] as String?;
      out
          .putIfAbsent(_relationId(table), () => [])
          .add(
            DbColumn(
              name: name,
              dataType: r[2] as String,
              nullable: r[3] == 'YES',
              isPrimaryKey: primary.contains('$table.$name'),
              hasDefault:
                  r[4] != null ||
                  extra.contains('auto_increment') ||
                  extra.contains('default_generated'),
              ordinal: r[6] as int,
              comment: comment == null || comment.isEmpty ? null : comment,
            ),
          );
    }
    return out;
  }

  Future<Set<String>> _primaryKeyColumns() async {
    final rows = await _rows(
      'SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.STATISTICS '
      "WHERE TABLE_SCHEMA = $_schemaLiteral AND INDEX_NAME = 'PRIMARY'",
    );
    return {for (final r in rows) '${r[0]}.${r[1]}'};
  }

  @override
  Future<Map<int, List<DbForeignKey>>> loadAllForeignKeys() async {
    final rows = await _rows(
      'SELECT k.TABLE_NAME, k.CONSTRAINT_NAME, k.COLUMN_NAME, '
      '       k.REFERENCED_TABLE_SCHEMA, k.REFERENCED_TABLE_NAME, '
      '       k.REFERENCED_COLUMN_NAME, r.UPDATE_RULE, r.DELETE_RULE '
      'FROM information_schema.KEY_COLUMN_USAGE k '
      'JOIN information_schema.REFERENTIAL_CONSTRAINTS r '
      '  ON r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA '
      '  AND r.TABLE_NAME = k.TABLE_NAME '
      '  AND r.CONSTRAINT_NAME = k.CONSTRAINT_NAME '
      'WHERE k.TABLE_SCHEMA = $_schemaLiteral '
      '  AND k.REFERENCED_TABLE_NAME IS NOT NULL '
      'ORDER BY k.TABLE_NAME, k.CONSTRAINT_NAME, k.ORDINAL_POSITION',
    );
    // One row per column; consecutive rows of a constraint fold into it.
    final out = <int, List<DbForeignKey>>{};
    String? current;
    late List<String> local;
    late List<String> referenced;
    for (final r in rows) {
      final table = r[0] as String;
      final constraint = r[1] as String;
      if ('$table.$constraint' != current) {
        current = '$table.$constraint';
        local = [];
        referenced = [];
        final refSchema = r[3] as String;
        final refTable = r[4] as String;
        out
            .putIfAbsent(_relationId(table), () => [])
            .add(
              DbForeignKey(
                constraintName: constraint,
                localColumns: local,
                refSchema: refSchema,
                refTable: refTable,
                refTableOid: refSchema == _schema
                    ? _relationId(refTable)
                    : DbTable.unknownOid,
                refColumns: referenced,
                onUpdate: _fkAction(r[6] as String?),
                onDelete: _fkAction(r[7] as String?),
              ),
            );
      }
      local.add(r[2] as String);
      referenced.add(r[5] as String);
    }
    return out;
  }

  /// `NO ACTION` is the default, suppressed the way the Postgres catalog
  /// suppresses it. MySQL also treats it as `RESTRICT`.
  static String? _fkAction(String? rule) =>
      rule == null || rule == 'NO ACTION' ? null : rule;

  /// MySQL has no separate UNIQUE constraint: one is a unique index, so
  /// keys are the `PRIMARY` index and every other unique one.
  @override
  Future<Map<int, List<DbKey>>> loadAllKeys() async {
    final out = <int, List<DbKey>>{};
    for (final index in await _indexes()) {
      if (!index.unique) continue;
      final primary = index.name == 'PRIMARY';
      final keys = out.putIfAbsent(index.relationId, () => []);
      final key = DbKey(
        name: index.name,
        kind: primary ? DbKeyKind.primary : DbKeyKind.unique,
        columns: index.columns,
      );
      primary ? keys.insert(0, key) : keys.add(key);
    }
    return out;
  }

  /// The `PRIMARY` index carries no DDL of its own — it is the table's
  /// `PRIMARY KEY` clause — so its `def` stays empty, like a Postgres
  /// constraint-backed index.
  @override
  Future<Map<int, List<DbIndex>>> loadAllIndexes() async {
    final out = <int, List<DbIndex>>{};
    for (final index in await _indexes()) {
      final columns = index.columns.map(_sql.quoteIdent).join(', ');
      out
          .putIfAbsent(index.relationId, () => [])
          .add(
            DbIndex(
              name: index.name,
              columns: index.columns,
              unique: index.unique,
              def: index.name == 'PRIMARY'
                  ? ''
                  : 'CREATE ${index.unique ? 'UNIQUE ' : ''}'
                        '${index.type == 'BTREE' ? '' : '${index.type} '}'
                        'INDEX ${_sql.quoteIdent(index.name)} '
                        'ON ${_sql.qualify(_schema, index.table)} '
                        '($columns)',
            ),
          );
    }
    return out;
  }

  /// A functional index part has no `COLUMN_NAME`; it shows as `(expr)`.
  Future<List<_Index>> _indexes() async {
    final rows = await _rows(
      'SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE, COLUMN_NAME, INDEX_TYPE '
      'FROM information_schema.STATISTICS '
      'WHERE TABLE_SCHEMA = $_schemaLiteral '
      'ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX',
    );
    final out = <_Index>[];
    for (final r in rows) {
      final table = r[0] as String;
      final name = r[1] as String;
      if (out.isEmpty || out.last.table != table || out.last.name != name) {
        out.add(
          _Index(
            table: table,
            relationId: _relationId(table),
            name: name,
            unique: '${r[2]}' == '0',
            type: (r[4] as String?) ?? 'BTREE',
          ),
        );
      }
      out.last.columns.add((r[3] as String?) ?? '(expr)');
    }
    return out;
  }

  @override
  Future<List<DbRoutine>> loadAllRoutines() async {
    final params = await _rows(
      'SELECT SPECIFIC_NAME, ROUTINE_TYPE, PARAMETER_MODE, PARAMETER_NAME, '
      '       DTD_IDENTIFIER '
      'FROM information_schema.PARAMETERS '
      'WHERE SPECIFIC_SCHEMA = $_schemaLiteral AND ORDINAL_POSITION > 0 '
      'ORDER BY SPECIFIC_NAME, ORDINAL_POSITION',
    );
    final arguments = <String, List<String>>{};
    for (final p in params) {
      final mode = p[2] as String?;
      arguments
          .putIfAbsent('${p[1]}.${p[0]}', () => [])
          .add(
            [
              if (p[1] == 'PROCEDURE' && mode != null) mode,
              p[3],
              p[4],
            ].join(' '),
          );
    }
    final rows = await _rows(
      'SELECT ROUTINE_NAME, ROUTINE_TYPE, DTD_IDENTIFIER '
      'FROM information_schema.ROUTINES '
      'WHERE ROUTINE_SCHEMA = $_schemaLiteral '
      'ORDER BY ROUTINE_NAME, ROUTINE_TYPE',
    );
    return [
      for (final r in rows)
        DbRoutine(
          oid: _routineIds.putIfAbsent(
            '${r[1]}.${r[0]}',
            () => _routineIds.length + 1,
          ),
          schema: _schema,
          name: r[0] as String,
          kind: r[1] == 'PROCEDURE'
              ? DbRoutineKind.procedure
              : DbRoutineKind.function,
          arguments: (arguments['${r[1]}.${r[0]}'] ?? const []).join(', '),
          dialect: _sql,
          result: r[1] == 'FUNCTION' ? r[2] as String? : null,
        ),
    ];
  }

  /// Wrapped in `DELIMITER` lines so the definition, pasted into the query
  /// editor, runs as one statement despite the `;` inside its body.
  /// `SHOW CREATE` leaves the definition NULL for a user who may call the
  /// routine but not read it.
  @override
  Future<String> loadRoutineDdl(DbRoutine routine) async {
    final kind = routine.kind == DbRoutineKind.procedure
        ? 'PROCEDURE'
        : 'FUNCTION';
    final rows = await _rows('SHOW CREATE $kind ${routine.qualifiedName}');
    final def = rows.isEmpty ? null : rows.first[2] as String?;
    if (def == null) {
      return '-- The definition of ${routine.qualifiedName} is hidden: '
          'reading it needs SHOW_ROUTINE or ownership.\n';
    }
    return 'DELIMITER \$\$\n${def.trimRight()}\$\$\nDELIMITER ;\n';
  }

  @override
  Future<List<DbEnum>> loadAllEnums() async => const [];

  @override
  Future<List<DbDomain>> loadAllDomains() async => const [];

  @override
  Future<List<DbSequence>> loadAllSequences() async => const [];

  @override
  Future<String> loadSequenceDdl(DbSequence sequence) =>
      throw UnsupportedError('MySQL catalogs list no sequences');

  @override
  Future<String> loadEnumDdl(DbEnum type) =>
      throw UnsupportedError('MySQL catalogs list no enum types');

  @override
  Future<String> loadDomainDdl(DbDomain domain) =>
      throw UnsupportedError('MySQL catalogs list no domains');
}

/// One index from `information_schema.STATISTICS`, columns in key order.
class _Index {
  _Index({
    required this.table,
    required this.relationId,
    required this.name,
    required this.unique,
    required this.type,
  });

  final String table;
  final int relationId;
  final String name;
  final bool unique;
  final String type;
  final List<String> columns = [];
}
