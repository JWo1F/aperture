import '../models/cell_edit.dart';

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
