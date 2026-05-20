import 'package:flutter/material.dart';

import '../models/db_catalog.dart';
import '../models/db_object.dart';
import '../ui/widgets/code_editor.dart';

/// Pure functions that produce [CodeSuggestion] lists for the editor. The
/// editor calls a thin closure per keystroke; everything heavy (catalog
/// inspection, regex parsing) lives here so the UI stays declarative.

/// SQL keywords offered everywhere — capitalised for visual contrast with
/// (typically lowercase) identifiers. The set is intentionally small; rare
/// keywords would only add noise to the prefix-match popup.
const List<String> sqlKeywords = [
  'SELECT', 'FROM', 'WHERE', 'GROUP BY', 'ORDER BY', 'HAVING',
  'LIMIT', 'OFFSET', 'JOIN', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN',
  'FULL JOIN', 'CROSS JOIN', 'ON', 'AS', 'AND', 'OR', 'NOT', 'NULL',
  'TRUE', 'FALSE', 'IS', 'IS NULL', 'IS NOT NULL', 'IN', 'BETWEEN',
  'LIKE', 'ILIKE', 'EXISTS', 'ANY', 'ALL', 'CASE', 'WHEN', 'THEN',
  'ELSE', 'END', 'ASC', 'DESC', 'NULLS FIRST', 'NULLS LAST',
  'INSERT INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE FROM', 'RETURNING',
  'WITH', 'DISTINCT', 'UNION', 'INTERSECT', 'EXCEPT',
];

const List<String> whereOperatorKeywords = [
  'AND', 'OR', 'NOT', 'IS NULL', 'IS NOT NULL', 'IN', 'BETWEEN',
  'LIKE', 'ILIKE', 'NULL', 'TRUE', 'FALSE',
];

const List<String> selectModifierKeywords = ['DISTINCT', 'AS', 'COUNT(*)'];

const List<String> orderModifierKeywords = [
  'ASC', 'DESC', 'NULLS FIRST', 'NULLS LAST',
];

/// Resolved snapshot of `FROM …` / `JOIN …` references inside one statement.
class SqlScope {
  SqlScope({required this.tables, required this.aliases});

  final List<DbTable> tables;
  /// Alias → table. Tables without an alias resolve under their bare name
  /// (so `users.id` works even when no `AS users` is written).
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

/// Identifier (bare or `"quoted"`) optionally schema-qualified, optionally
/// aliased. The negative lookahead in front of the alias slot keeps clause
/// and join keywords from being swallowed — without it, `FROM users JOIN
/// orders` would parse "JOIN" as the alias of `users` and the second table
/// would never match.
final _refRe = RegExp(
  r'\b(from|join|update|into)\s+'
  r'("[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*)'
  r'(?:\.("[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*))?'
  r'(?:\s+(?:as\s+)?'
  r'(?!(?:from|join|inner|left|right|full|cross|where|group|order|having|limit|offset|on|returning|union|intersect|except)\b)'
  r'("[^"]+"|[a-zA-Z_][a-zA-Z0-9_]*))?',
  caseSensitive: false,
);

const _clauseStops = {
  'from', 'join', 'where', 'group', 'order', 'having', 'limit', 'offset',
  'on', 'returning', 'union', 'intersect', 'except', 'inner', 'left',
  'right', 'full', 'cross',
};

SqlScope parseScope(String stmtText, DatabaseCatalog catalog) {
  final tables = <DbTable>[];
  final aliases = <String, DbTable>{};

  for (final m in _refRe.allMatches(stmtText)) {
    final part1 = _unquote(m.group(2)!);
    final part2 = m.group(3) == null ? null : _unquote(m.group(3)!);
    final aliasCandidate =
        m.group(4) == null ? null : _unquote(m.group(4)!);
    final alias = aliasCandidate == null ||
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

bool _matches(String name, String token) {
  if (token.isEmpty) return true;
  return name.toLowerCase().startsWith(token.toLowerCase());
}

List<CodeSuggestion> _keywordSuggestions(
  Iterable<String> keywords,
  String token,
) {
  return [
    for (final kw in keywords)
      if (_matches(kw, token))
        CodeSuggestion(label: kw, insertText: kw, detail: 'keyword'),
  ];
}

List<CodeSuggestion> _columnSuggestions(
  Iterable<DbColumn> columns,
  String token,
) {
  return [
    for (final c in columns)
      if (_matches(c.name, token))
        CodeSuggestion(
          label: c.name,
          insertText: c.name,
          detail: c.dataType,
          icon: c.isPrimaryKey ? Icons.key : null,
        ),
  ];
}

/// Token immediately before [cursor]'s leading whitespace — used to detect
/// "we are right after a JOIN keyword, suggest tables" / "right after a
/// FROM keyword, prefer table names". Returns the lowercased word, or `''`.
String previousWord(String text, int tokenStart) {
  var i = tokenStart;
  while (i > 0 && _isSpace(text.codeUnitAt(i - 1))) {
    i--;
  }
  final end = i;
  while (i > 0 && _isWord(text.codeUnitAt(i - 1))) {
    i--;
  }
  return text.substring(i, end).toLowerCase();
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _isWord(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F;

// --- Public entry points ------------------------------------------------

/// Suggestions for the table-view clause-bar inputs (single-line). [columns]
/// are the columns of the bound relation; [extraKeywords] are clause-specific
/// operator words layered on top.
List<CodeSuggestion> completeClause({
  required SuggestRequest req,
  required Iterable<DbColumn> columns,
  required List<String> extraKeywords,
}) {
  final out = <CodeSuggestion>[];
  out.addAll(_columnSuggestions(columns, req.token));
  out.addAll(_keywordSuggestions(extraKeywords, req.token));
  return out;
}

/// Suggestions for the multi-line SQL editor. Combines:
///   - the SQL keyword set (always)
///   - columns from every table in the current statement's FROM / JOIN scope
///   - JOIN target templates (FK-aware) when the cursor sits right after a
///     JOIN keyword
List<CodeSuggestion> completeQueryEditor({
  required SuggestRequest req,
  required DatabaseCatalog catalog,
  required String stmtText,
}) {
  final out = <CodeSuggestion>[];
  final prev = previousWord(req.text, req.tokenStart);

  final scope = parseScope(stmtText, catalog);

  // Right after JOIN / FROM / UPDATE / INTO — suggest tables.
  const tableContexts = {'join', 'from', 'update', 'into'};
  if (tableContexts.contains(prev)) {
    out.addAll(_joinSuggestions(
      currentTables: scope.tables,
      catalog: catalog,
      token: req.token,
    ));
    out.addAll(_tableNameSuggestions(catalog, req.token));
    out.addAll(_keywordSuggestions(sqlKeywords, req.token));
    return out;
  }

  // In general scope: columns of the in-scope tables + keywords.
  if (scope.tables.isNotEmpty) {
    out.addAll(_columnSuggestions(scope.columnsFrom(catalog), req.token));
  }
  out.addAll(_keywordSuggestions(sqlKeywords, req.token));
  return out;
}

List<CodeSuggestion> _tableNameSuggestions(
  DatabaseCatalog catalog,
  String token,
) {
  return [
    for (final t in catalog.relationsByOid.values)
      if (_matches(t.name, token))
        CodeSuggestion(
          label: t.name,
          insertText: t.schema == 'public' ? t.name : t.qualifiedName,
          detail: t.schema,
          icon: Icons.table_chart_outlined,
        ),
  ];
}

List<CodeSuggestion> _joinSuggestions({
  required Iterable<DbTable> currentTables,
  required DatabaseCatalog catalog,
  required String token,
}) {
  final out = <CodeSuggestion>[];
  final seen = <String>{};

  for (final src in currentTables) {
    // Outbound FKs: src.col → other.col
    for (final fk in catalog.foreignKeysByOid[src.oid] ?? const <DbForeignKey>[]) {
      if (!fk.isSingleColumn) continue;
      if (!_matches(fk.refTable, token)) continue;
      final ref = fk.refSchema == 'public' ? fk.refTable : fk.refQualified;
      final insert =
          '$ref ON ${fk.refTable}.${fk.refColumn} = ${src.name}.${fk.localColumn}';
      if (!seen.add(insert)) continue;
      out.add(CodeSuggestion(
        label: fk.refTable,
        insertText: insert,
        detail: '→ ${src.name}.${fk.localColumn}',
        icon: Icons.link,
      ));
    }
    // Inbound FKs: other.col → src.col
    for (final entry in catalog.foreignKeysByOid.entries) {
      final other = catalog.relation(entry.key);
      if (other == null) continue;
      if (other.oid == src.oid) continue;
      for (final fk in entry.value) {
        if (!fk.isSingleColumn) continue;
        if (fk.refTableOid != src.oid) continue;
        if (!_matches(other.name, token)) continue;
        final ref =
            other.schema == 'public' ? other.name : other.qualifiedName;
        final insert =
            '$ref ON ${other.name}.${fk.localColumn} = ${src.name}.${fk.refColumn}';
        if (!seen.add(insert)) continue;
        out.add(CodeSuggestion(
          label: other.name,
          insertText: insert,
          detail: '← ${other.name}.${fk.localColumn}',
          icon: Icons.link,
        ));
      }
    }
  }

  return out;
}
