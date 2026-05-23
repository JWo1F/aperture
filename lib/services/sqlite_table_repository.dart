import 'package:sqlite3/sqlite3.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'sql_identifier.dart';
import 'sql_render.dart';
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

  String _projection(String selectList) {
    final t = selectList.trim();
    return t.isEmpty ? '*' : t;
  }

  @override
  Future<int> countRows(DbTable table, {String filter = ''}) async {
    validateClauseSnippet(filter, kind: ClauseKind.filter);
    final rs = _db.select(
      'SELECT count(*) FROM ${table.qualifiedName}${whereClause(filter)}',
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
    validateClauseSnippet(filter, kind: ClauseKind.filter);
    validateClauseSnippet(orderBy, kind: ClauseKind.orderBy);
    validateClauseSnippet(selectList, kind: ClauseKind.selectList);
    final tail =
        '${whereClause(filter)}${orderClause(orderBy)} '
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
    validateClauseSnippet(filter, kind: ClauseKind.filter);
    validateClauseSnippet(orderBy, kind: ClauseKind.orderBy);
    validateClauseSnippet(selectList, kind: ClauseKind.selectList);
    final watch = Stopwatch()..start();
    final rs = _db.select(
      'SELECT ${_projection(selectList)} FROM ${table.qualifiedName}'
      '${whereClause(filter)}${orderClause(orderBy)}',
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
    buf.writeln(
      createSql == null
          ? '-- definition unavailable'
          : '${_prettyCreateTable(createSql)};',
    );
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
    // An UPDATE whose only assignments are `CellDefault` collapses to a
    // no-op (see `_renderUpdate`); drop those rowids from the tracking
    // lists so the statement-to-rowid index used for stale-row detection
    // stays aligned with the emitted SQL.
    final effectiveUpdates = {
      for (final e in batch.updatesByCtid.entries)
        if (e.value.values.any((v) => v is! CellDefault)) e.key: e.value,
    };
    final effectiveBatch = identical(effectiveUpdates, batch.updatesByCtid)
        ? batch
        : EditBatch(
            updatesByCtid: effectiveUpdates,
            deleteCtids: batch.deleteCtids,
            inserts: batch.inserts,
          );
    if (effectiveBatch.isEmpty) return 0;
    final statements = buildSqliteEditStatements(table, effectiveBatch);
    final updateIds = effectiveUpdates.keys.toList(growable: false);
    final deleteIds = effectiveBatch.deleteCtids;
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
      _safeRollback(conn);
      rethrow;
    } on SqliteException catch (e) {
      _safeRollback(conn);
      throw EditFailureException(e.message);
    } catch (e) {
      _safeRollback(conn);
      throw EditFailureException(e.toString());
    }
  }

  /// Rolls back the open transaction without ever letting a rollback
  /// failure replace the original exception, and without leaving the
  /// connection stuck inside a half-open transaction.
  ///
  /// SQLite's `ROLLBACK` can itself fail (disconnect, disk error). If we
  /// let that propagate it would mask the real cause and — worse — every
  /// subsequent `applyEdits` would die with `cannot start a transaction
  /// within a transaction`, breaking the edit subsystem until reconnect.
  /// We swallow the rollback error, then re-check `autocommit` and try
  /// one more best-effort `ROLLBACK` if the connection is still inside a
  /// transaction.
  static void _safeRollback(Database conn) {
    try {
      conn.execute('ROLLBACK');
    } catch (_) {
      // Original exception wins; rollback failures are swallowed.
    }
    if (!conn.autocommit) {
      try {
        conn.execute('ROLLBACK');
      } catch (_) {}
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
      ?_renderUpdate(table, entry.key, entry.value),
    for (final id in batch.deleteCtids) _renderDelete(table, id),
    for (final insert in batch.inserts) _renderInsert(table, insert),
  ];
}

/// SQLite rejects `SET col = DEFAULT`, so `CellDefault` assignments are
/// dropped from the SET list — the column simply keeps its current value,
/// which matches the user's intent of "revert this edit". If every
/// assignment is `CellDefault` the UPDATE collapses to a no-op and we
/// skip emitting it entirely.
String? _renderUpdate(
  DbTable table,
  String rowId,
  Map<String, CellEditValue> assignments,
) {
  final lines = assignments.entries
      .where((e) => e.value is! CellDefault)
      .map((e) => '  ${quoteIdent(e.key)} = ${renderAssignment(e.value)}')
      .join(',\n');
  if (lines.isEmpty) return null;
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
      .map((c) => renderAssignment(insert.values[c]!))
      .join(', ');
  return 'INSERT INTO ${table.qualifiedName} ($colList)\n'
      'VALUES ($valList)';
}

/// Reflows a verbatim `CREATE TABLE` statement onto one column/constraint per
/// line. SQLite stores `CREATE` text exactly as written, and dumpers (Rails,
/// etc.) emit the whole body on a single line. The parenthesised body is split
/// on top-level commas — commas inside nested parens or quoted strings and
/// identifiers (`'…'`, `"…"`, `` `…` ``, `[…]`) are left alone — and runs of
/// whitespace outside quotes are collapsed. Non-table statements (views) and
/// anything that fails to parse are returned untouched.
String _prettyCreateTable(String sql) {
  if (!RegExp(r'^\s*CREATE\s+TABLE', caseSensitive: false).hasMatch(sql)) {
    return sql;
  }
  final open = sql.indexOf('(');
  if (open < 0) return sql;

  final parts = <String>[];
  final current = StringBuffer();
  var pendingSpace = false;
  var depth = 0;
  var close = -1;
  String? quote;

  void emit(String ch) {
    if (pendingSpace && current.isNotEmpty) current.write(' ');
    pendingSpace = false;
    current.write(ch);
  }

  for (var i = open + 1; i < sql.length; i++) {
    final ch = sql[i];
    if (quote != null) {
      current.write(ch);
      if (ch == quote) {
        if (quote != ']' && i + 1 < sql.length && sql[i + 1] == quote) {
          current.write(sql[++i]);
        } else {
          quote = null;
        }
      }
      continue;
    }
    if (ch == "'" || ch == '"' || ch == '`' || ch == '[') {
      quote = ch == '[' ? ']' : ch;
      emit(ch);
    } else if (ch == '(') {
      depth++;
      emit(ch);
    } else if (ch == ')' && depth == 0) {
      close = i;
      break;
    } else if (ch == ')') {
      depth--;
      emit(ch);
    } else if (ch == ',' && depth == 0) {
      parts.add(current.toString().trim());
      current.clear();
      pendingSpace = false;
    } else if (ch.trim().isEmpty) {
      pendingSpace = true;
    } else {
      emit(ch);
    }
  }
  if (close < 0) return sql;
  parts.add(current.toString().trim());

  final header = sql.substring(0, open).replaceAll(RegExp(r'\s+'), ' ').trim();
  final body = parts.where((p) => p.isNotEmpty).map((p) => '  $p').join(',\n');
  final trailer = sql.substring(close + 1).trim();
  final out = '$header (\n$body\n)';
  return trailer.isEmpty ? out : '$out $trailer';
}
