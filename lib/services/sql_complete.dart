import 'package:flutter/material.dart';

import '../models/db_catalog.dart';
import '../models/db_object.dart';
import '../ui/widgets/code_editor.dart';

/// SQL autocomplete engine. Pure functions only — the editor calls
/// [completeQueryEditor] / [completeClause] per keystroke and the result
/// flows straight into the popup. Everything stateful (debouncing,
/// suppression after accept, manual trigger) lives in the editor.
///
/// The engine handles:
///   * dot-qualified completion (`u.` after `FROM users u` returns only
///     that table's columns, with no keyword noise);
///   * clause-sensitive keyword sets (no `ORDER BY` in a `WHERE` slot);
///   * string- and comment-aware suppression (no popup inside `'...'`);
///   * relevance ranking with a hard cap — case-sensitive prefix wins,
///     then case-insensitive prefix, then substring; identifiers always
///     outrank keywords for the same score.

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

/// Resolved snapshot of `FROM …` / `JOIN …` references inside one statement.
class SqlScope {
  SqlScope({required this.tables, required this.aliases});

  final List<DbTable> tables;

  /// Alias (or bare table name when none is written) → resolved table.
  final Map<String, DbTable> aliases;

  Iterable<DbColumn> columnsFrom(DatabaseCatalog catalog) sync* {
    final seen = <String>{};
    for (final t in tables) {
      for (final c in catalog.columnsFor(t)) {
        if (seen.add(c.name)) yield c;
      }
    }
  }
}

// --- Keyword sets -------------------------------------------------------

const List<String> _statementKeywords = [
  'SELECT',
  'INSERT INTO',
  'UPDATE',
  'DELETE FROM',
  'WITH',
  'CREATE',
  'ALTER',
  'DROP',
  'TRUNCATE',
  'EXPLAIN',
];

const List<String> _selectListKeywords = [
  'DISTINCT',
  'ALL',
  'AS',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
  'COUNT(*)',
  'NULL',
  'TRUE',
  'FALSE',
  'FROM',
];

const List<String> _selectTailKeywords = [
  'WHERE',
  'GROUP BY',
  'ORDER BY',
  'HAVING',
  'LIMIT',
  'OFFSET',
  'JOIN',
  'INNER JOIN',
  'LEFT JOIN',
  'RIGHT JOIN',
  'FULL JOIN',
  'CROSS JOIN',
  'UNION',
  'INTERSECT',
  'EXCEPT',
];

const List<String> _whereKeywords = [
  'AND',
  'OR',
  'NOT',
  'IS',
  'IS NULL',
  'IS NOT NULL',
  'IN',
  'BETWEEN',
  'LIKE',
  'ILIKE',
  'EXISTS',
  'ANY',
  'ALL',
  'NULL',
  'TRUE',
  'FALSE',
  'CASE',
  'WHEN',
  'THEN',
  'ELSE',
  'END',
];

const List<String> _orderKeywords = [
  'ASC',
  'DESC',
  'NULLS FIRST',
  'NULLS LAST',
];

const List<String> _joinTailKeywords = ['ON', 'USING', 'AS'];

// Re-exported for the clause-bar in table_view (single-line inputs).
const List<String> selectModifierKeywords = ['DISTINCT', 'AS', 'COUNT(*)'];

const List<String> whereOperatorKeywords = _whereKeywords;

const List<String> orderModifierKeywords = _orderKeywords;

// --- Scope parsing ------------------------------------------------------

/// Identifier (bare or `"quoted"`) optionally schema-qualified, optionally
/// aliased. The negative lookahead in front of the alias slot keeps clause
/// and join keywords from being swallowed — without it, `FROM users JOIN
/// orders` would parse "JOIN" as the alias of `users`.
final _refRe = RegExp(
  r'\b(from|join|update|into)\s+'
  r'("[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*)'
  r'(?:\.("[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*))?'
  r'(?:\s+(?:as\s+)?'
  r'(?!(?:from|join|inner|left|right|full|cross|where|group|order|having|limit|offset|on|returning|union|intersect|except|using|set|values)\b)'
  r'("[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*))?',
  caseSensitive: false,
);

const _clauseStops = {
  'from', 'join', 'where', 'group', 'order', 'having', 'limit', 'offset',
  'on', 'returning', 'union', 'intersect', 'except', 'inner', 'left',
  'right', 'full', 'cross', 'using', 'set', 'values',
};

SqlScope parseScope(String stmtText, DatabaseCatalog catalog) {
  final tables = <DbTable>[];
  final aliases = <String, DbTable>{};

  for (final m in _refRe.allMatches(stmtText)) {
    final part1 = _unquote(m.group(2)!);
    final part2 = m.group(3) == null ? null : _unquote(m.group(3)!);
    final aliasCandidate = m.group(4) == null ? null : _unquote(m.group(4)!);
    final alias =
        aliasCandidate == null ||
            _clauseStops.contains(aliasCandidate.toLowerCase())
        ? null
        : aliasCandidate;

    final schema = part2 != null ? part1 : null;
    final tableName = part2 ?? part1;

    DbTable? table;
    if (schema != null) {
      table = catalog.relationByName(schema, tableName);
    } else {
      table = catalog.relationByName('public', tableName);
      if (table == null) {
        for (final r in catalog.relationsByOid.values) {
          if (r.name == tableName) {
            table = r;
            break;
          }
        }
      }
    }
    if (table == null) continue;

    tables.add(table);
    aliases[alias ?? table.name] = table;
  }

  return SqlScope(tables: tables, aliases: aliases);
}

String _unquote(String s) =>
    s.length >= 2 && s.startsWith('"') && s.endsWith('"')
    ? s.substring(1, s.length - 1)
    : s;

// --- Clause detection ---------------------------------------------------

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
  final upto = _stripStringsAndComments(
    stmtText,
    cursor.clamp(0, stmtText.length),
  );
  final words = <String>[];
  var i = 0;
  while (i < upto.length) {
    final c = upto.codeUnitAt(i);
    if (_isWordCode(c)) {
      final start = i;
      while (i < upto.length && _isWordCode(upto.codeUnitAt(i))) {
        i++;
      }
      words.add(upto.substring(start, i).toLowerCase());
    } else {
      i++;
    }
  }
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

/// Returns the lowercased word immediately preceding [tokenStart], skipping
/// any whitespace. Used by the editor for "right after a JOIN/FROM" tests.
String previousWord(String text, int tokenStart) {
  var i = tokenStart;
  while (i > 0 && _isSpaceCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  final end = i;
  while (i > 0 && _isWordCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  return text.substring(i, end).toLowerCase();
}

/// Returns the qualifier when [tokenStart] sits right after `<qualifier>.`,
/// e.g. given `… users u WHERE u.id|`, the qualifier of the token at the
/// caret is `u`. Returns null when no dot precedes the token.
String? qualifierBefore(String text, int tokenStart) {
  if (tokenStart == 0) return null;
  if (text.codeUnitAt(tokenStart - 1) != 0x2E /* . */ ) return null;
  var i = tokenStart - 1;
  while (i > 0 && _isWordCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  if (i == tokenStart - 1) return null;
  return text.substring(i, tokenStart - 1);
}

/// Walks `.identifier.identifier.…` backwards from [tokenStart],
/// returning the dot-separated chain as a list of bare names in the
/// order they appear in the source.
///
/// `public.users.id|`  → `['public', 'users']`
/// `u.|`               → `['u']`
/// `id|`               → `[]`
///
/// Quoted identifiers (`"Some.Name"`) are intentionally not handled —
/// our user types snake_case unquoted names; quoted-identifier support
/// would require a separate path that respects the quotes verbatim.
List<String> qualifierChainBefore(String text, int tokenStart) {
  if (tokenStart == 0) return const [];
  if (text.codeUnitAt(tokenStart - 1) != 0x2E /* . */ ) return const [];
  final parts = <String>[];
  var i = tokenStart - 1;
  while (i > 0 && text.codeUnitAt(i) == 0x2E) {
    var j = i;
    while (j > 0 && _isWordCode(text.codeUnitAt(j - 1))) {
      j--;
    }
    if (j == i) break;
    parts.insert(0, text.substring(j, i));
    if (j == 0 || text.codeUnitAt(j - 1) != 0x2E) break;
    i = j - 1;
  }
  return parts;
}

/// True when the caret sits inside a single-quoted literal, a `--` line
/// comment, or a `/* … */` block comment. The editor uses this to
/// suppress the popup so we don't pop suggestions while typing string
/// content. Scans the *full* text — string scope is decided by whether
/// the cursor lies inside an open-close pair, so we have to look past
/// the cursor for the closing delimiter.
bool isInsideStringOrComment(String text, int cursor) {
  final upto = cursor.clamp(0, text.length);
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);

    if (c == 0x27 /* ' */ ) {
      final openedBeforeCursor = i < upto;
      i++;
      var closed = false;
      while (i < text.length) {
        final cc = text.codeUnitAt(i);
        if (cc == 0x27) {
          if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x27) {
            i += 2;
            continue;
          }
          i++;
          closed = true;
          break;
        }
        i++;
      }
      // Cursor falls inside the literal when the opener is before it
      // *and* the closer (if any) is at or after it.
      if (openedBeforeCursor && (!closed || i > upto)) return true;
      continue;
    }

    if (c == 0x2D /* - */ &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == 0x2D) {
      final openedBeforeCursor = i < upto;
      while (i < text.length && text.codeUnitAt(i) != 0x0A) {
        i++;
      }
      // Cursor is in the comment when the `--` opens before it and the
      // newline (which we stop on) lands at or after it.
      if (openedBeforeCursor && i >= upto) return true;
      continue;
    }

    if (c == 0x2F /* / */ &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == 0x2A) {
      final openedBeforeCursor = i < upto;
      i += 2;
      var closed = false;
      while (i + 1 < text.length) {
        if (text.codeUnitAt(i) == 0x2A && text.codeUnitAt(i + 1) == 0x2F) {
          i += 2;
          closed = true;
          break;
        }
        i++;
      }
      if (!closed) i = text.length;
      if (openedBeforeCursor && (!closed || i > upto)) return true;
      continue;
    }

    i++;
  }
  return false;
}

/// Returns [text] truncated at [upto] with every string-literal and
/// comment region replaced by spaces. Used by [detectClause] so a stray
/// `WHERE` inside a string doesn't fool the clause scanner.
String _stripStringsAndComments(String text, int upto) {
  final buf = StringBuffer();
  var i = 0;
  while (i < upto) {
    final c = text.codeUnitAt(i);
    if (c == 0x27) {
      buf.write(' ');
      i++;
      while (i < upto) {
        final cc = text.codeUnitAt(i);
        if (cc == 0x27) {
          if (i + 1 < upto && text.codeUnitAt(i + 1) == 0x27) {
            buf.write('  ');
            i += 2;
            continue;
          }
          buf.write(' ');
          i++;
          break;
        }
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (c == 0x2D && i + 1 < upto && text.codeUnitAt(i + 1) == 0x2D) {
      while (i < upto && text.codeUnitAt(i) != 0x0A) {
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (c == 0x2F && i + 1 < upto && text.codeUnitAt(i + 1) == 0x2A) {
      buf.write('  ');
      i += 2;
      while (i + 1 < upto) {
        if (text.codeUnitAt(i) == 0x2A && text.codeUnitAt(i + 1) == 0x2F) {
          buf.write('  ');
          i += 2;
          break;
        }
        buf.write(' ');
        i++;
      }
      continue;
    }
    buf.writeCharCode(c);
    i++;
  }
  return buf.toString();
}

// --- Public entry points ------------------------------------------------

/// Suggestions for the table-view clause-bar inputs (single-line). The
/// engine ranks columns ahead of keywords and caps the result list.
List<CodeSuggestion> completeClause({
  required SuggestRequest req,
  required Iterable<DbColumn> columns,
  required List<String> extraKeywords,
}) {
  final pool = <CodeSuggestion>[
    ..._columnsToSuggestions(columns),
    ..._keywordsToSuggestions(extraKeywords),
  ];
  return _rankAndLimit(pool, req.token, manualTrigger: req.manualTrigger);
}

/// Suggestions for the multi-line SQL editor. Resolves clause context,
/// scope (FROM/JOIN), and dot-qualified references; returns at most 30
/// entries ranked by relevance to [req.token].
List<CodeSuggestion> completeQueryEditor({
  required SuggestRequest req,
  required DatabaseCatalog catalog,
  required String stmtText,
}) {
  if (isInsideStringOrComment(req.text, req.cursor)) return const [];

  // The editor passes `manualTrigger=true` only for Ctrl-Space. We
  // additionally synthesise it whenever the cursor sits in a slot where
  // completion is *naturally* expected (right after `JOIN `, `WHERE `,
  // `,`, `(`, etc.) so typing one space after `JOIN` pops the table
  // list without making the user reach for Ctrl-Space.
  final softTrigger = req.manualTrigger ||
      (req.token.isEmpty &&
          _isSoftTriggerPosition(req.text, req.tokenStart));

  final scope = parseScope(stmtText, catalog);
  final chain = qualifierChainBefore(req.text, req.tokenStart);

  if (chain.isNotEmpty) {
    final pool = _qualifierCompletions(chain, scope, catalog);
    // The user has already typed the disambiguating `.` — treat the
    // empty-token case the same as a manual trigger so `a.|` /
    // `public.|` pop the list immediately instead of waiting for a
    // first letter.
    return _rankAndLimit(pool, req.token, manualTrigger: true);
  }

  // Right after a JOIN keyword — bare table names plus the FK-aware
  // join templates (`orders ON orders.user_id = users.id`). The
  // templates only make sense here because they synthesise an `ON`
  // clause; offering them after `FROM` would insert a stray `ON` into
  // a place that doesn't take one.
  final prev = previousWord(req.text, req.tokenStart);
  if (prev == 'join') {
    final pool = <CodeSuggestion>[
      ..._joinSuggestions(
        currentTables: scope.tables,
        catalog: catalog,
      ),
      ..._tableSuggestions(catalog),
    ];
    return _rankAndLimit(pool, req.token, manualTrigger: softTrigger);
  }

  // Right after FROM / UPDATE / INSERT INTO — bare table names, no
  // join templates (the user hasn't asked for a join here).
  const bareTableContexts = {'from', 'update', 'into'};
  if (bareTableContexts.contains(prev)) {
    return _rankAndLimit(
      _tableSuggestions(catalog),
      req.token,
      manualTrigger: softTrigger,
    );
  }

  final clause = detectClause(stmtText, req.cursor);
  final pool = <CodeSuggestion>[];

  // Columns are only useful in clauses that *consume* expressions. In
  // FROM/JOIN/INSERT INTO/UPDATE continuations the user just landed on
  // a table name — the next token is a clause keyword (WHERE, GROUP BY,
  // ORDER BY, JOIN, …), never a column.
  if (scope.tables.isNotEmpty && _clauseTakesColumns(clause)) {
    pool.addAll(_columnsToSuggestions(scope.columnsFrom(catalog)));
    pool.addAll(_aliasSuggestions(scope.aliases));
  }

  switch (clause) {
    case SqlClause.statementStart:
      pool.addAll(_keywordsToSuggestions(_statementKeywords));
    case SqlClause.selectList:
      final listHasContent = _selectListHasContent(stmtText, req.cursor);
      if (!listHasContent) {
        // `*` is the overwhelmingly common first thing typed after
        // SELECT — pin it to the top with a matchBoost the ranker
        // honours when the token is empty (the soft-trigger case
        // after `SELECT `). Skipped once anything's already in the
        // list so we don't dangle `*` at the top after the user
        // already accepted it.
        pool.add(
          const CodeSuggestion(
            label: '*',
            insertText: '*',
            detail: 'all columns',
            kind: SuggestionKind.snippet,
            matchBoost: 1000,
            chainNext: true,
          ),
        );
      } else {
        // Once the user has *something* in the select list, the next
        // useful token is `FROM` — bump it to the top of the keyword
        // pool the same way we did for `*` on the empty list.
        pool.add(
          const CodeSuggestion(
            label: 'FROM',
            insertText: 'FROM',
            detail: 'keyword',
            kind: SuggestionKind.keyword,
            matchBoost: 1000,
            chainNext: true,
          ),
        );
      }
      pool.addAll(
        _keywordsToSuggestions(
          listHasContent
              ? _selectListKeywords.where((k) => k != 'FROM')
              : _selectListKeywords,
        ),
      );
      if (scope.tables.isNotEmpty) {
        pool.addAll(_keywordsToSuggestions(_selectTailKeywords));
      }
    case SqlClause.from:
    case SqlClause.updateTable:
      // The table name itself is already on the page; from here the
      // useful next tokens are the clause that follows (`WHERE`, …) or
      // a JOIN variant. New tables get suggested by the early-return
      // path above when the cursor sits right after `FROM` / `JOIN`.
      pool.addAll(_keywordsToSuggestions(_selectTailKeywords));
    case SqlClause.join:
      // After `JOIN <table>` the next thing is the join condition.
      pool.addAll(_keywordsToSuggestions(_joinTailKeywords));
    case SqlClause.insertInto:
      pool.addAll(_tableSuggestions(catalog));
    case SqlClause.where:
    case SqlClause.having:
    case SqlClause.on:
      pool.addAll(_keywordsToSuggestions(_whereKeywords));
      pool.addAll(_keywordsToSuggestions(_selectTailKeywords));
    case SqlClause.orderBy:
    case SqlClause.groupBy:
      pool.addAll(_keywordsToSuggestions(_orderKeywords));
      pool.addAll(_keywordsToSuggestions(['LIMIT', 'OFFSET', 'HAVING']));
    case SqlClause.limit:
      pool.addAll(_keywordsToSuggestions(['OFFSET']));
    case SqlClause.set:
      // Columns of the UPDATE target are already in scope via parseScope.
    case SqlClause.values_:
      pool.addAll(_keywordsToSuggestions(['DEFAULT', 'NULL', 'RETURNING']));
    case SqlClause.returning:
      pool.add(
        const CodeSuggestion(
          label: '*',
          insertText: '*',
          detail: 'all columns',
          kind: SuggestionKind.keyword,
        ),
      );
    case SqlClause.with_:
      pool.addAll(_keywordsToSuggestions(['AS', 'RECURSIVE']));
    case SqlClause.unknown:
      pool.addAll(_keywordsToSuggestions(_statementKeywords));
  }

  return _rankAndLimit(pool, req.token, manualTrigger: softTrigger);
}

// --- Conversion helpers -------------------------------------------------

List<CodeSuggestion> _keywordsToSuggestions(Iterable<String> kws) => [
  for (final kw in kws)
    CodeSuggestion(
      label: kw,
      insertText: kw,
      detail: 'keyword',
      kind: SuggestionKind.keyword,
      chainNext: true,
    ),
];

List<CodeSuggestion> _columnsToSuggestions(Iterable<DbColumn> cols) => [
  for (final c in cols)
    CodeSuggestion(
      label: c.name,
      insertText: c.name,
      detail: c.dataType,
      icon: c.isPrimaryKey ? Icons.key : null,
      kind: SuggestionKind.column,
      matchBoost: c.isPrimaryKey ? 2 : 0,
    ),
];

List<CodeSuggestion> _tableSuggestions(DatabaseCatalog catalog) => [
  for (final t in catalog.relationsByOid.values)
    CodeSuggestion(
      label: t.name,
      insertText: t.schema == 'public' ? t.name : t.qualifiedName,
      detail: t.schema,
      icon: Icons.table_chart_outlined,
      kind: SuggestionKind.table,
      chainNext: true,
    ),
];

List<CodeSuggestion> _aliasSuggestions(Map<String, DbTable> aliases) => [
  for (final entry in aliases.entries)
    if (entry.key != entry.value.name)
      CodeSuggestion(
        label: entry.key,
        insertText: entry.key,
        detail: '→ ${entry.value.name}',
        icon: Icons.alternate_email,
        kind: SuggestionKind.alias,
      ),
];

/// Resolves a single-part qualifier (`u`, `users`, `public`) to either a
/// table (alias or bare name) or null. The schema-as-qualifier case is
/// handled in [_qualifierCompletions] because it returns tables, not a
/// single table.
DbTable? _resolveTableQualifier(
  String qualifier,
  SqlScope scope,
  DatabaseCatalog catalog,
) {
  final byAlias = scope.aliases[qualifier];
  if (byAlias != null) return byAlias;
  final lower = qualifier.toLowerCase();
  for (final entry in scope.aliases.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  final byName = catalog.relationByName('public', qualifier);
  if (byName != null) return byName;
  for (final r in catalog.relationsByOid.values) {
    if (r.name == qualifier) return r;
  }
  return null;
}

/// Dispatches dot-completion based on the length of the qualifier chain:
///
/// * `[schema, table]`  → columns of `schema.table`
/// * `[alias|table]`    → columns of that relation
/// * `[schema]`         → tables in that schema
///
/// Falls back to the in-scope column list when the chain doesn't
/// resolve, so the popup still offers something useful when the user
/// has typed a partial schema name we haven't fully introspected yet.
List<CodeSuggestion> _qualifierCompletions(
  List<String> chain,
  SqlScope scope,
  DatabaseCatalog catalog,
) {
  if (chain.length >= 2) {
    final schema = chain[chain.length - 2];
    final tableName = chain.last;
    final table = catalog.relationByName(schema, tableName);
    if (table != null) {
      return _columnsToSuggestions(catalog.columnsFor(table));
    }
    return const [];
  }

  final qualifier = chain.single;
  final table = _resolveTableQualifier(qualifier, scope, catalog);
  if (table != null) {
    return _columnsToSuggestions(catalog.columnsFor(table));
  }

  final inSchema = _tableSuggestionsInSchema(catalog, qualifier);
  if (inSchema.isNotEmpty) return inSchema;

  return _columnsToSuggestions(scope.columnsFrom(catalog));
}

/// Bare table names from one schema, inserted without the schema prefix
/// (the user already typed `schema.`). Returns [] when the schema isn't
/// in the catalog.
List<CodeSuggestion> _tableSuggestionsInSchema(
  DatabaseCatalog catalog,
  String schema,
) {
  final lower = schema.toLowerCase();
  final out = <CodeSuggestion>[];
  for (final t in catalog.relationsByOid.values) {
    if (t.schema.toLowerCase() != lower) continue;
    out.add(
      CodeSuggestion(
        label: t.name,
        insertText: t.name,
        detail: t.schema,
        icon: Icons.table_chart_outlined,
        kind: SuggestionKind.table,
        chainNext: true,
      ),
    );
  }
  return out;
}

// --- Join templates (FK-aware) -----------------------------------------

List<CodeSuggestion> _joinSuggestions({
  required Iterable<DbTable> currentTables,
  required DatabaseCatalog catalog,
}) {
  final out = <CodeSuggestion>[];
  final seen = <String>{};

  for (final src in currentTables) {
    for (final fk
        in catalog.foreignKeysByOid[src.oid] ?? const <DbForeignKey>[]) {
      if (!fk.isSingleColumn) continue;
      final ref = fk.refSchema == 'public' ? fk.refTable : fk.refQualified;
      final insert =
          '$ref ON ${fk.refTable}.${fk.refColumn} = ${src.name}.${fk.localColumn}';
      if (!seen.add(insert)) continue;
      out.add(
        CodeSuggestion(
          label: fk.refTable,
          insertText: insert,
          detail: '→ ${src.name}.${fk.localColumn}',
          icon: Icons.link,
          kind: SuggestionKind.snippet,
          matchBoost: 8,
        ),
      );
    }
    for (final entry in catalog.foreignKeysByOid.entries) {
      final other = catalog.relation(entry.key);
      if (other == null) continue;
      if (other.oid == src.oid) continue;
      for (final fk in entry.value) {
        if (!fk.isSingleColumn) continue;
        if (fk.refTableOid != src.oid) continue;
        final ref = other.schema == 'public' ? other.name : other.qualifiedName;
        final insert =
            '$ref ON ${other.name}.${fk.localColumn} = ${src.name}.${fk.refColumn}';
        if (!seen.add(insert)) continue;
        out.add(
          CodeSuggestion(
            label: other.name,
            insertText: insert,
            detail: '← ${other.name}.${fk.localColumn}',
            icon: Icons.link,
            kind: SuggestionKind.snippet,
            matchBoost: 8,
          ),
        );
      }
    }
  }

  return out;
}

// --- Ranking ------------------------------------------------------------

/// Cap on the number of items shown — past this the popup is just noise
/// and the scroll wheel hides the matches you actually want.
const int _suggestLimit = 30;

/// Scores [pool] against [token] and returns the top [_suggestLimit] hits
/// in descending order. When [manualTrigger] is true an empty token shows
/// the full pool (capped) so Ctrl-Space gives a "what's available" view.
List<CodeSuggestion> _rankAndLimit(
  List<CodeSuggestion> pool,
  String token, {
  required bool manualTrigger,
}) {
  if (pool.isEmpty) return const [];

  if (token.isEmpty) {
    if (!manualTrigger) return const [];
    final sorted = [...pool]
      ..sort((a, b) {
        // matchBoost first so callers can pin a "this is what you almost
        // certainly want" entry (e.g. `*` right after `SELECT`) to the
        // top regardless of kind weight.
        final boost = b.matchBoost - a.matchBoost;
        if (boost != 0) return boost;
        final k = _kindWeight(b.kind) - _kindWeight(a.kind);
        if (k != 0) return k;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return sorted.take(_suggestLimit).toList();
  }

  final scored = <_Scored>[];
  for (final s in pool) {
    final score = _score(s, token);
    if (score == null) continue;
    scored.add(_Scored(s, score));
  }
  scored.sort((a, b) {
    final s = b.score - a.score;
    if (s != 0) return s;
    return a.suggestion.label.length - b.suggestion.label.length;
  });

  // Deduplicate by (label,insertText) — FK join templates and bare table
  // names can collide on the same `label`.
  final seen = <String>{};
  final out = <CodeSuggestion>[];
  for (final s in scored) {
    final key = '${s.suggestion.label}${s.suggestion.insertText}';
    if (!seen.add(key)) continue;
    out.add(s.suggestion);
    if (out.length >= _suggestLimit) break;
  }
  return out;
}

class _Scored {
  _Scored(this.suggestion, this.score);
  final CodeSuggestion suggestion;
  final int score;
}

int _kindWeight(SuggestionKind k) {
  switch (k) {
    case SuggestionKind.alias:
      return 60;
    case SuggestionKind.column:
      return 55;
    case SuggestionKind.snippet:
      return 50;
    case SuggestionKind.table:
      return 40;
    case SuggestionKind.keyword:
      return 20;
  }
}

/// Returns null when [s] doesn't match [token] at all. Otherwise:
///   +1000  case-sensitive prefix
///   +600   case-insensitive prefix
///   +300   word-boundary prefix inside a multi-word label
///   +120   case-insensitive substring (anywhere)
///   +200   exact match (case-insensitive), on top of any prefix bonus
///   + kind weight
///   + suggestion.matchBoost
///   – label length (shorter wins on ties)
int? _score(CodeSuggestion s, String token) {
  final label = s.label;
  final lLabel = label.toLowerCase();
  final lToken = token.toLowerCase();

  int? base;
  if (label.startsWith(token)) {
    base = 1000;
  } else if (lLabel.startsWith(lToken)) {
    base = 600;
  } else {
    final wb = _wordBoundaryIndex(lLabel, lToken);
    if (wb > 0) {
      base = 300;
    } else if (lLabel.contains(lToken)) {
      base = 120;
    }
  }
  if (base == null) return null;

  if (lLabel == lToken) base += 200;

  return base + _kindWeight(s.kind) + s.matchBoost - label.length;
}

int _wordBoundaryIndex(String label, String token) {
  for (var i = 1; i < label.length; i++) {
    final c = label.codeUnitAt(i - 1);
    if (c == 0x20 || c == 0x5F /* _ */ ) {
      if (label.startsWith(token, i)) return i;
    }
  }
  return -1;
}

/// True when [clause] is a slot where naming a column makes sense.
/// FROM / JOIN / INSERT INTO / UPDATE target are *table* slots — after
/// the table is in place the next useful token is a clause keyword, not
/// a column name.
bool _clauseTakesColumns(SqlClause clause) {
  switch (clause) {
    case SqlClause.selectList:
    case SqlClause.where:
    case SqlClause.having:
    case SqlClause.on:
    case SqlClause.orderBy:
    case SqlClause.groupBy:
    case SqlClause.set:
    case SqlClause.returning:
    case SqlClause.values_:
      return true;
    case SqlClause.statementStart:
    case SqlClause.from:
    case SqlClause.join:
    case SqlClause.insertInto:
    case SqlClause.updateTable:
    case SqlClause.limit:
    case SqlClause.with_:
    case SqlClause.unknown:
      return false;
  }
}

/// True when there's any non-whitespace, non-comma content between the
/// last `SELECT` keyword and [cursor] (ignoring strings and comments).
/// Used to decide whether `*` is still a sensible empty-token suggestion
/// or whether the user has moved past it and wants `FROM` next.
bool _selectListHasContent(String stmtText, int cursor) {
  // `cursor` arrives in *full-editor* coordinates while `stmtText` is
  // the (often shorter) substring of the active statement — clamp
  // before indexing so a cursor sitting past the statement's end
  // doesn't blow up `_stripStringsAndComments`.
  final at = cursor.clamp(0, stmtText.length);
  final clean = _stripStringsAndComments(stmtText, at);
  final lower = clean.toLowerCase();
  final idx = lower.lastIndexOf('select');
  if (idx < 0) return false;
  for (var i = idx + 6; i < clean.length; i++) {
    final c = clean.codeUnitAt(i);
    if (_isSpaceCode(c) || c == 0x2C /* , */ ) continue;
    return true;
  }
  return false;
}

// --- Soft auto-trigger --------------------------------------------------

/// Keywords that "want" a completion popup to appear when the user hits
/// space after them, with no identifier prefix typed yet. Mirrors the
/// SQL grammar's natural pause points — after these, the next token is
/// almost always an identifier (table, column) or a small set of
/// continuation keywords, both of which the engine can helpfully list.
const Set<String> _autoTriggerWords = {
  // Statement openers
  'select', 'insert', 'update', 'delete', 'with',
  // Source / target
  'from', 'into', 'join', 'inner', 'left', 'right', 'full', 'cross',
  'on', 'using',
  // Predicates
  'where', 'and', 'or', 'not', 'is', 'in', 'like', 'ilike',
  'between', 'exists', 'having',
  // Lists / ordering
  'group', 'order', 'by', 'distinct', 'as',
  // Page
  'limit', 'offset',
  // DML tails
  'set', 'values', 'returning',
};

bool _isSoftTriggerPosition(String text, int tokenStart) {
  var i = tokenStart;
  while (i > 0 && _isSpaceCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  // Must have *some* whitespace between the cursor and the prior token —
  // otherwise the cursor sits right on top of that token and the user
  // hasn't yet committed it with a space.
  if (i == tokenStart) return false;
  if (i == 0) return false;
  final c = text.codeUnitAt(i - 1);
  if (c == 0x2C /* , */ || c == 0x28 /* ( */ ) return true;
  final wordEnd = i;
  while (i > 0 && _isWordCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  if (i == wordEnd) return false;
  return _autoTriggerWords.contains(
    text.substring(i, wordEnd).toLowerCase(),
  );
}

// --- Character classifiers ---------------------------------------------

bool _isSpaceCode(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _isWordCode(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F;
