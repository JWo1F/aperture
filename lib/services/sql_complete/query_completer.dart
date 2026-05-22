import '../../models/db_catalog.dart';
import '../../models/db_object.dart';
import '../../ui/widgets/code_editor.dart';
import 'clause.dart';
import 'ddl_completer.dart';
import 'insert_completer.dart';
import 'scope.dart';
import 'select_completer.dart';
import 'suggestions.dart';
import 'text_scan.dart';

/// Orchestrates SQL autocomplete: suppresses inside strings/comments,
/// translates the caret into statement-relative coordinates, handles
/// dot-qualified completion, then dispatches to the statement completer.

/// Suggestions for the table-view clause-bar inputs (single-line). The
/// engine ranks columns ahead of keywords and caps the result list.
List<CodeSuggestion> completeClause({
  required SuggestRequest req,
  required Iterable<DbColumn> columns,
  required List<String> extraKeywords,
}) {
  final pool = <CodeSuggestion>[
    ...columnsToSuggestions(columns),
    ...keywordsToSuggestions(extraKeywords),
  ];
  return rankAndLimit(pool, req.token, manualTrigger: req.manualTrigger);
}

/// Suggestions for the multi-line SQL editor. [stmtText] is the text of the
/// statement under the caret and [stmtStart] its offset into the full
/// editor — together they let the engine reason in statement-relative
/// coordinates so a sibling statement's clauses don't leak in.
List<CodeSuggestion> completeQueryEditor({
  required SuggestRequest req,
  required DatabaseCatalog catalog,
  required String stmtText,
  int stmtStart = 0,
}) {
  if (isInsideStringOrComment(req.text, req.cursor)) return const [];

  final localCursor = (req.cursor - stmtStart).clamp(0, stmtText.length);

  // The editor passes `manualTrigger=true` only for Ctrl-Space. We
  // additionally synthesise it whenever the caret sits in a slot where
  // completion is naturally expected (right after `JOIN `, `WHERE `, `,`,
  // `(`, …) so typing one space pops the list without Ctrl-Space.
  final softTrigger = req.manualTrigger ||
      (req.token.isEmpty && _isSoftTriggerPosition(req.text, req.tokenStart));

  final scope = parseScope(stmtText, catalog);

  // Dot-qualified completion works the same for every statement kind.
  final chain = qualifierChainBefore(req.text, req.tokenStart);
  if (chain.isNotEmpty) {
    // The user has already typed the disambiguating `.` — treat an empty
    // token like a manual trigger so `a.|` / `public.|` pop immediately.
    return rankAndLimit(
      qualifierCompletions(chain, scope, catalog),
      req.token,
      manualTrigger: true,
    );
  }

  // INSERT and DDL each get a statement-aware matcher. A non-null pool is
  // shown eagerly — the matchers only emit suggestions at slots that
  // genuinely want them, and return an empty pool for free-identifier
  // slots. A null result means the caret sits in a SELECT sub-body
  // (`INSERT … SELECT`, `CREATE … AS SELECT`) — fall through.
  switch (statementKindOf(stmtText)) {
    case StatementKind.insert:
      final ins = completeInsertPool(
        req: req,
        catalog: catalog,
        stmtText: stmtText,
        localCursor: localCursor,
      );
      if (ins != null) {
        return rankAndLimit(ins, req.token, manualTrigger: true);
      }
    case StatementKind.ddl:
      final ddl = completeDdlPool(
        req: req,
        catalog: catalog,
        stmtText: stmtText,
        localCursor: localCursor,
      );
      if (ddl != null) {
        return rankAndLimit(ddl, req.token, manualTrigger: true);
      }
    case StatementKind.select:
    case StatementKind.update:
    case StatementKind.delete:
    case StatementKind.withCte:
    case StatementKind.other:
      break;
  }

  final pool = completeSelectPool(
    req: req,
    catalog: catalog,
    stmtText: stmtText,
    localCursor: localCursor,
    scope: scope,
  );
  return rankAndLimit(pool, req.token, manualTrigger: softTrigger);
}

// --- Soft auto-trigger --------------------------------------------------

/// Keywords that "want" a completion popup when the user hits space after
/// them, with no identifier prefix typed yet. Mirrors the SQL grammar's
/// natural pause points — after these, the next token is almost always an
/// identifier or a small set of continuation keywords.
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
  while (i > 0 && isSpaceCode(text.codeUnitAt(i - 1))) {
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
  while (i > 0 && isWordCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  if (i == wordEnd) return false;
  return _autoTriggerWords.contains(text.substring(i, wordEnd).toLowerCase());
}
