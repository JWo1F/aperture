import 'package:postgres/postgres.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import '../state/workspace_tab.dart';
import 'introspector.dart';

/// Wraps a single live Postgres connection: opening it, introspecting the
/// catalog, and running statements. One instance maps to one open connection.
class PostgresService {
  PostgresService(this.config);

  final ConnectionConfig config;
  Connection? _connection;

  bool get isConnected => _connection?.isOpen ?? false;

  Future<void> connect() async {
    _connection = await Connection.open(
      Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
      ),
      settings: ConnectionSettings(
        sslMode: config.useSsl ? SslMode.require : SslMode.disable,
        connectTimeout: const Duration(seconds: 10),
        applicationName: 'dbv',
      ),
    );
  }

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }

  Connection get _conn {
    final c = _connection;
    if (c == null || !c.isOpen) {
      throw StateError('Not connected');
    }
    return c;
  }

  /// Catalog introspector bound to this connection. The caller drives which
  /// sweeps to run (schemas + columns + FKs + indexes + enums + domains) and
  /// in what order — see [Introspector] for the individual queries.
  Introspector get introspector => Introspector(_conn);

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

  /// Total row count for a relation under the active filter.
  Future<int> countRows(DbTable table, {String filter = ''}) async {
    final result = await _conn.execute(
      'SELECT count(*) FROM ${table.qualifiedName}${_whereClause(filter)}',
    );
    return (result.first.first as int?) ?? 0;
  }

  /// One page of rows from a relation. Each row carries its `ctid` so the UI
  /// can later target it for updates; the ctid is returned separately and is
  /// never shown as a data column.
  Future<QueryResult> fetchTablePage(
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
      );
      watch.stop();

      // First schema column is the injected ctid — strip it from both the
      // column list and the per-column schemas before returning.
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
        rows.add(values.sublist(1));
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
  Future<QueryResult> fetchAllTableRows(
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
    final rows = result.map((r) => r.toList()).toList();
    return QueryResult.rows(
      columns: columns,
      rows: rows,
      elapsed: watch.elapsed,
    );
  }

  /// Reconstructs a readable DDL for [table]: `CREATE TABLE` with columns,
  /// table-level constraints (PK / FK / UNIQUE / CHECK) and trailing
  /// `CREATE INDEX` statements. Uses pg_catalog so the column types come back
  /// in canonical form (e.g. `numeric(8,2)`, `timestamp with time zone`).
  Future<String> loadTableDdl(DbTable table) async {
    final regclass =
        "'${_quoteIdent(table.schema)}.${_quoteIdent(table.name)}'::regclass";

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
    );

    final constraints = await _conn.execute(
      'SELECT conname::text, contype::text, pg_get_constraintdef(oid) '
      'FROM pg_constraint '
      "WHERE conrelid = $regclass AND contype IN ('p', 'f', 'u', 'c') "
      'ORDER BY CASE contype '
      "WHEN 'p' THEN 1 WHEN 'u' THEN 2 WHEN 'f' THEN 3 ELSE 4 END, "
      'conname',
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
    );

    final comment = await _conn.execute(
      'SELECT obj_description($regclass, \'pg_class\')',
    );

    // Build the column lines with aligned columns for readability.
    final colNames = [for (final r in columns) '"${r[0] as String}"'];
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
      final tail = StringBuffer()
        ..write(nullable ? 'NULL' : 'NOT NULL');
      if (defaultExpr != null) {
        tail.write(' DEFAULT $defaultExpr');
      }
      colLines.add(
        '  ${colNames[i].padRight(nameWidth)}  '
        '${colTypes[i].padRight(typeWidth)}  '
        '$tail',
      );
    }

    final constraintLines = <String>[
      for (final r in constraints)
        '  CONSTRAINT "${r[0] as String}" ${r[2] as String}',
    ];

    final buf = StringBuffer();
    buf.writeln(
      '-- Table: "${table.schema}"."${table.name}"',
    );
    buf.writeln(
      '-- ${columns.length} columns · '
      '${constraints.where((r) => r[1] as String == 'f').length} foreign keys · '
      '${indexes.length} indexes',
    );
    buf.writeln();
    buf.writeln(
      'CREATE TABLE "${table.schema}"."${table.name}" (',
    );
    final allLines = [...colLines, ...constraintLines];
    buf.writeln(allLines.join(',\n'));
    buf.writeln(');');

    // Column comments
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
        'COMMENT ON COLUMN "${table.schema}"."${table.name}"."${columns[i][0]}" '
        "IS '$escaped';",
      );
    }
    final tableComment = comment.isEmpty ? null : comment.first.first as String?;
    if (tableComment != null) {
      buf.writeln();
      final escaped = tableComment.replaceAll("'", "''");
      buf.writeln(
        'COMMENT ON TABLE "${table.schema}"."${table.name}" '
        "IS '$escaped';",
      );
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

  /// Doubles any embedded double-quotes for use inside a quoted identifier.
  String _quoteIdent(String name) => name.replaceAll('"', '""');

  /// Executes an arbitrary statement, capturing timing and errors so the UI
  /// never has to deal with raised exceptions directly.
  Future<QueryResult> runQuery(String sql) async {
    final watch = Stopwatch()..start();
    try {
      final result = await _conn.execute(sql);
      watch.stop();

      if (result.schema.columns.isEmpty) {
        return QueryResult.command(
          affectedRows: result.affectedRows,
          elapsed: watch.elapsed,
        );
      }

      final columns = result.schema.columns
          .map((c) => c.columnName ?? 'column')
          .toList();
      final columnSchemas = result.schema.columns
          .map(
            (c) => ResultColumnSchema(
              name: c.columnName ?? 'column',
              tableOid: c.tableOid,
              columnAttNum: c.columnOid,
            ),
          )
          .toList();
      final rows = result.map((row) => row.toList()).toList();

      return QueryResult.rows(
        columns: columns,
        rows: rows,
        elapsed: watch.elapsed,
        affectedRows: result.affectedRows,
        columnSchemas: columnSchemas,
      );
    } on ServerException catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.message, elapsed: watch.elapsed);
    } catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.toString(), elapsed: watch.elapsed);
    }
  }

  /// Applies pending cell edits as one transaction of `UPDATE` statements,
  /// one per affected row keyed by `ctid`. Throws on the first failure so the
  /// whole batch rolls back.
  Future<int> applyTableEdits(
    DbTable table,
    Map<String, Map<String, CellEditValue>> updatesByCtid,
  ) async {
    if (updatesByCtid.isEmpty) return 0;
    final statements = buildEditStatements(table, updatesByCtid);
    return _conn.runTx((session) async {
      var affected = 0;
      for (final sql in statements) {
        final result = await session.execute(sql);
        affected += result.affectedRows;
      }
      return affected;
    });
  }
}

/// Pure builder for the per-ctid UPDATE statements that would be sent to the
/// database. Lives at the top level so the preview UI can render the same
/// SQL without holding a connection.
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
      .map((e) => '  "${e.key}" = ${_renderAssignment(e.value)}')
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
