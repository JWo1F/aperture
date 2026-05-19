import 'package:postgres/postgres.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import '../state/workspace_tab.dart';

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

  /// Reads every user schema with its tables and views in one round trip.
  Future<List<DbSchema>> loadSchemas() async {
    final result = await _conn.execute(
      "SELECT table_schema, table_name, table_type "
      "FROM information_schema.tables "
      "WHERE table_schema NOT IN ('pg_catalog', 'information_schema') "
      "ORDER BY table_schema, table_name",
    );

    final grouped = <String, List<DbTable>>{};
    for (final row in result) {
      final schema = row[0] as String;
      final name = row[1] as String;
      final type = row[2] as String;
      grouped.putIfAbsent(schema, () => []).add(
            DbTable(
              schema: schema,
              name: name,
              kind: type == 'VIEW'
                  ? DbRelationKind.view
                  : DbRelationKind.table,
            ),
          );
    }

    return grouped.entries
        .map((e) => DbSchema(name: e.key, tables: e.value))
        .toList();
  }

  Future<List<DbColumn>> loadColumns(DbTable table) async {
    final result = await _conn.execute(
      Sql.named(
        'SELECT c.column_name, c.data_type, c.is_nullable, '
        'COALESCE(pk.is_pk, false) AS is_primary_key '
        'FROM information_schema.columns c '
        'LEFT JOIN ('
        '  SELECT kcu.column_name, true AS is_pk '
        '  FROM information_schema.table_constraints tc '
        '  JOIN information_schema.key_column_usage kcu '
        '    ON tc.constraint_name = kcu.constraint_name '
        '   AND tc.table_schema = kcu.table_schema '
        "  WHERE tc.constraint_type = 'PRIMARY KEY' "
        '    AND tc.table_schema = @schema AND tc.table_name = @table'
        ') pk ON pk.column_name = c.column_name '
        'WHERE c.table_schema = @schema AND c.table_name = @table '
        'ORDER BY c.ordinal_position',
      ),
      parameters: {'schema': table.schema, 'table': table.name},
    );

    return result
        .map(
          (row) => DbColumn(
            name: row[0] as String,
            dataType: row[1] as String,
            nullable: (row[2] as String) == 'YES',
            isPrimaryKey: row[3] as bool,
          ),
        )
        .toList();
  }

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

      final columns = result.schema.columns
          .map((c) => c.columnName ?? 'column')
          .toList()
        ..removeAt(0);
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
      final rows = result.map((row) => row.toList()).toList();

      return QueryResult.rows(
        columns: columns,
        rows: rows,
        elapsed: watch.elapsed,
        affectedRows: result.affectedRows,
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
