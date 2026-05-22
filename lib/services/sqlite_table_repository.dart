import 'package:sqlite3/sqlite3.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'sql_identifier.dart';
import 'sqlite_service.dart';
import 'table_repository.dart';

/// SQLite per-relation operations: paging, exporting, DDL, cell editing.
///
/// Row identity is the implicit integer `rowid`. Views and `WITHOUT ROWID`
/// tables have no `rowid`; for those, [fetchPage] returns a null `rowIds`
/// and the grid treats the page as read-only.
class SqliteTableRepository implements TableRepository {
  SqliteTableRepository(this._db);

  final SqliteService _db;

  String _whereClause(String filter) {
    final t = filter.trim();
    return t.isEmpty ? '' : ' WHERE $t';
  }

  String _orderClause(String orderBy) {
    final t = orderBy.trim();
    return t.isEmpty ? '' : ' ORDER BY $t';
  }

  String _projection(String selectList) {
    final t = selectList.trim();
    return t.isEmpty ? '*' : t;
  }

  @override
  Future<int> countRows(DbTable table, {String filter = ''}) async {
    final rs = _db.select(
      'SELECT count(*) FROM ${table.qualifiedName}${_whereClause(filter)}',
    );
    if (rs.rows.isEmpty) return 0;
    return (rs.rows.first.first as int?) ?? 0;
  }

  /// One page of rows. Regular tables are fetched with a leading `rowid`
  /// column so the grid can target rows for editing; that column is split
  /// out into [QueryResult.rowIds] and never shown as data. Views — and
  /// `WITHOUT ROWID` tables, detected by the `rowid` lookup failing — fall
  /// back to a plain, non-editable page.
  @override
  Future<QueryResult> fetchPage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    final tail =
        '${_whereClause(filter)}${_orderClause(orderBy)} '
        'LIMIT $limit OFFSET $offset';
    final projection = _projection(selectList);
    final watch = Stopwatch()..start();
    try {
      if (table.kind == DbRelationKind.table) {
        try {
          final rs = _db.select(
            'SELECT rowid AS __rowid, $projection '
            'FROM ${table.qualifiedName}$tail',
          );
          watch.stop();
          return _shapePage(rs, watch.elapsed, withRowId: true);
        } on SqliteException catch (e) {
          if (!_isMissingRowId(e)) rethrow;
          // WITHOUT ROWID table — retry without the identity column.
        }
      }
      final rs = _db.select(
        'SELECT $projection FROM ${table.qualifiedName}$tail',
      );
      watch.stop();
      return _shapePage(rs, watch.elapsed, withRowId: false);
    } on SqliteException catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.message, elapsed: watch.elapsed);
    } catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.toString(), elapsed: watch.elapsed);
    }
  }

  QueryResult _shapePage(
    ResultSet rs,
    Duration elapsed, {
    required bool withRowId,
  }) {
    if (!withRowId) {
      final columns = List<String>.from(rs.columnNames);
      return QueryResult.rows(
        columns: columns,
        rows: [for (final r in rs.rows) List<Object?>.from(r)],
        columnSchemas: [
          for (final n in columns) ResultColumnSchema(name: n),
        ],
        elapsed: elapsed,
      );
    }
    final columns = rs.columnNames.sublist(1);
    final rowIds = <String>[];
    final rows = <List<Object?>>[];
    for (final r in rs.rows) {
      rowIds.add('${r.first}');
      rows.add(List<Object?>.from(r.sublist(1)));
    }
    return QueryResult.rows(
      columns: columns,
      rows: rows,
      rowIds: rowIds,
      columnSchemas: [for (final n in columns) ResultColumnSchema(name: n)],
      elapsed: elapsed,
    );
  }

  @override
  Future<QueryResult> fetchAll(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    final watch = Stopwatch()..start();
    final rs = _db.select(
      'SELECT ${_projection(selectList)} FROM ${table.qualifiedName}'
      '${_whereClause(filter)}${_orderClause(orderBy)}',
    );
    watch.stop();
    return QueryResult.rows(
      columns: List<String>.from(rs.columnNames),
      rows: [for (final r in rs.rows) List<Object?>.from(r)],
      elapsed: watch.elapsed,
    );
  }

  /// SQLite stores the original `CREATE` text verbatim in `sqlite_master`,
  /// so the DDL view is that statement plus any standalone index DDL — no
  /// reconstruction needed.
  @override
  Future<String> loadDdl(DbTable table) async {
    final createRows = _db
        .select(
          "SELECT sql FROM sqlite_master "
          "WHERE type IN ('table', 'view') AND name = ?",
          params: [table.name],
        )
        .rows;
    final createSql = createRows.isEmpty
        ? null
        : createRows.first.first as String?;
    final indexRows = _db
        .select(
          "SELECT sql FROM sqlite_master "
          "WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL "
          'ORDER BY name',
          params: [table.name],
        )
        .rows;

    final buf = StringBuffer();
    buf.writeln(
      '-- ${table.kind == DbRelationKind.view ? 'View' : 'Table'}: '
      '${table.qualifiedName}',
    );
    buf.writeln();
    buf.writeln(createSql == null ? '-- definition unavailable' : '$createSql;');
    if (indexRows.isNotEmpty) {
      buf.writeln();
      buf.writeln('-- Indexes');
      for (final row in indexRows) {
        buf.writeln('${row.first as String};');
      }
    }
    return buf.toString();
  }

  /// Applies a batch of pending edits inside one transaction. Any UPDATE or
  /// DELETE that doesn't touch exactly one row rolls the whole batch back
  /// and raises [StaleRowException] — the rowid no longer resolves, so the
  /// caller should reload and retry.
  @override
  Future<int> applyEdits(DbTable table, EditBatch batch) async {
    if (batch.isEmpty) return 0;
    final statements = buildSqliteEditStatements(table, batch);
    final updateIds = batch.updatesByCtid.keys.toList(growable: false);
    final deleteIds = batch.deleteCtids;
    final mutationCount = updateIds.length + deleteIds.length;
    final conn = _db.conn;

    conn.execute('BEGIN');
    try {
      var affected = 0;
      for (var i = 0; i < statements.length; i++) {
        _db.run(statements[i]);
        final changed = _db.updatedRows;
        if (i < mutationCount && changed != 1) {
          final id = i < updateIds.length
              ? updateIds[i]
              : deleteIds[i - updateIds.length];
          throw StaleRowException(
            rowId: id,
            affectedRows: changed,
            table: table,
          );
        }
        affected += changed;
      }
      conn.execute('COMMIT');
      return affected;
    } on StaleRowException {
      conn.execute('ROLLBACK');
      rethrow;
    } on SqliteException catch (e) {
      conn.execute('ROLLBACK');
      throw EditFailureException(e.message);
    } catch (e) {
      conn.execute('ROLLBACK');
      throw EditFailureException(e.toString());
    }
  }

  static bool _isMissingRowId(SqliteException e) =>
      e.message.toLowerCase().contains('rowid');
}

/// Pure builder for the SQL SQLite would receive for a batch of pending
/// edits. Ordering is UPDATE → DELETE → INSERT, matching the Postgres
/// builder, so a row that's edited and duplicated in the same batch
/// propagates the edit before the duplicate is committed.
List<String> buildSqliteEditStatements(DbTable table, EditBatch batch) {
  return [
    for (final entry in batch.updatesByCtid.entries)
      _renderUpdate(table, entry.key, entry.value),
    for (final id in batch.deleteCtids) _renderDelete(table, id),
    for (final insert in batch.inserts) _renderInsert(table, insert),
  ];
}

String _renderUpdate(
  DbTable table,
  String rowId,
  Map<String, CellEditValue> assignments,
) {
  final lines = assignments.entries
      .map((e) => '  ${quoteIdent(e.key)} = ${_renderAssignment(e.value)}')
      .join(',\n');
  return 'UPDATE ${table.qualifiedName} SET\n$lines\nWHERE rowid = $rowId';
}

String _renderDelete(DbTable table, String rowId) =>
    'DELETE FROM ${table.qualifiedName}\nWHERE rowid = $rowId';

String _renderInsert(DbTable table, PendingInsert insert) {
  // SQLite has no per-column DEFAULT keyword in a VALUES list. Columns the
  // user left as DEFAULT are omitted entirely so the column default (or
  // INTEGER PRIMARY KEY auto-assignment) applies — this is what makes the
  // Duplicate-row gesture produce a fresh primary key.
  final cols = [
    for (final entry in insert.values.entries)
      if (entry.value is! CellDefault) entry.key,
  ];
  if (cols.isEmpty) {
    return 'INSERT INTO ${table.qualifiedName} DEFAULT VALUES';
  }
  final colList = cols.map(quoteIdent).join(', ');
  final valList = cols
      .map((c) => _renderAssignment(insert.values[c]!))
      .join(', ');
  return 'INSERT INTO ${table.qualifiedName} ($colList)\n'
      'VALUES ($valList)';
}

String _renderAssignment(CellEditValue value) => switch (value) {
  CellLiteral(:final value) => _literal(value),
  // Reachable only for UPDATE assignments; SQLite rejects `= DEFAULT` and
  // the apply path surfaces that as an EditFailureException.
  CellDefault() => 'DEFAULT',
};

/// Renders a value as a SQL literal. Single quotes are doubled to neutralise
/// injection; SQLite's type affinity coerces the text into the column type.
String _literal(String? value) {
  if (value == null) return 'NULL';
  return "'${value.replaceAll("'", "''")}'";
}
