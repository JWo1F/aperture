import 'dart:convert';

import '../models/cell_edit.dart';
import '../models/db_object.dart';
import '../models/query_result.dart';
import 'mysql_service.dart';
import 'sql_identifier.dart';
import 'sql_render.dart';
import 'table_repository.dart';

const _sql = SqlDialect.mysql;

/// MySQL per-relation operations: paging, exporting, DDL, cell editing.
///
/// MySQL has no `ctid` or `rowid`, so a row is addressed by its primary-key
/// values. A page of a table with a primary key carries those values in
/// [QueryResult.rowIds], encoded by [_identityToken]; views and tables
/// without a primary key get a null `rowIds` and the grid treats the page
/// as read-only.
class MysqlTableRepository implements TableRepository {
  MysqlTableRepository(this._db);

  final MysqlService _db;

  @override
  Future<int> countRows(DbTable table, {String filter = ''}) async {
    validateClauseSnippet(filter, kind: ClauseKind.filter, dialect: _sql);
    final result = await _db.execute(
      'SELECT COUNT(*) FROM ${table.qualifiedName}${whereClause(filter)}',
    );
    final count = result.rows.first.first;
    return count is int ? count : 0;
  }

  /// One page of rows. For a table with an addressable primary key the
  /// key columns are fetched in front of the data under `__pk<n>` aliases,
  /// split out into [QueryResult.rowIds], and never shown as data.
  ///
  /// The relation is aliased to its own name, so `*` can be qualified (MySQL
  /// rejects a bare `*` after another select item) while a clausebar filter
  /// written as `orders.status = 'x'` still resolves.
  @override
  Future<QueryResult> fetchPage(
    DbTable table, {
    required int limit,
    required int offset,
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    validateClauseSnippet(filter, kind: ClauseKind.filter, dialect: _sql);
    validateClauseSnippet(orderBy, kind: ClauseKind.orderBy, dialect: _sql);
    validateClauseSnippet(
      selectList,
      kind: ClauseKind.selectList,
      dialect: _sql,
    );
    final watch = Stopwatch()..start();
    try {
      final key = table.kind == DbRelationKind.table
          ? await _addressableKey(table)
          : const <String>[];
      final alias = _sql.quoteIdent(table.name);
      final trimmed = selectList.trim();
      final projection = trimmed.isEmpty || trimmed == '*'
          ? (key.isEmpty ? '*' : '$alias.*')
          : trimmed;
      final keyPrefix = [
        for (var i = 0; i < key.length; i++)
          '$alias.${_sql.quoteIdent(key[i])} AS `__pk$i`, ',
      ].join();
      final from = key.isEmpty
          ? 'FROM ${table.qualifiedName}'
          : 'FROM ${table.qualifiedName} AS $alias';
      final result = await _db.execute(
        'SELECT $keyPrefix$projection $from'
        '${whereClause(filter)}${orderClause(orderBy)} '
        'LIMIT $limit OFFSET $offset',
      );
      watch.stop();

      final columns = result.columns.sublist(key.length);
      final rows = <List<Object?>>[];
      final rowIds = key.isEmpty ? null : <String>[];
      for (final row in result.rows) {
        if (rowIds != null) {
          rowIds.add(_identityToken(key, row.sublist(0, key.length)));
        }
        rows.add(row.sublist(key.length));
      }
      return QueryResult.rows(
        columns: columns,
        rows: rows,
        rowIds: rowIds,
        columnSchemas: [for (final n in columns) ResultColumnSchema(name: n)],
        elapsed: watch.elapsed,
      );
    } catch (e) {
      watch.stop();
      return QueryResult.failure(
        error: MysqlService.errorMessage(e),
        elapsed: watch.elapsed,
      );
    }
  }

  /// The primary-key columns of [table], in key order, or an empty list
  /// when it has none or the key can't address a row.
  ///
  /// A key holding a binary-typed column can't: `mysql_dart` decodes
  /// `BINARY` / `VARBINARY` text-protocol values as UTF-8, so a
  /// `BINARY(16)` UUID arrives altered and would match no row on the way
  /// back.
  Future<List<String>> _addressableKey(DbTable table) async {
    final result = await _db.execute(
      'SELECT s.COLUMN_NAME, c.DATA_TYPE '
      'FROM information_schema.STATISTICS s '
      'JOIN information_schema.COLUMNS c '
      '  ON c.TABLE_SCHEMA = s.TABLE_SCHEMA '
      '  AND c.TABLE_NAME = s.TABLE_NAME '
      '  AND c.COLUMN_NAME = s.COLUMN_NAME '
      'WHERE s.TABLE_SCHEMA = ${_sql.literal(table.schema)} '
      '  AND s.TABLE_NAME = ${_sql.literal(table.name)} '
      "  AND s.INDEX_NAME = 'PRIMARY' "
      'ORDER BY s.SEQ_IN_INDEX',
      log: false,
    );
    final columns = <String>[];
    for (final row in result.rows) {
      final type = (row[1] as String).toLowerCase();
      if (_binaryTypes.contains(type)) return const [];
      columns.add(row[0] as String);
    }
    return columns;
  }

  static const _binaryTypes = {
    'binary',
    'varbinary',
    'tinyblob',
    'blob',
    'mediumblob',
    'longblob',
    'bit',
    'geometry',
  };

  @override
  Future<QueryResult> fetchAll(
    DbTable table, {
    String filter = '',
    String orderBy = '',
    String selectList = '*',
  }) async {
    validateClauseSnippet(filter, kind: ClauseKind.filter, dialect: _sql);
    validateClauseSnippet(orderBy, kind: ClauseKind.orderBy, dialect: _sql);
    validateClauseSnippet(
      selectList,
      kind: ClauseKind.selectList,
      dialect: _sql,
    );
    final trimmed = selectList.trim();
    final projection = trimmed.isEmpty ? '*' : trimmed;
    final watch = Stopwatch()..start();
    final result = await _db.execute(
      'SELECT $projection FROM ${table.qualifiedName}'
      '${whereClause(filter)}${orderClause(orderBy)}',
    );
    watch.stop();
    return QueryResult.rows(
      columns: result.columns,
      rows: result.rows,
      elapsed: watch.elapsed,
    );
  }

  /// `SHOW CREATE TABLE` answers for views as well, and both put the
  /// statement in the second column.
  @override
  Future<String> loadDdl(DbTable table) async {
    final result = await _db.execute(
      'SHOW CREATE TABLE ${table.qualifiedName}',
      log: false,
    );
    final kind = table.isView ? 'View' : 'Table';
    final create = result.rows.isEmpty ? null : result.rows.first[1];
    return '-- $kind: ${table.qualifiedName}\n\n'
        '${create == null ? '-- definition unavailable' : '$create;'}\n';
  }

  /// Applies a batch of pending edits inside one transaction. An UPDATE or
  /// DELETE that doesn't address exactly one row rolls the whole batch back
  /// as a [StaleRowException] — the row's key no longer matches.
  ///
  /// MySQL reports an UPDATE's *changed* rows, not its matched ones, and
  /// `mysql_dart` offers no `CLIENT_FOUND_ROWS`. An UPDATE that writes the
  /// value a row already holds reports 0, so a 0 is checked against the key
  /// before it counts as stale.
  @override
  Future<EditResult> applyEdits(DbTable table, EditBatch batch) async {
    if (batch.isEmpty) return const EditResult.success(0);
    final statements = buildMysqlEditStatements(table, batch);
    final updateIds = batch.updatesByCtid.keys.toList(growable: false);
    final deleteIds = batch.deleteCtids;
    try {
      await _db.runTx((tx) async {
        for (var i = 0; i < statements.length; i++) {
          final affected = (await tx.execute(statements[i])).affectedRows;
          if (i < updateIds.length) {
            if (affected == 1) continue;
            final id = updateIds[i];
            if (affected == 0 && await _rowExists(tx, table, id)) continue;
            throw StaleRowException(
              rowId: id,
              affectedRows: affected,
              table: table,
            );
          }
          if (i < updateIds.length + deleteIds.length && affected != 1) {
            throw StaleRowException(
              rowId: deleteIds[i - updateIds.length],
              affectedRows: affected,
              table: table,
            );
          }
        }
      });
      return EditResult.success(statements.length);
    } catch (e) {
      return EditResult.failure(
        appliedCount: 0,
        totalCount: statements.length,
        error: e is StaleRowException
            ? e.toString()
            : MysqlService.errorMessage(e),
      );
    }
  }

  Future<bool> _rowExists(MysqlTx tx, DbTable table, String rowId) async {
    final result = await tx.execute(
      'SELECT 1 FROM ${table.qualifiedName} ${_keyPredicate(rowId)} LIMIT 2',
    );
    return result.rows.length == 1;
  }
}

/// Pure builder for the SQL MySQL would receive for a batch of pending
/// edits. MySQL accepts `DEFAULT` in both an UPDATE's SET list and an
/// INSERT's VALUES, so nothing is filtered — an `AUTO_INCREMENT` key set to
/// `DEFAULT` draws the next value, which is what gives Duplicate-row a
/// fresh key.
List<String> buildMysqlEditStatements(DbTable table, EditBatch batch) =>
    buildEditStatements(table, batch, _mysqlPolicy);

const EditPolicy _mysqlPolicy = EditPolicy(
  rowIdPredicate: _keyPredicate,
  insertOmitsDefaultColumns: false,
  updateDropsDefaultAssignments: false,
);

/// The row identity of a page row: its primary-key column names and their
/// values as the server printed them, so a token is self-describing and
/// [_keyPredicate] needs no catalog lookup.
String _identityToken(List<String> key, List<Object?> values) => jsonEncode([
  for (var i = 0; i < key.length; i++) [key[i], values[i]?.toString()],
]);

/// `WHERE \`a\` = '1' AND \`b\` = 'x'` for an [_identityToken]. Values are
/// compared as string literals, which MySQL converts to the column's type —
/// for an integer key the index is still used.
String _keyPredicate(String rowId) {
  final pairs = (jsonDecode(rowId) as List).cast<List<dynamic>>();
  final terms = [
    for (final p in pairs)
      '${_sql.quoteIdent(p[0] as String)} = ${_sql.literal(p[1] as String?)}',
  ];
  return 'WHERE ${terms.join(' AND ')}';
}
