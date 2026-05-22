import 'text_scan.dart';

/// Where the cursor sits in a (best-effort) SQL parse. Determines which
/// keyword set is offered and whether identifiers are wanted at all.
enum SqlClause {
  /// Before any clause keyword — fresh statement, expect SELECT / INSERT / …
  statementStart,
  selectList,
  from,
  join,
  on,
  where,
  groupBy,
  having,
  orderBy,
  limit,
  insertInto,
  values_,
  updateTable,
  set,
  returning,
  with_,
  unknown,
}

/// The kind of statement under the cursor — chooses which completer the
/// orchestrator dispatches to.
enum StatementKind { select, insert, update, delete, ddl, withCte, other }

/// Pairs of two-word clause keywords we want to recognise as a unit so
/// `ORDER BY` doesn't get scanned as the bare `BY`.
const _twoWordClauses = {
  'order by': SqlClause.orderBy,
  'group by': SqlClause.groupBy,
  'insert into': SqlClause.insertInto,
  'delete from': SqlClause.from,
  'inner join': SqlClause.join,
  'left join': SqlClause.join,
  'right join': SqlClause.join,
  'full join': SqlClause.join,
  'cross join': SqlClause.join,
};

const _oneWordClauses = {
  'select': SqlClause.selectList,
  'from': SqlClause.from,
  'join': SqlClause.join,
  'on': SqlClause.on,
  'using': SqlClause.on,
  'where': SqlClause.where,
  'having': SqlClause.having,
  'limit': SqlClause.limit,
  'offset': SqlClause.limit,
  'update': SqlClause.updateTable,
  'set': SqlClause.set,
  'returning': SqlClause.returning,
  'values': SqlClause.values_,
  'with': SqlClause.with_,
};

/// Walks backwards from [cursor] inside [stmtText] (ignoring strings and
/// comments) and returns the clause that owns the cursor position.
SqlClause detectClause(String stmtText, int cursor) {
  final words = [
    for (final w in scanWords(stmtText, cursor.clamp(0, stmtText.length)))
      w.toLowerCase(),
  ];
  if (words.isEmpty) return SqlClause.statementStart;

  for (var j = words.length - 1; j >= 0; j--) {
    if (j > 0) {
      final pair = '${words[j - 1]} ${words[j]}';
      final two = _twoWordClauses[pair];
      if (two != null) return two;
    }
    final one = _oneWordClauses[words[j]];
    if (one != null) return one;
  }
  return SqlClause.statementStart;
}

const _explainLeaders = {'explain', 'analyze', 'verbose'};

/// Classifies a statement by its leading keyword (a leading `EXPLAIN
/// [ANALYZE] [VERBOSE]` is skipped so `EXPLAIN SELECT …` is still a select).
StatementKind statementKindOf(String stmtText) {
  final words = scanWords(stmtText, stmtText.length);
  var i = 0;
  while (i < words.length && _explainLeaders.contains(words[i].toLowerCase())) {
    i++;
  }
  if (i >= words.length) return StatementKind.other;
  switch (words[i].toLowerCase()) {
    case 'select':
      return StatementKind.select;
    case 'insert':
      return StatementKind.insert;
    case 'update':
      return StatementKind.update;
    case 'delete':
      return StatementKind.delete;
    case 'with':
      return StatementKind.withCte;
    case 'create':
    case 'alter':
    case 'drop':
    case 'truncate':
      return StatementKind.ddl;
    default:
      return StatementKind.other;
  }
}
