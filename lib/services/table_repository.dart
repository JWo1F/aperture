import 'package:postgres/postgres.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'driver_decoder.dart';
import 'sql_identifier.dart';

List<Object?> _decodeRow(List<Object?> raw) =>
    [for (final v in raw) decodeDriverValue(v)];

/// Per-relation database operations: paging, exporting, applying cell
/// edits, building the DDL for the schema viewer.
///
/// Split out of [PostgresService] so tests can drive a fake `Connection`
/// without spinning up a real server, and so the connection-lifecycle
/// concerns (open / close / runQuery / health checks) stay focused.
class TableRepository {
  TableRepository(this._conn);

  final Connection _conn;

  String _whereClause(String filter) {
    final trimmed = filter.trim();
    return trimmed.isEmpty ? '' : ' WHERE $trimmed';
  }

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
  Future<int> countRows(DbTable table, {String filter = ''}) async {
    final result = await _conn.execute(
      'SELECT count(*) FROM ${table.qualifiedName}${_whereClause(filter)}',
      timeout: _pageQueryTimeout,
    );
    return (result.first.first as int?) ?? 0;
  }

  /// One page of rows from a relation. Each row carries its `ctid` so the UI
  /// can later target it for updates; the ctid is returned separately and is
  /// never shown as a data column.
  Future<QueryResult> fetchPage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    final watch = Stopwatch()..start();
    final order = orderBy.trim().isEmpty ? '' : ' ORDER BY ${orderBy.trim()}';
    final projection = _projection(selectList);
    try {
      final result = await _conn.execute(
        'SELECT t.ctid::text AS __ctid, $projection '
        'FROM ${table.qualifiedName} AS t'
        '${_whereClause(filter)}'
        '$order '
        'LIMIT $limit OFFSET $offset',
        timeout: _pageQueryTimeout,
      );
      watch.stop();

      final dataSchemas = result.schema.columns.sublist(1);
      final columns = dataSchemas
          .map((c) => c.columnName ?? 'column')
          .toList();
      final columnSchemas = dataSchemas
          .map(
            (c) => ResultColumnSchema(
              name: c.columnName ?? 'column',
              tableOid: c.tableOid,
              columnAttNum: c.columnOid,
            ),
          )
          .toList();
      final rows = <List<dynamic>>[];
      final rowIds = <String>[];
      for (final row in result) {
        final values = row.toList();
        rowIds.add(values.first as String);
        rows.add(_decodeRow(values.sublist(1)));
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
  Future<QueryResult> fetchAll(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    final order =
        orderBy.trim().isEmpty ? '' : ' ORDER BY ${orderBy.trim()}';
    final watch = Stopwatch()..start();
    final projection = _projection(selectList, aliased: false);
    final result = await _conn.execute(
      'SELECT $projection FROM ${table.qualifiedName}'
      '${_whereClause(filter)}$order',
    );
    watch.stop();
    final columns = result.schema.columns
        .map((c) => c.columnName ?? 'column')
        .toList();
    final rows = [for (final r in result) _decodeRow(r.toList())];
    return QueryResult.rows(
      columns: columns,
      rows: rows,
      elapsed: watch.elapsed,
    );
  }

  /// Reconstructs a readable DDL for [table]: `CREATE TABLE` with columns,
  /// table-level constraints (PK / FK / UNIQUE / CHECK) and trailing
  /// `CREATE INDEX` statements.
  Future<String> loadDdl(DbTable table) async {
    final regclass = "'${qualify(table.schema, table.name)}'::regclass";

    // pg_catalog columns of type `name` (OID 19) have no built-in codec in
    // the postgres driver, so they come back as UndecodedBytes — explicit
    // `::text` casts force textual output and a clean String in Dart.
    final columns = await _conn.execute(
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

    final constraints = await _conn.execute(
      'SELECT conname::text, contype::text, pg_get_constraintdef(oid) '
      'FROM pg_constraint '
      "WHERE conrelid = $regclass AND contype IN ('p', 'f', 'u', 'c') "
      'ORDER BY CASE contype '
      "WHEN 'p' THEN 1 WHEN 'u' THEN 2 WHEN 'f' THEN 3 ELSE 4 END, "
      'conname',
      timeout: _ddlQueryTimeout,
    );

    final indexes = await _conn.execute(
      Sql.named(
        'SELECT indexname::text, indexdef FROM pg_indexes '
        'WHERE schemaname = @schema AND tablename = @table '
        '  AND indexname NOT IN ('
        '    SELECT conname::text FROM pg_constraint '
        "    WHERE conrelid = (quote_ident(@schema) || '.' || quote_ident(@table))::regclass "
        "      AND contype IN ('p', 'u')"
        '  ) '
        'ORDER BY indexname',
      ),
      parameters: {'schema': table.schema, 'table': table.name},
      timeout: _ddlQueryTimeout,
    );

    final comment = await _conn.execute(
      'SELECT obj_description($regclass, \'pg_class\')',
      timeout: _ddlQueryTimeout,
    );

    final colNames = [for (final r in columns) quoteIdent(r[0] as String)];
    final colTypes = [for (final r in columns) r[1] as String];
    final nameWidth =
        colNames.fold<int>(0, (m, s) => s.length > m ? s.length : m);
    final typeWidth =
        colTypes.fold<int>(0, (m, s) => s.length > m ? s.length : m);

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
    final tableComment =
        comment.isEmpty ? null : comment.first.first as String?;
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

  /// Applies pending cell edits as one transaction of `UPDATE` statements,
  /// one per affected row keyed by `ctid`. Runs under REPEATABLE READ so the
  /// snapshot used to resolve the ctids stays consistent for the whole batch.
  ///
  /// If any statement affects a row count other than 1, the whole batch is
  /// rolled back and [StaleRowException] is thrown — the row's ctid was
  /// moved by a concurrent VACUUM FULL / HOT update / DELETE, or the row was
  /// never matched. The caller should ask the user to reload and retry.
  Future<int> applyEdits(
    DbTable table,
    Map<String, Map<String, CellEditValue>> updatesByCtid,
  ) async {
    if (updatesByCtid.isEmpty) return 0;
    final ctids = updatesByCtid.keys.toList(growable: false);
    final statements = buildEditStatements(table, updatesByCtid);
    try {
      return await _conn.runTx(
        (session) async {
          var affected = 0;
          for (var i = 0; i < statements.length; i++) {
            final result = await session.execute(statements[i]);
            if (result.affectedRows != 1) {
              throw StaleRowException(
                ctid: ctids[i],
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

/// Pure builder for the per-ctid UPDATE statements that would be sent to the
/// database. Lives at top level so the preview UI can render the same SQL
/// without holding a connection.
List<String> buildEditStatements(
  DbTable table,
  Map<String, Map<String, CellEditValue>> updatesByCtid,
) {
  return [
    for (final entry in updatesByCtid.entries)
      _renderUpdate(table, entry.key, entry.value),
  ];
}

String _renderUpdate(
  DbTable table,
  String ctid,
  Map<String, CellEditValue> assignments,
) {
  final lines = assignments.entries
      .map((e) => '  ${quoteIdent(e.key)} = ${_renderAssignment(e.value)}')
      .join(',\n');
  return 'UPDATE ${table.qualifiedName} SET\n'
      '$lines\n'
      "WHERE ctid = '$ctid'::tid";
}

String _renderAssignment(CellEditValue value) => switch (value) {
      CellLiteral(:final value) => _literal(value),
      CellDefault() => 'DEFAULT',
    };

/// Renders a value as a SQL literal. Strings stay untyped ('unknown') so
/// Postgres coerces them into the target column type; single quotes are
/// doubled to neutralise injection.
String _literal(String? value) {
  if (value == null) return 'NULL';
  return "'${value.replaceAll("'", "''")}'";
}

/// Thrown when an UPDATE batch hits a row whose ctid no longer matches.
/// ctid is a physical row pointer: VACUUM FULL, CLUSTER, HOT updates, and
/// concurrent DELETEs all move it. When this fires the transaction has
/// already rolled back, so no partial edit is committed.
class StaleRowException implements Exception {
  StaleRowException({
    required this.ctid,
    required this.affectedRows,
    required this.table,
  });

  final String ctid;
  final int affectedRows;
  final DbTable table;

  @override
  String toString() =>
      'Row no longer matches in ${table.qualifiedName} '
      '(ctid $ctid affected $affectedRows rows). Reload and retry.';
}

/// Wraps a database-side failure during an edit batch so the UI layer never
/// sees a raw driver exception type.
class EditFailureException implements Exception {
  EditFailureException(this.message);
  final String message;

  @override
  String toString() => message;
}
