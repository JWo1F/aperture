import 'package:flutter/material.dart';

import '../../models/db_catalog.dart';
import '../../models/db_object.dart';
import '../../ui/widgets/code_editor.dart';
import 'clause.dart';
import 'keywords.dart';
import 'scope.dart';
import 'suggestions.dart';
import 'text_scan.dart';

/// Completion for SELECT and the read-shaped clauses shared by UPDATE /
/// DELETE (FROM, JOIN, WHERE, GROUP/ORDER BY, …). Returns an unranked
/// candidate pool; the orchestrator scores it against the typed token.
///
/// [kind] tailors the keywords offered after a table / predicate so a
/// DELETE doesn't get `GROUP BY` and an UPDATE target gets `SET`.
List<CodeSuggestion> completeSelectPool({
  required SuggestRequest req,
  required DatabaseCatalog catalog,
  required String stmtText,
  required int localCursor,
  required SqlScope scope,
  required StatementKind kind,
}) {
  // Right after a JOIN keyword — bare table names plus the FK-aware join
  // templates (`orders ON orders.user_id = users.id`). The templates only
  // make sense here because they synthesise an `ON` clause; offering them
  // after `FROM` would insert a stray `ON` where one doesn't belong.
  final prev = previousWord(req.text, req.tokenStart);
  if (prev == 'join') {
    return [
      ..._joinSuggestions(currentTables: scope.tables, catalog: catalog),
      ...tableSuggestions(catalog),
    ];
  }

  // Right after FROM / UPDATE / INSERT INTO — bare table names, no join
  // templates (the user hasn't asked for a join here).
  const bareTableContexts = {'from', 'update', 'into'};
  if (bareTableContexts.contains(prev)) {
    return tableSuggestions(catalog);
  }

  final clause = detectClause(stmtText, localCursor);
  final pool = <CodeSuggestion>[];

  // Columns are only useful in clauses that *consume* expressions. In
  // FROM/JOIN/INSERT INTO/UPDATE continuations the user just landed on a
  // table name — the next token is a clause keyword, never a column.
  if (scope.tables.isNotEmpty && _clauseTakesColumns(clause)) {
    pool.addAll(columnsToSuggestions(scope.columnsFrom(catalog)));
    pool.addAll(aliasSuggestions(scope.aliases));
  }

  switch (clause) {
    case SqlClause.statementStart:
      pool.addAll(keywordsToSuggestions(statementKeywords));
    case SqlClause.selectList:
      final listHasContent = _selectListHasContent(stmtText, localCursor);
      if (!listHasContent) {
        // `*` is the overwhelmingly common first thing typed after SELECT
        // — pin it to the top with a matchBoost the ranker honours when
        // the token is empty. Skipped once anything's already in the list
        // so we don't dangle `*` after the user accepted it.
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
        // Once the list has content, the next useful token is `FROM` —
        // bump it to the top the same way we did for `*`.
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
        keywordsToSuggestions(
          listHasContent
              ? selectListKeywords.where((k) => k != 'FROM')
              : selectListKeywords,
        ),
      );
      if (scope.tables.isNotEmpty) {
        pool.addAll(keywordsToSuggestions(selectTailKeywords));
      }
    case SqlClause.from:
      // After `DELETE FROM t` only WHERE / USING / RETURNING are legal —
      // a plain SELECT's FROM continues into GROUP BY / JOIN / UNION / …
      pool.addAll(
        keywordsToSuggestions(
          kind == StatementKind.delete
              ? deleteTailKeywords
              : selectTailKeywords,
        ),
      );
    case SqlClause.updateTable:
      // `UPDATE <table>` is always followed by SET.
      pool.addAll(keywordsToSuggestions(const ['SET']));
    case SqlClause.join:
      pool.addAll(keywordsToSuggestions(joinTailKeywords));
    case SqlClause.insertInto:
      pool.addAll(tableSuggestions(catalog));
    case SqlClause.where:
    case SqlClause.having:
    case SqlClause.on:
      pool.addAll(keywordsToSuggestions(whereKeywords));
      // A WHERE in a DELETE / UPDATE ends the statement bar RETURNING;
      // only a SELECT's WHERE continues into GROUP BY / ORDER BY / JOIN.
      pool.addAll(
        keywordsToSuggestions(
          kind == StatementKind.delete || kind == StatementKind.update
              ? const ['RETURNING']
              : selectTailKeywords,
        ),
      );
    case SqlClause.orderBy:
    case SqlClause.groupBy:
      pool.addAll(keywordsToSuggestions(orderKeywords));
      pool.addAll(keywordsToSuggestions(['LIMIT', 'OFFSET', 'HAVING']));
    case SqlClause.limit:
      pool.addAll(keywordsToSuggestions(['OFFSET']));
    case SqlClause.set:
      // Columns of the UPDATE target are already in scope via parseScope;
      // once an assignment is written the statement continues into
      // WHERE / FROM / RETURNING.
      pool.addAll(keywordsToSuggestions(const ['WHERE', 'FROM', 'RETURNING']));
    case SqlClause.values_:
      pool.addAll(keywordsToSuggestions(['DEFAULT', 'NULL', 'RETURNING']));
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
      pool.addAll(keywordsToSuggestions(['AS', 'RECURSIVE']));
    case SqlClause.unknown:
      pool.addAll(keywordsToSuggestions(statementKeywords));
  }

  return pool;
}

/// True when [clause] is a slot where naming a column makes sense.
/// FROM / JOIN / INSERT INTO / UPDATE target are *table* slots — after the
/// table is in place the next useful token is a clause keyword.
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
bool _selectListHasContent(String stmtText, int cursor) {
  final clean = stripStringsAndComments(stmtText, cursor);
  final lower = clean.toLowerCase();
  final idx = lower.lastIndexOf('select');
  if (idx < 0) return false;
  for (var i = idx + 6; i < clean.length; i++) {
    final c = clean.codeUnitAt(i);
    if (isSpaceCode(c) || c == 0x2C /* , */ ) continue;
    return true;
  }
  return false;
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
        final ref =
            other.schema == 'public' ? other.name : other.qualifiedName;
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
