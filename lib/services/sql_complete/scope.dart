import '../../models/db_catalog.dart';
import '../../models/db_object.dart';

/// Resolved snapshot of `FROM …` / `JOIN …` / `UPDATE …` / `INSERT INTO …`
/// references inside one statement — the set of relations whose columns are
/// in scope, plus the alias map for dot-qualified lookups.
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
    final part1 = unquoteIdentifier(m.group(2)!);
    final part2 = m.group(3) == null ? null : unquoteIdentifier(m.group(3)!);
    final aliasCandidate =
        m.group(4) == null ? null : unquoteIdentifier(m.group(4)!);
    final alias =
        aliasCandidate == null ||
            _clauseStops.contains(aliasCandidate.toLowerCase())
        ? null
        : aliasCandidate;

    final schema = part2 != null ? part1 : null;
    final tableName = part2 ?? part1;

    final table = lookupRelation(catalog, schema, tableName);
    if (table == null) continue;

    tables.add(table);
    aliases[alias ?? table.name] = table;
  }

  return SqlScope(tables: tables, aliases: aliases);
}

/// Resolves a (possibly schema-qualified) name to a relation. When [schema]
/// is null, prefers `public` then falls back to the first relation matching
/// the bare name in any schema.
DbTable? lookupRelation(
  DatabaseCatalog catalog,
  String? schema,
  String name,
) {
  if (schema != null) {
    final exact = catalog.relationByName(schema, name);
    if (exact != null) return exact;
    final lowerSchema = schema.toLowerCase();
    final lowerName = name.toLowerCase();
    for (final r in catalog.relationsByOid.values) {
      if (r.schema.toLowerCase() == lowerSchema &&
          r.name.toLowerCase() == lowerName) {
        return r;
      }
    }
    return null;
  }
  final inPublic = catalog.relationByName('public', name);
  if (inPublic != null) return inPublic;
  for (final r in catalog.relationsByOid.values) {
    if (r.name == name) return r;
  }
  final lower = name.toLowerCase();
  for (final r in catalog.relationsByOid.values) {
    if (r.name.toLowerCase() == lower) return r;
  }
  return null;
}

String unquoteIdentifier(String s) =>
    s.length >= 2 && s.startsWith('"') && s.endsWith('"')
    ? s.substring(1, s.length - 1)
    : s;
