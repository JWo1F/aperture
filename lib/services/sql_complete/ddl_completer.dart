import '../../models/db_catalog.dart';
import '../../models/db_object.dart';
import '../../ui/widgets/code_editor.dart';
import 'keywords.dart';
import 'scope.dart';
import 'suggestions.dart';
import 'text_scan.dart';

/// Completion for CREATE / ALTER / DROP / TRUNCATE statements.
///
/// Returns an unranked candidate pool, or `null` to signal "this is not a
/// DDL slot I handle — delegate to the SELECT completer" (used for the
/// `CREATE … AS SELECT` / `CREATE VIEW … AS SELECT` body).
///
/// Unlike the SELECT path this matcher works off the keyword skeleton:
/// it tokenizes the statement-so-far, drops the partial token under the
/// caret, and pattern-matches the trailing words. Free-identifier slots
/// (a fresh table / column / constraint name) return an empty pool so the
/// popup stays closed there.
List<CodeSuggestion>? completeDdlPool({
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
  if (words.isEmpty) return null; // still typing the CREATE/ALTER/… head

  // `CREATE TABLE … AS SELECT` / `CREATE VIEW … AS SELECT` — once a SELECT
  // body has begun the read-path completer handles it far better.
  if (words.contains('select')) return null;

  switch (words.first) {
    case 'create':
      return _create(words, ctx, catalog);
    case 'alter':
      return _alter(words, ctx, catalog);
    case 'drop':
      return _drop(words, catalog);
    case 'truncate':
      return _truncate(words, ctx, catalog);
  }
  return null;
}

// --- CREATE -------------------------------------------------------------

List<CodeSuggestion>? _create(
  List<String> words,
  String ctx,
  DatabaseCatalog catalog,
) {
  if (words.length == 1) return keywordsToSuggestions(createObjectKeywords);

  final prev = words.last;
  switch (prev) {
    case 'or':
      return keywordsToSuggestions(['REPLACE']);
    case 'replace':
      return keywordsToSuggestions(['VIEW', 'FUNCTION', 'TRIGGER']);
    case 'unique':
      return keywordsToSuggestions(['INDEX']);
    case 'materialized':
      return keywordsToSuggestions(['VIEW']);
    case 'temp':
    case 'temporary':
    case 'unlogged':
    case 'global':
    case 'local':
      return keywordsToSuggestions(['TABLE', 'VIEW', 'SEQUENCE']);
    case 'if':
      return keywordsToSuggestions(['NOT EXISTS']);
    case 'not':
      return keywordsToSuggestions(['EXISTS']);
  }

  if (words.contains('table')) return _createTable(words, ctx, catalog);
  if (words.contains('index')) return _createIndex(words, ctx, catalog);
  if (words.contains('view')) return _createView(words);
  if (words.contains('type')) {
    return prev == 'as' ? keywordsToSuggestions(['ENUM', 'RANGE']) : const [];
  }
  if (words.contains('schema') && prev == 'schema') {
    return keywordsToSuggestions(['IF NOT EXISTS', 'AUTHORIZATION']);
  }
  return const [];
}

List<CodeSuggestion> _createTable(
  List<String> words,
  String ctx,
  DatabaseCatalog catalog,
) {
  if (parenDepth(ctx) >= 1) return _columnDef(ctx, catalog);

  final prev = words.last;
  if (prev == 'table') return keywordsToSuggestions(['IF NOT EXISTS']);
  if (_endsWith(words, ['if', 'not', 'exists'])) return const [];
  if (prev == 'as') return keywordsToSuggestions(['SELECT', 'WITH']);
  // A table name has been typed — the alternative to `(` is `AS …`.
  return keywordsToSuggestions(['AS']);
}

/// Completion inside the parenthesised body of `CREATE TABLE name (…)`.
List<CodeSuggestion> _columnDef(String ctx, DatabaseCatalog catalog) {
  // Find the start of the column definition the caret sits in: the most
  // recent `(` that opened depth 1, or the most recent depth-1 comma.
  var depth = 0;
  var boundary = -1;
  for (var i = 0; i < ctx.length; i++) {
    final c = ctx.codeUnitAt(i);
    if (c == 0x28) {
      depth++;
      if (depth == 1) boundary = i + 1;
    } else if (c == 0x29) {
      depth--;
    } else if (c == 0x2C && depth == 1) {
      boundary = i + 1;
    }
  }
  if (boundary < 0) return const [];
  final segment = ctx.substring(boundary);
  final segWords = [for (final w in wordsIn(segment)) w.toLowerCase()];

  if (depth >= 2) {
    // A nested paren — only worth completing for a `REFERENCES t (…)`
    // foreign-key column list (the table being created isn't in the
    // catalog yet, so CHECK / type-size parens get nothing).
    final ref = _refTableIn(segment, catalog);
    return ref == null ? const [] : columnsToSuggestions(catalog.columnsFor(ref));
  }

  if (segWords.isEmpty) return keywordsToSuggestions(tableConstraintKeywords);

  // A line that opens with a table-constraint keyword is a constraint
  // definition, not a `<column> <type>` pair.
  if (tableConstraintStartWords.contains(segWords.first)) {
    if (segWords.first == 'like') return tableSuggestions(catalog);
    if (segWords.last == 'references') return tableSuggestions(catalog);
    if (segWords.length == 1 &&
        (segWords.first == 'primary' || segWords.first == 'foreign')) {
      return keywordsToSuggestions(['KEY']);
    }
    return const [];
  }

  if (segWords.length == 1) return _typeSuggestions(catalog);
  if (segWords.last == 'references') return tableSuggestions(catalog);
  if (segWords.last == 'default') return _defaultValueSuggestions();
  return keywordsToSuggestions(columnConstraintKeywords);
}

List<CodeSuggestion> _createIndex(
  List<String> words,
  String ctx,
  DatabaseCatalog catalog,
) {
  final prev = words.last;
  if (words.contains('on')) {
    if (parenDepth(ctx) >= 1) {
      final t = _matchTable(_indexOnRe, ctx, catalog);
      return [
        if (t != null) ...columnsToSuggestions(catalog.columnsFor(t)),
        ...keywordsToSuggestions(orderKeywords),
      ];
    }
    if (prev == 'on') return tableSuggestions(catalog);
    if (prev == 'using') return keywordsToSuggestions(indexMethodKeywords);
    return keywordsToSuggestions(['USING']);
  }
  if (prev == 'index') {
    return keywordsToSuggestions(['ON', 'CONCURRENTLY', 'IF NOT EXISTS']);
  }
  if (prev == 'concurrently') {
    return keywordsToSuggestions(['ON', 'IF NOT EXISTS']);
  }
  return keywordsToSuggestions(['ON']);
}

List<CodeSuggestion> _createView(List<String> words) {
  final prev = words.last;
  if (prev == 'view') return const []; // typing the new view name
  if (prev == 'as') return keywordsToSuggestions(['SELECT', 'WITH']);
  if (_endsWith(words, ['if', 'not', 'exists'])) return const [];
  return keywordsToSuggestions(['AS']);
}

// --- ALTER --------------------------------------------------------------

List<CodeSuggestion>? _alter(
  List<String> words,
  String ctx,
  DatabaseCatalog catalog,
) {
  if (words.length == 1) return keywordsToSuggestions(alterObjectKeywords);
  if (words[1] == 'table') return _alterTable(words, ctx, catalog);
  return _alterOther(words, catalog);
}

List<CodeSuggestion> _alterTable(
  List<String> words,
  String ctx,
  DatabaseCatalog catalog,
) {
  final m = _alterTableTargetRe.firstMatch(ctx);
  if (m == null) {
    // The target table hasn't been fully typed yet.
    final prev = words.last;
    if (prev == 'table') {
      return [
        ...keywordsToSuggestions(['IF EXISTS', 'ONLY']),
        ...tableSuggestions(catalog),
      ];
    }
    if (prev == 'only' || prev == 'exists') return tableSuggestions(catalog);
    return const [];
  }
  final target = _resolveRef(m.group(1), m.group(2), catalog);
  final tail = [for (final w in wordsIn(ctx.substring(m.end))) w.toLowerCase()];
  return _alterTableTail(tail, target, catalog);
}

List<CodeSuggestion> _alterTableTail(
  List<String> tail,
  DbTable? target,
  DatabaseCatalog catalog,
) {
  final cols = target == null
      ? const <CodeSuggestion>[]
      : columnsToSuggestions(catalog.columnsFor(target));

  if (tail.isEmpty) return keywordsToSuggestions(alterTableActionKeywords);
  if (tail.last == 'references') return tableSuggestions(catalog);
  if (tail.last == 'default') return _defaultValueSuggestions();

  switch (tail.first) {
    case 'add':
      return _alterAdd(tail, catalog);
    case 'drop':
      return _alterDrop(tail, cols, target, catalog);
    case 'alter':
      return _alterColumn(tail, cols, catalog);
    case 'rename':
      return _alterRename(tail, cols, target, catalog);
    case 'owner':
      return tail.length == 1 ? keywordsToSuggestions(['TO']) : const [];
    case 'set':
      if (tail.length == 1) {
        return keywordsToSuggestions(['SCHEMA', 'TABLESPACE', 'WITHOUT OIDS']);
      }
      return tail[1] == 'schema' ? _schemaNames(catalog) : const [];
    case 'enable':
    case 'disable':
      return keywordsToSuggestions(['ROW LEVEL SECURITY', 'TRIGGER', 'RULE']);
    case 'validate':
      return tail.length == 1
          ? keywordsToSuggestions(['CONSTRAINT'])
          : _constraintNames(target, catalog);
  }
  return const [];
}

List<CodeSuggestion> _alterAdd(List<String> tail, DatabaseCatalog catalog) {
  if (tail.length == 1) {
    return keywordsToSuggestions([
      'COLUMN',
      'CONSTRAINT',
      'PRIMARY KEY',
      'FOREIGN KEY',
      'UNIQUE',
      'CHECK',
    ]);
  }
  if (tail[1] == 'column') {
    final after = tail.length - 2; // words past `ADD COLUMN`
    if (after <= 0) return const []; // typing the new column name
    if (after == 1) return _typeSuggestions(catalog); // after the name
    return keywordsToSuggestions(columnConstraintKeywords);
  }
  if (tail[1] == 'constraint') {
    return tail.length == 2
        ? const [] // typing the new constraint name
        : keywordsToSuggestions([
            'PRIMARY KEY',
            'FOREIGN KEY',
            'UNIQUE',
            'CHECK',
          ]);
  }
  if (tail[1] == 'primary' || tail[1] == 'foreign') {
    return keywordsToSuggestions(['KEY']);
  }
  // `ADD <name> <type> …` with the COLUMN keyword omitted.
  final after = tail.length - 1;
  if (after == 1) return _typeSuggestions(catalog);
  return keywordsToSuggestions(columnConstraintKeywords);
}

List<CodeSuggestion> _alterDrop(
  List<String> tail,
  List<CodeSuggestion> cols,
  DbTable? target,
  DatabaseCatalog catalog,
) {
  if (tail.length == 1) {
    return [
      ...keywordsToSuggestions(['COLUMN', 'CONSTRAINT', 'IF EXISTS']),
      ...cols,
    ];
  }
  if (tail[1] == 'column') {
    return tail.length == 2 ? cols : keywordsToSuggestions(dropBehaviorKeywords);
  }
  if (tail[1] == 'constraint') {
    return tail.length == 2
        ? [
            ..._constraintNames(target, catalog),
            ...keywordsToSuggestions(['IF EXISTS']),
          ]
        : keywordsToSuggestions(dropBehaviorKeywords);
  }
  // `DROP <column>` with the COLUMN keyword omitted.
  return keywordsToSuggestions(dropBehaviorKeywords);
}

List<CodeSuggestion> _alterColumn(
  List<String> tail,
  List<CodeSuggestion> cols,
  DatabaseCatalog catalog,
) {
  final hasColumnKw = tail.length >= 2 && tail[1] == 'column';
  final colIdx = hasColumnKw ? 2 : 1;
  if (tail.length <= colIdx) {
    return hasColumnKw
        ? cols
        : [...keywordsToSuggestions(['COLUMN']), ...cols];
  }
  final actions = tail.sublist(colIdx + 1);
  if (actions.isEmpty) return keywordsToSuggestions(alterColumnActionKeywords);
  if (actions.last == 'type') return _typeSuggestions(catalog);
  if (_endsWith(actions, ['set', 'data'])) return keywordsToSuggestions(['TYPE']);
  if (actions.last == 'set') {
    return keywordsToSuggestions(['DEFAULT', 'NOT NULL', 'DATA TYPE', 'STATISTICS']);
  }
  if (actions.last == 'drop') {
    return keywordsToSuggestions(['DEFAULT', 'NOT NULL', 'IDENTITY', 'EXPRESSION']);
  }
  return const [];
}

List<CodeSuggestion> _alterRename(
  List<String> tail,
  List<CodeSuggestion> cols,
  DbTable? target,
  DatabaseCatalog catalog,
) {
  if (tail.length == 1) {
    return [...keywordsToSuggestions(['COLUMN', 'CONSTRAINT', 'TO']), ...cols];
  }
  if (tail[1] == 'column') {
    if (tail.length == 2) return cols;
    if (tail.length == 3) return keywordsToSuggestions(['TO']);
    return const [];
  }
  if (tail[1] == 'constraint') {
    if (tail.length == 2) return _constraintNames(target, catalog);
    if (tail.length == 3) return keywordsToSuggestions(['TO']);
    return const [];
  }
  if (tail[1] == 'to') return const [];
  // `RENAME <column> …` with the COLUMN keyword omitted.
  return tail.length == 2 ? keywordsToSuggestions(['TO']) : const [];
}

List<CodeSuggestion> _alterOther(List<String> words, DatabaseCatalog catalog) {
  final kind = words[1];
  final prev = words.last;
  switch (kind) {
    case 'index':
      return prev == 'index'
          ? _indexNames(catalog)
          : keywordsToSuggestions([
              'RENAME TO',
              'SET TABLESPACE',
              'ALTER COLUMN',
            ]);
    case 'view':
      return prev == 'view'
          ? relationSuggestions(catalog, kinds: {DbRelationKind.view})
          : keywordsToSuggestions([
              'RENAME TO',
              'RENAME COLUMN',
              'ALTER COLUMN',
              'OWNER TO',
              'SET SCHEMA',
            ]);
    case 'materialized':
      return prev == 'view' || prev == 'materialized'
          ? relationSuggestions(
              catalog,
              kinds: {DbRelationKind.materializedView},
            )
          : keywordsToSuggestions(['RENAME TO', 'RENAME COLUMN', 'OWNER TO']);
    case 'sequence':
      return keywordsToSuggestions([
        'RESTART',
        'OWNED BY',
        'RENAME TO',
        'SET SCHEMA',
        'INCREMENT BY',
      ]);
    case 'schema':
      return prev == 'schema'
          ? _schemaNames(catalog)
          : keywordsToSuggestions(['RENAME TO', 'OWNER TO']);
    case 'type':
      return prev == 'type'
          ? _typeNames(catalog)
          : keywordsToSuggestions([
              'ADD VALUE',
              'RENAME TO',
              'RENAME VALUE',
              'OWNER TO',
              'SET SCHEMA',
            ]);
  }
  return const [];
}

// --- DROP ---------------------------------------------------------------

const _dropKindWords = {
  'table', 'view', 'materialized', 'index', 'sequence', 'schema',
  'type', 'extension', 'trigger', 'function', 'database', 'role',
};

const _dropStopWords = {
  'drop', 'if', 'exists', 'cascade', 'restrict', 'concurrently', ..._dropKindWords,
};

List<CodeSuggestion>? _drop(List<String> words, DatabaseCatalog catalog) {
  if (words.length == 1) return keywordsToSuggestions(dropObjectKeywords);

  final prev = words.last;
  if (prev == 'if') return keywordsToSuggestions(['EXISTS']);
  if (prev == 'not') return keywordsToSuggestions(['EXISTS']);

  // Once an object name has been typed the only tails are CASCADE/RESTRICT.
  if (!_dropStopWords.contains(prev)) {
    return keywordsToSuggestions(dropBehaviorKeywords);
  }

  final kind = words.firstWhere(
    _dropKindWords.contains,
    orElse: () => '',
  );
  switch (kind) {
    case 'table':
      return [
        if (prev != 'exists') ...keywordsToSuggestions(['IF EXISTS']),
        ...relationSuggestions(catalog, kinds: {DbRelationKind.table}),
      ];
    case 'view':
      return relationSuggestions(catalog, kinds: {DbRelationKind.view});
    case 'materialized':
      return relationSuggestions(
        catalog,
        kinds: {DbRelationKind.materializedView},
      );
    case 'index':
      return _indexNames(catalog);
    case 'schema':
      return _schemaNames(catalog);
    case 'type':
      return _typeNames(catalog);
  }
  return const [];
}

// --- TRUNCATE -----------------------------------------------------------

const _truncateStopWords = {
  'truncate', 'table', 'only', 'cascade', 'restrict', 'restart',
  'continue', 'identity',
};

List<CodeSuggestion>? _truncate(
  List<String> words,
  String ctx,
  DatabaseCatalog catalog,
) {
  final prev = words.last;
  if (words.length == 1) {
    return [
      ...keywordsToSuggestions(['TABLE', 'ONLY']),
      ...relationSuggestions(catalog, kinds: {DbRelationKind.table}),
    ];
  }
  if (prev == 'table' || prev == 'only') {
    return relationSuggestions(catalog, kinds: {DbRelationKind.table});
  }
  if (prev == 'restart' || prev == 'continue') {
    return keywordsToSuggestions(['IDENTITY']);
  }
  if (!_truncateStopWords.contains(prev)) {
    // After a table name — another table follows a comma, else an option.
    return lastNonSpaceCode(ctx) == 0x2C
        ? relationSuggestions(catalog, kinds: {DbRelationKind.table})
        : keywordsToSuggestions(truncateOptionKeywords);
  }
  return const [];
}

// --- Shared helpers -----------------------------------------------------

final _alterTableTargetRe = RegExp(
  r'\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?'
  r'("[^"]+"|[a-zA-Z_]\w*)(?:\s*\.\s*("[^"]+"|[a-zA-Z_]\w*))?',
  caseSensitive: false,
);

final _indexOnRe = RegExp(
  r'\bon\s+("[^"]+"|[a-zA-Z_]\w*)(?:\s*\.\s*("[^"]+"|[a-zA-Z_]\w*))?',
  caseSensitive: false,
);

final _referencesRe = RegExp(
  r'\breferences\s+("[^"]+"|[a-zA-Z_]\w*)(?:\s*\.\s*("[^"]+"|[a-zA-Z_]\w*))?',
  caseSensitive: false,
);

DbTable? _resolveRef(String? g1, String? g2, DatabaseCatalog catalog) {
  if (g1 == null) return null;
  final n1 = unquoteIdentifier(g1);
  if (g2 != null) return lookupRelation(catalog, n1, unquoteIdentifier(g2));
  return lookupRelation(catalog, null, n1);
}

DbTable? _matchTable(RegExp re, String text, DatabaseCatalog catalog) {
  final m = re.firstMatch(text);
  return m == null ? null : _resolveRef(m.group(1), m.group(2), catalog);
}

DbTable? _refTableIn(String segment, DatabaseCatalog catalog) =>
    _matchTable(_referencesRe, segment, catalog);

bool _endsWith(List<String> words, List<String> suffix) {
  if (words.length < suffix.length) return false;
  for (var i = 0; i < suffix.length; i++) {
    if (words[words.length - suffix.length + i] != suffix[i]) return false;
  }
  return true;
}

List<CodeSuggestion> _names(
  Iterable<String> names,
  String detail, {
  SuggestionKind kind = SuggestionKind.table,
}) => [
  for (final n in names)
    CodeSuggestion(label: n, insertText: n, detail: detail, kind: kind),
];

/// Built-in data types plus the catalog's user-defined enum / domain types.
List<CodeSuggestion> _typeSuggestions(DatabaseCatalog catalog) => [
  for (final t in dataTypeKeywords)
    CodeSuggestion(
      label: t,
      insertText: t,
      detail: 'type',
      kind: SuggestionKind.keyword,
      chainNext: true,
    ),
  ..._names([for (final e in catalog.enums) e.name], 'enum'),
  ..._names([for (final d in catalog.domains) d.name], 'domain'),
];

const _defaultValues = [
  'NULL',
  'true',
  'false',
  'now()',
  'CURRENT_TIMESTAMP',
  'CURRENT_DATE',
  'gen_random_uuid()',
  '0',
];

List<CodeSuggestion> _defaultValueSuggestions() =>
    _names(_defaultValues, 'default', kind: SuggestionKind.snippet);

List<CodeSuggestion> _schemaNames(DatabaseCatalog catalog) =>
    _names([for (final s in catalog.schemas) s.name], 'schema');

List<CodeSuggestion> _typeNames(DatabaseCatalog catalog) => [
  ..._names([for (final e in catalog.enums) e.name], 'enum'),
  ..._names([for (final d in catalog.domains) d.name], 'domain'),
];

List<CodeSuggestion> _indexNames(DatabaseCatalog catalog) {
  final seen = <String>{};
  final out = <CodeSuggestion>[];
  for (final list in catalog.indexesByOid.values) {
    for (final ix in list) {
      if (seen.add(ix.name)) {
        out.add(
          CodeSuggestion(
            label: ix.name,
            insertText: ix.name,
            detail: 'index',
            kind: SuggestionKind.table,
          ),
        );
      }
    }
  }
  return out;
}

List<CodeSuggestion> _constraintNames(
  DbTable? target,
  DatabaseCatalog catalog,
) {
  if (target == null) return const [];
  final fks = catalog.foreignKeysByOid[target.oid] ?? const <DbForeignKey>[];
  return _names([for (final fk in fks) fk.constraintName], 'constraint');
}
