import 'package:postgres/postgres.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'driver_decoder.dart';
import 'postgres_service.dart';
import 'sql_identifier.dart';
import 'sql_render.dart';
import 'table_repository.dart';

/// Postgres per-relation operations: paging, exporting, applying cell edits,
/// building DDL for the schema viewer.
///
/// All statements run through [PostgresService.execute] / [runTx] — the
/// single SQL channel that captures every query in the activity log.
class PostgresTableRepository implements TableRepository {
  PostgresTableRepository(this._db);

  final PostgresService _db;

  /// Expands the user-supplied SELECT list into a projection clause. `*` and
  /// empty become `*` (qualified to `t.*` when the table is aliased);
  /// anything else is trusted as-is.
  String _projection(String selectList, {bool aliased = true}) {
    final trimmed = selectList.trim();
    if (trimmed.isEmpty || trimmed == '*') return aliased ? 't.*' : '*';
    return trimmed;
  }

  static const _pageQueryTimeout = Duration(seconds: 60);
  static const _ddlQueryTimeout = Duration(seconds: 30);

  /// Total row count for a relation under the active filter.
  ///
  /// `count(*)` is a full scan — seconds to minutes on a relation of tens of
  /// millions of rows. For the unfiltered case we instead read the planner's
  /// `reltuples` estimate from `pg_class`, an O(1) catalog lookup. The
  /// estimate is only trusted when positive: `reltuples` is -1 before a
  /// relation has ever been analyzed and 0 for views and empty tables, and
  /// for all of those an exact `count(*)` is cheap anyway.
  @override
  Future<int> countRows(DbTable table, {String filter = ''}) async {
    if (filter.trim().isEmpty) {
      final estimate = await _estimatedRowCount(table);
      if (estimate != null) return estimate;
    }
    validateClauseSnippet(filter, kind: ClauseKind.filter);
    final result = await _db.execute(
      'SELECT count(*) FROM ${table.qualifiedName}${whereClause(filter)}',
      timeout: _pageQueryTimeout,
    );
    return (result.first.first as int?) ?? 0;
  }

  /// Planner row estimate for [table], or null when no trustworthy estimate
  /// exists (relation never analyzed, a view, or genuinely empty) — callers
  /// fall back to an exact `count(*)`.
  Future<int?> _estimatedRowCount(DbTable table) async {
    final literal = table.qualifiedName.replaceAll("'", "''");
    try {
      final result = await _db.execute(
        "SELECT reltuples::bigint FROM pg_class "
        "WHERE oid = '$literal'::regclass",
        timeout: _ddlQueryTimeout,
      );
      final estimate = result.first.first as int?;
      return (estimate != null && estimate > 0) ? estimate : null;
    } catch (_) {
      return null;
    }
  }

  /// One page of rows from a relation. For regular tables each row carries
  /// its `ctid` so the UI can later target it for updates; the ctid is
  /// returned separately and is never shown as a data column. Views (and
  /// materialized views) have no usable `ctid` for editing — for views it
  /// doesn't exist at all and the query would fail — so we skip it.
  @override
  Future<QueryResult> fetchPage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    final watch = Stopwatch()..start();
    validateClauseSnippet(filter, kind: ClauseKind.filter);
    validateClauseSnippet(orderBy, kind: ClauseKind.orderBy);
    validateClauseSnippet(selectList, kind: ClauseKind.selectList);
    final order = orderClause(orderBy);
    final withCtid = table.kind == DbRelationKind.table;
    final projection = _projection(selectList, aliased: withCtid);
    final ctidPrefix = withCtid ? 't.ctid::text AS __ctid, ' : '';
    final fromClause = withCtid
        ? 'FROM ${table.qualifiedName} AS t'
        : 'FROM ${table.qualifiedName}';
    try {
      final result = await _db.execute(
        'SELECT $ctidPrefix$projection '
        '$fromClause'
        '${whereClause(filter)}'
        '$order '
        'LIMIT $limit OFFSET $offset',
        timeout: _pageQueryTimeout,
      );
      watch.stop();

      final dataSchemas = withCtid
          ? result.schema.columns.sublist(1)
          : result.schema.columns;
      final columns = dataSchemas.map((c) => c.columnName ?? 'column').toList();
      final columnSchemas = dataSchemas
          .map(
            (c) => ResultColumnSchema(
              name: c.columnName ?? 'column',
              tableOid: c.tableOid,
              columnAttNum: c.columnOid,
            ),
          )
          .toList();
      final rows = <List<Object?>>[];
      final rowIds = withCtid ? <String>[] : null;
      for (final row in result) {
        final values = row.toList();
        if (withCtid) {
          rowIds!.add(values.first as String);
          rows.add(decodeDriverRow(values.sublist(1)));
        } else {
          rows.add(decodeDriverRow(values));
        }
      }

      return QueryResult.rows(
        columns: columns,
        rows: rows,
        rowIds: rowIds,
        columnSchemas: columnSchemas,
        elapsed: watch.elapsed,
      );
    } on ServerException catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.message, elapsed: watch.elapsed);
    } catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.toString(), elapsed: watch.elapsed);
    }
  }

  /// Fetches every row of a relation under the active filter/order, with no
  /// pagination. Used by exporters; callers are expected to be aware that
  /// this materialises the entire result in memory.
  @override
  Future<QueryResult> fetchAll(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    validateClauseSnippet(filter, kind: ClauseKind.filter);
    validateClauseSnippet(orderBy, kind: ClauseKind.orderBy);
    validateClauseSnippet(selectList, kind: ClauseKind.selectList);
    final order = orderClause(orderBy);
    final watch = Stopwatch()..start();
    final projection = _projection(selectList, aliased: false);
    final result = await _db.execute(
      'SELECT $projection FROM ${table.qualifiedName}'
      '${whereClause(filter)}$order',
    );
    watch.stop();
    final columns = result.schema.columns
        .map((c) => c.columnName ?? 'column')
        .toList();
    final rows = [for (final r in result) decodeDriverRow(r.toList())];
    return QueryResult.rows(
      columns: columns,
      rows: rows,
      elapsed: watch.elapsed,
    );
  }

  /// Reconstructs a readable DDL for [table]: `CREATE TABLE` with columns,
  /// table-level constraints (PK / FK / UNIQUE / CHECK) and trailing
  /// `CREATE INDEX` statements.
  @override
  Future<String> loadDdl(DbTable table) async {
    final regclass = "'${qualify(table.schema, table.name)}'::regclass";

    // pg_catalog columns of type `name` (OID 19) have no built-in codec in
    // the postgres driver, so they come back as UndecodedBytes — explicit
    // `::text` casts force textual output and a clean String in Dart.
    final columns = await _db.execute(
      'SELECT a.attname::text, format_type(a.atttypid, a.atttypmod), '
      'NOT a.attnotnull, '
      'pg_get_expr(d.adbin, d.adrelid), '
      'col_description(a.attrelid, a.attnum) '
      'FROM pg_attribute a '
      'LEFT JOIN pg_attrdef d '
      '  ON d.adrelid = a.attrelid AND d.adnum = a.attnum '
      'WHERE a.attrelid = $regclass AND a.attnum > 0 AND NOT a.attisdropped '
      'ORDER BY a.attnum',
      timeout: _ddlQueryTimeout,
    );

    final constraints = await _db.execute(
      'SELECT conname::text, contype::text, pg_get_constraintdef(oid) '
      'FROM pg_constraint '
      "WHERE conrelid = $regclass AND contype IN ('p', 'f', 'u', 'c') "
      'ORDER BY CASE contype '
      "WHEN 'p' THEN 1 WHEN 'u' THEN 2 WHEN 'f' THEN 3 ELSE 4 END, "
      'conname',
      timeout: _ddlQueryTimeout,
    );

    final indexes = await _db.execute(
      'SELECT indexname::text, indexdef FROM pg_indexes '
      'WHERE schemaname = @schema AND tablename = @table '
      '  AND indexname NOT IN ('
      '    SELECT conname::text FROM pg_constraint '
      "    WHERE conrelid = (quote_ident(@schema) || '.' || quote_ident(@table))::regclass "
      "      AND contype IN ('p', 'u')"
      '  ) '
      'ORDER BY indexname',
      parameters: {'schema': table.schema, 'table': table.name},
      timeout: _ddlQueryTimeout,
    );

    final comment = await _db.execute(
      'SELECT obj_description($regclass, \'pg_class\')',
      timeout: _ddlQueryTimeout,
    );

    final colNames = [for (final r in columns) quoteIdent(r[0] as String)];
    final colTypes = [for (final r in columns) r[1] as String];
    final nameWidth = colNames.fold<int>(
      0,
      (m, s) => s.length > m ? s.length : m,
    );
    final typeWidth = colTypes.fold<int>(
      0,
      (m, s) => s.length > m ? s.length : m,
    );

    final colLines = <String>[];
    for (var i = 0; i < columns.length; i++) {
      final row = columns[i];
      final nullable = row[2] as bool;
      final defaultExpr = row[3] as String?;
      final tail = StringBuffer()..write(nullable ? 'NULL' : 'NOT NULL');
      if (defaultExpr != null) tail.write(' DEFAULT $defaultExpr');
      colLines.add(
        '  ${colNames[i].padRight(nameWidth)}  '
        '${colTypes[i].padRight(typeWidth)}  '
        '$tail',
      );
    }

    final constraintLines = <String>[
      for (final r in constraints)
        '  CONSTRAINT ${quoteIdent(r[0] as String)} ${r[2] as String}',
    ];

    final qualified = qualify(table.schema, table.name);
    final buf = StringBuffer();
    buf.writeln('-- Table: $qualified');
    buf.writeln(
      '-- ${columns.length} columns · '
      '${constraints.where((r) => r[1] as String == 'f').length} foreign keys · '
      '${indexes.length} indexes',
    );
    buf.writeln();
    buf.writeln('CREATE TABLE $qualified (');
    final allLines = [...colLines, ...constraintLines];
    buf.writeln(allLines.join(',\n'));
    buf.writeln(');');

    var hasComments = false;
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i][4] as String?;
      if (c == null) continue;
      if (!hasComments) {
        buf.writeln();
        hasComments = true;
      }
      final escaped = c.replaceAll("'", "''");
      buf.writeln(
        'COMMENT ON COLUMN $qualified.${quoteIdent(columns[i][0] as String)} '
        "IS '$escaped';",
      );
    }
    final tableComment = comment.isEmpty
        ? null
        : comment.first.first as String?;
    if (tableComment != null) {
      buf.writeln();
      final escaped = tableComment.replaceAll("'", "''");
      buf.writeln("COMMENT ON TABLE $qualified IS '$escaped';");
    }

    if (indexes.isNotEmpty) {
      buf.writeln();
      buf.writeln('-- Indexes');
      for (final r in indexes) {
        buf.writeln('${r[1] as String};');
      }
    }

    return buf.toString();
  }

  /// Applies a batch of pending UPDATEs, DELETEs, and INSERTs in one
  /// transaction. Runs under REPEATABLE READ so the snapshot used to
  /// resolve the ctids stays consistent for every statement.
  ///
  /// Any UPDATE or DELETE that doesn't affect exactly one row rolls the
  /// whole batch back and raises [StaleRowException] — the row's ctid was
  /// moved by a concurrent VACUUM FULL / HOT update / DELETE, or the row
  /// no longer exists. The caller should ask the user to reload and retry.
  @override
  Future<int> applyEdits(DbTable table, EditBatch batch) async {
    if (batch.isEmpty) return 0;
    final statements = buildPostgresEditStatements(table, batch);
    // Mirror the statement-list ordering used inside buildPostgresEditStatements
    // so a stale-row failure can name the ctid it stumbled on.
    final updateCtids = batch.updatesByCtid.keys.toList(growable: false);
    final deleteCtids = batch.deleteCtids;
    final mutationCount = updateCtids.length + deleteCtids.length;
    try {
      return await _db.runTx<int>(
        (scope) async {
          var affected = 0;
          for (var i = 0; i < statements.length; i++) {
            final result = await scope.execute(statements[i]);
            if (i < mutationCount && result.affectedRows != 1) {
              final ctid = i < updateCtids.length
                  ? updateCtids[i]
                  : deleteCtids[i - updateCtids.length];
              throw StaleRowException(
                rowId: ctid,
                affectedRows: result.affectedRows,
                table: table,
              );
            }
            affected += result.affectedRows;
          }
          return affected;
        },
        settings: TransactionSettings(
          isolationLevel: IsolationLevel.repeatableRead,
        ),
      );
    } on StaleRowException {
      rethrow;
    } on ServerException catch (e) {
      throw EditFailureException(e.message);
    }
  }
}

/// Pure builder for the SQL Postgres would receive for a batch of pending
/// edits. Thin wrapper around [buildEditStatements] with the Postgres-
/// specific row-identity + DEFAULT policy.
List<String> buildPostgresEditStatements(DbTable table, EditBatch batch) =>
    buildEditStatements(table, batch, _postgresPolicy);

final EditPolicy _postgresPolicy = EditPolicy(
  rowIdPredicate: (ctid) => "WHERE ctid = '$ctid'::tid",
  insertOmitsDefaultColumns: false,
  updateDropsDefaultAssignments: false,
);
