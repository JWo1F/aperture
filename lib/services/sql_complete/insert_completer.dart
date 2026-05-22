import '../../models/db_catalog.dart';
import '../../models/db_object.dart';
import '../../ui/widgets/code_editor.dart';
import 'scope.dart';
import 'suggestions.dart';
import 'text_scan.dart';

/// Completion for INSERT statements.
///
/// Returns an unranked candidate pool, or `null` to delegate to the SELECT
/// completer once an `INSERT INTO t … SELECT …` sub-query has begun.
///
/// Walks the keyword skeleton like the DDL matcher: tokenizes the
/// statement-so-far, drops the partial token, and decides the slot from
/// the trailing words plus the paren depth.
List<CodeSuggestion>? completeInsertPool({
  required SuggestRequest req,
  required DatabaseCatalog catalog,
  required String stmtText,
  required int localCursor,
}) {
  final token = req.token;
  final clean = stripStringsAndComments(stmtText, localCursor);
  final ctx = clean.substring(
    0,
    (clean.length - token.length).clamp(0, clean.length),
  );
  final words = [for (final w in wordsIn(ctx)) w.toLowerCase()];
  if (words.isEmpty) return null; // still typing `INSERT`

  final prev = words.last;
  if (words.length == 1 || prev == 'insert') {
    return keywordsToSuggestions(['INTO']);
  }

  // The `… SELECT …` source query — the read-path completer owns it.
  if (words.contains('select')) return null;

  final target = _matchInto(ctx, catalog);
  if (target == null) {
    // The target relation hasn't been fully typed yet.
    return prev == 'into' ? tableSuggestions(catalog) : const [];
  }

  final cols = columnsToSuggestions(catalog.columnsFor(target));
  final depth = parenDepth(ctx);

  if (words.contains('returning')) {
    return [_star, ...cols];
  }
  if (_hasSeq(words, ['on', 'conflict'])) {
    return _onConflict(words, depth, cols);
  }
  if (_hasSeq(words, ['default', 'values'])) {
    return keywordsToSuggestions(['RETURNING', 'ON CONFLICT']);
  }
  if (words.contains('values')) {
    if (depth >= 1) {
      return keywordsToSuggestions(['DEFAULT', 'NULL', 'true', 'false']);
    }
    // Between `VALUES` and a tuple, or just after a `,` separating tuples,
    // the user is about to type `(…)` — nothing to offer.
    if (prev == 'values' || lastNonSpaceCode(ctx) == 0x2C) return const [];
    return keywordsToSuggestions(['RETURNING', 'ON CONFLICT']);
  }

  // No VALUES / SELECT yet.
  if (depth >= 1) return cols; // inside the `(col, col, …)` list
  if (lastNonSpaceCode(ctx) == 0x29 /* ) */ ) {
    return keywordsToSuggestions(['VALUES', 'SELECT', 'OVERRIDING SYSTEM VALUE']);
  }
  // Right after the table name.
  return keywordsToSuggestions(['VALUES', 'SELECT', 'DEFAULT VALUES']);
}

List<CodeSuggestion> _onConflict(
  List<String> words,
  int depth,
  List<CodeSuggestion> cols,
) {
  final prev = words.last;
  if (_hasSeq(words, ['do', 'update', 'set'])) return cols;
  if (prev == 'do') return keywordsToSuggestions(['NOTHING', 'UPDATE SET']);
  if (prev == 'conflict') {
    return keywordsToSuggestions(['DO NOTHING', 'DO UPDATE SET', 'ON CONSTRAINT']);
  }
  if (prev == 'constraint') return const []; // typing the constraint name
  if (depth >= 1) return cols; // the `ON CONFLICT (col, …)` target list
  if (_hasSeq(words, ['do', 'nothing'])) {
    return keywordsToSuggestions(['RETURNING']);
  }
  return keywordsToSuggestions(['DO NOTHING', 'DO UPDATE SET', 'WHERE']);
}

const _star = CodeSuggestion(
  label: '*',
  insertText: '*',
  detail: 'all columns',
  kind: SuggestionKind.keyword,
);

final _insertIntoRe = RegExp(
  r'\binsert\s+into\s+("[^"]+"|[a-zA-Z_]\w*)'
  r'(?:\s*\.\s*("[^"]+"|[a-zA-Z_]\w*))?',
  caseSensitive: false,
);

DbTable? _matchInto(String ctx, DatabaseCatalog catalog) {
  final m = _insertIntoRe.firstMatch(ctx);
  if (m == null) return null;
  final n1 = unquoteIdentifier(m.group(1)!);
  final g2 = m.group(2);
  return g2 != null
      ? lookupRelation(catalog, n1, unquoteIdentifier(g2))
      : lookupRelation(catalog, null, n1);
}

/// True when [seq] appears as consecutive elements anywhere in [words].
bool _hasSeq(List<String> words, List<String> seq) {
  for (var i = 0; i + seq.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < seq.length; j++) {
      if (words[i + j] != seq[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
