import '../models/cell_edit.dart';
import 'sql_statements.dart';

/// Pure SQL-rendering helpers shared by the per-engine table repositories.
///
/// Postgres and SQLite differ in row-identity tokens, transaction style, and
/// a handful of literal escaping details for non-text types — but the
/// quote-doubling for string literals, the `WHERE` prefix decision, and the
/// `CellEditValue → SQL fragment` translation are identical. Centralising
/// them here keeps the per-engine repository files focused on the parts that
/// genuinely diverge.

/// Renders a value as a SQL string literal. Strings stay untyped so the
/// engine coerces them into the target column type; single quotes are
/// doubled to neutralise injection.
String literalSql(String? value) {
  if (value == null) return 'NULL';
  return "'${value.replaceAll("'", "''")}'";
}

/// Translates a [CellEditValue] into the SQL fragment that goes on the
/// right-hand side of an assignment or VALUES tuple.
///
/// `CellDefault` renders as the bare `DEFAULT` keyword. Postgres accepts it
/// in both UPDATE assignments and VALUES lists; SQLite accepts it only in a
/// VALUES list, and the SQLite repository filters DEFAULT-valued columns out
/// of INSERTs and never builds an UPDATE with a CellDefault.
String renderAssignment(CellEditValue value) => switch (value) {
  CellLiteral(:final value) => literalSql(value),
  CellDefault() => 'DEFAULT',
};

/// Renders the optional ` WHERE <filter>` tail. Empty / whitespace-only
/// filters produce an empty string so the caller can concatenate
/// unconditionally.
String whereClause(String filter) {
  final trimmed = filter.trim();
  return trimmed.isEmpty ? '' : ' WHERE $trimmed';
}

/// Renders the optional ` ORDER BY <expr>` tail with the same shape as
/// [whereClause].
String orderClause(String orderBy) {
  final trimmed = orderBy.trim();
  return trimmed.isEmpty ? '' : ' ORDER BY $trimmed';
}

/// Identifies which clausebar input failed validation so the surfaced error
/// can name the offending field instead of leaking an engine-specific
/// parser message.
enum ClauseKind {
  filter('filter'),
  orderBy('order by'),
  selectList('select list');

  const ClauseKind(this.label);

  final String label;
}

/// Raised when a user-supplied clausebar snippet would smuggle additional
/// SQL statements into a query. The repos throw this *before* concatenating
/// the snippet so neither engine ever sees the injected text.
class ClauseSyntaxException implements Exception {
  ClauseSyntaxException({required this.kind, required this.snippet});

  final ClauseKind kind;
  final String snippet;

  @override
  String toString() =>
      '${kind.label} clause must be a single SQL expression '
      '(found multiple statements).';
}

/// Validates that [snippet] — a user-typed clausebar fragment — won't
/// terminate the surrounding query and introduce a second statement.
///
/// Empty / whitespace-only input is allowed; the corresponding clause is
/// omitted by [whereClause] / [orderClause] / the projection helpers. For
/// non-empty input we embed the snippet into a probe statement shaped like
/// the real query and feed it through [parseSqlStatements]; a result of
/// more than one statement means a top-level `;` (or a `;` followed by a
/// comment) inside the snippet closed the probe early, so we reject.
void validateClauseSnippet(String snippet, {required ClauseKind kind}) {
  final trimmed = snippet.trim();
  if (trimmed.isEmpty) return;
  final probe = switch (kind) {
    ClauseKind.filter => 'SELECT 1 FROM t WHERE $trimmed',
    ClauseKind.orderBy => 'SELECT 1 FROM t ORDER BY $trimmed',
    ClauseKind.selectList => 'SELECT $trimmed FROM t',
  };
  if (parseSqlStatements(probe).length > 1) {
    throw ClauseSyntaxException(kind: kind, snippet: trimmed);
  }
}
