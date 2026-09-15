import 'package:sqlite3/sqlite3.dart';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'sql_render.dart';
import 'sqlite_service.dart';
import 'table_repository.dart';

/// SQLite per-relation operations: paging, exporting, DDL, cell editing.
///
/// Row identity is the implicit integer rowid, addressed as `_rowid_` so a
/// user column named `rowid` can't shadow it. Views and `WITHOUT ROWID`
/// tables have none; for those, [fetchPage] returns a null `rowIds` and the
/// grid treats the page as read-only.
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
            'SELECT _rowid_ AS __rowid, $projection '
            'FROM ${table.qualifiedName}$tail',
          );
          watch.stop();
          final page = _shapePage(rs, watch.elapsed, withRowId: true);
          if (page != null) return page;
          // The identity column came back as something other than an
          // integer — fall through to the read-only shape.
        } on SqliteException catch (e) {
          if (!_isMissingRowId(e)) rethrow;
          // WITHOUT ROWID table — retry without the identity column.
        }
      }
      final rs = _db.select(
        'SELECT $projection FROM ${table.qualifiedName}$tail',
      );
      watch.stop();
      return _shapePage(rs, watch.elapsed, withRowId: false)!;
    } on SqliteException catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.message, elapsed: watch.elapsed);
    } catch (e) {
      watch.stop();
      return QueryResult.failure(error: e.toString(), elapsed: watch.elapsed);
    }
  }

  /// Shapes [rs] into a page. Returns null when [withRowId] was requested
  /// but the leading identity column isn't an integer.
  ///
  /// Identity is read as `_rowid_`, not `rowid`. A table may legally
  /// declare a column called `rowid` (`CREATE TABLE t(rowid TEXT)`), and
  /// `SELECT rowid` then returns that column's user data; `_rowid_` is the
  /// same pseudo-column under a name almost nothing shadows, and the edit
  /// predicate uses it too so both halves agree.
  ///
  /// The type check is the backstop for a table that shadows `_rowid_` as
  /// well. The edit builder inlines the identity token into the statement
  /// rather than binding it, so a non-integer here is arbitrary user text
  /// heading for the SQL body. Such a relation has no identity we can
  /// address: the caller re-shapes it as a read-only page.
  QueryResult? _shapePage(
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
      final id = r.first;
      if (id is! int) return null;
      rowIds.add('$id');
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
  /// and is reported as a [StaleRowException]-shaped failure on the
  /// returned [EditResult] — the rowid no longer resolves, so the caller
  /// should reload and retry.
  ///
  /// `appliedCount` is best-effort progress: the number of statements that
  /// `_db.run` returned before the throw. In the common case `_safeRollback`
  /// reverts those rows, so the on-disk count is 0. The progress count
  /// matters when ROLLBACK itself fails (disk error, disconnect) — see
  /// [EditResult.partial] — at which point the UI must tell the user to
  /// refresh before retrying.
  @override
  Future<EditResult> applyEdits(DbTable table, EditBatch batch) async {
    if (batch.isEmpty) return const EditResult.success(0);
    // An UPDATE whose only assignments are `CellDefault` collapses to a
    // no-op (see `_renderUpdate`); drop those rowids from the tracking
    // lists so the statement-to-rowid index used for stale-row detection
    // stays aligned with the emitted SQL.
    final effectiveUpdates = {
      for (final e in batch.updatesByCtid.entries)
        if (e.value.values.any((v) => v is! CellDefault)) e.key: e.value,
    };
    final effectiveBatch = EditBatch(
      updatesByCtid: effectiveUpdates,
      deleteCtids: batch.deleteCtids,
      inserts: batch.inserts,
    );
    if (effectiveBatch.isEmpty) return const EditResult.success(0);
    final statements = buildSqliteEditStatements(table, effectiveBatch);
    final totalCount = statements.length;
    final updateIds = effectiveUpdates.keys.toList(growable: false);
    final deleteIds = effectiveBatch.deleteCtids;
    final mutationCount = updateIds.length + deleteIds.length;
    final conn = _db.conn;

    conn.execute('BEGIN');
    var applied = 0;
    try {
      for (var i = 0; i < statements.length; i++) {
        _db.run(statements[i]);
        applied = i + 1;
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
      }
      conn.execute('COMMIT');
      return EditResult.success(totalCount);
    } on StaleRowException catch (e) {
      return _rolledBack(conn, applied, totalCount, e.toString());
    } on SqliteException catch (e) {
      return _rolledBack(conn, applied, totalCount, e.message);
    } catch (e) {
      return _rolledBack(conn, applied, totalCount, e.toString());
    }
  }

  /// Rolls back and reports what the rollback achieved.
  ///
  /// `appliedCount` is only meaningful when the rollback did NOT recover:
  /// a successful ROLLBACK means nothing was committed, whatever the loop
  /// managed before it threw. Reporting the loop's progress regardless made
  /// every mid-batch stale row look like a partial apply, and
  /// `TabsController` reacts to `partial` by reloading the page — which
  /// drops the row-indexed pending edits, so a recoverable conflict threw
  /// away the user's other, still-valid edits and told them 3 of 5
  /// statements had landed.
  static EditResult _rolledBack(
    Database conn,
    int applied,
    int totalCount,
    String error,
  ) {
    final recovered = _safeRollback(conn);
    return EditResult.failure(
      appliedCount: recovered ? 0 : applied,
      totalCount: totalCount,
      error: recovered
          ? error
          : '$error\n\nThe rollback did not complete — refresh to see what '
                'the database actually holds before retrying.',
    );
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
  ///
  /// Returns true when the connection ended up outside a transaction, i.e.
  /// nothing from the batch remains committed.
  static bool _safeRollback(Database conn) {
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
    return conn.autocommit;
  }

  static bool _isMissingRowId(SqliteException e) =>
      e.message.toLowerCase().contains('rowid');
}

/// Pure builder for the SQL SQLite would receive for a batch of pending
/// edits. Thin wrapper around [buildEditStatements] with the SQLite-
/// specific row-identity + DEFAULT policy.
List<String> buildSqliteEditStatements(DbTable table, EditBatch batch) =>
    buildEditStatements(table, batch, _sqlitePolicy);

final EditPolicy _sqlitePolicy = EditPolicy(
  rowIdPredicate: (rowId) => 'WHERE _rowid_ = $rowId',
  insertOmitsDefaultColumns: true,
  updateDropsDefaultAssignments: true,
);

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
