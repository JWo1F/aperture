import '../models/cell_edit.dart';
import '../models/db_object.dart';
import 'sql_identifier.dart';
import 'sql_statements.dart';

/// Pure SQL-rendering helpers shared by the per-engine table repositories.
///
/// The engines differ in row-identity tokens, transaction style, and how a
/// [SqlDialect] spells identifiers and literals — but the `WHERE` prefix
/// decision and the `CellEditValue → SQL fragment` translation are
/// identical. Centralising them here keeps the per-engine repository files
/// focused on the parts that genuinely diverge.

/// Translates a [CellEditValue] into the SQL fragment that goes on the
/// right-hand side of an assignment or VALUES tuple.
///
/// `CellDefault` renders as the bare `DEFAULT` keyword. Postgres and MySQL
/// accept it in both UPDATE assignments and VALUES lists; SQLite accepts it
/// only in a VALUES list, and the SQLite repository filters DEFAULT-valued
/// columns out of INSERTs and never builds an UPDATE with a CellDefault.
String renderAssignment(CellEditValue value, SqlDialect dialect) =>
    switch (value) {
      CellLiteral(:final value) => dialect.literal(value),
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
/// terminate the surrounding query.
///
/// Empty / whitespace-only input is allowed; the corresponding clause is
/// omitted by [whereClause] / [orderClause] / the projection helpers. For
/// non-empty input we embed the snippet into a probe statement shaped like
/// the real query and append a sentinel clause. Anything that ends the
/// probe's own statement — a stacked `DROP`, or a bare trailing `;` —
/// leaves the sentinel in a second statement, so we reject.
///
/// The sentinel matters. Checking only for "more than one statement"
/// missed a trailing `;` on its own, because the empty fragment after it
/// is dropped by [parseSqlStatements]. SQLite's `prepare` compiles the
/// first statement and discards the rest of the string in silence, so a
/// filter of `1=1;` took the page query's LIMIT, OFFSET and ORDER BY with
/// it and fetched the entire relation into one page.
///
/// The sentinel goes on its own line so a snippet ending in a `--`
/// comment cannot swallow it and read as harmless.
///
/// [dialect] decides what counts as a string: MySQL reads `\'` inside a
/// literal as an escaped quote, so splitting its snippets the ANSI way
/// would see a closed string where the server sees an open one, and wave
/// through `x = 'a\'' ; DROP TABLE t; -- '`.
void validateClauseSnippet(
  String snippet, {
  required ClauseKind kind,
  required SqlDialect dialect,
}) {
  final trimmed = snippet.trim();
  if (trimmed.isEmpty) return;
  final probe = switch (kind) {
    ClauseKind.filter => 'SELECT 1 FROM t WHERE $trimmed\nLIMIT 1',
    ClauseKind.orderBy => 'SELECT 1 FROM t ORDER BY $trimmed\nLIMIT 1',
    ClauseKind.selectList => 'SELECT $trimmed FROM t\nLIMIT 1',
  };
  if (parseSqlStatements(probe, dialect: dialect).length > 1) {
    throw ClauseSyntaxException(kind: kind, snippet: trimmed);
  }
}

/// Engine-specific bits the shared edit-statement builder needs.
///
/// The shape of the batch (iteration order, UPDATE → DELETE → INSERT
/// ordering, the SET / VALUES rendering, identifier quoting) is identical
/// across engines and lives in [buildEditStatements]. What genuinely diverges
/// is row identity and `DEFAULT` semantics:
///
/// - Row identity: Postgres rows are addressed by `ctid` (`WHERE ctid =
///   '(0,5)'::tid`), SQLite rows by the implicit integer `rowid`
///   (`WHERE rowid = 7`, inlined — never bound). MySQL has neither, so its
///   rows are addressed by their primary-key values.
/// - DEFAULT in INSERT: Postgres and MySQL accept the bare `DEFAULT` keyword
///   inside a VALUES tuple. SQLite has no per-column DEFAULT marker, so the
///   column must be omitted entirely; the table default (or INTEGER PRIMARY
///   KEY auto-assignment) then fills it. That's what makes Duplicate-row
///   produce a fresh primary key on SQLite.
/// - DEFAULT in UPDATE: Postgres and MySQL accept `SET col = DEFAULT`.
///   SQLite rejects it, so `CellDefault` assignments are filtered out of the
///   SET list. If every assignment in an UPDATE is `CellDefault` the
///   statement collapses to a no-op and is dropped from the batch entirely —
///   keep the dropped row-id out of the caller's stale-row tracking list.
class EditPolicy {
  const EditPolicy({
    required this.rowIdPredicate,
    required this.insertOmitsDefaultColumns,
    required this.updateDropsDefaultAssignments,
  });

  /// Builds the trailing `WHERE …` predicate that pins a single row.
  final String Function(String rowId) rowIdPredicate;

  /// True when a `CellDefault` value in a `PendingInsert` should drop the
  /// column from the column / VALUES lists rather than emit `DEFAULT`.
  final bool insertOmitsDefaultColumns;

  /// True when a `CellDefault` assignment in an UPDATE should be filtered
  /// out of the SET list rather than emit `col = DEFAULT`.
  final bool updateDropsDefaultAssignments;
}

/// Renders the SQL a [batch] would produce against [table] under [policy].
///
/// Ordering is UPDATE → DELETE → INSERT so that a pending edit on a row
/// being duplicated in the same batch propagates the new value into the
/// source row before the duplicate commits.
///
/// An UPDATE that collapses to a no-op under
/// [EditPolicy.updateDropsDefaultAssignments] is omitted from the result;
/// callers using the statement index for stale-row reporting must filter
/// the same row-ids out of their tracking list (see
/// `SqliteTableRepository.applyEdits`).
List<String> buildEditStatements(
  DbTable table,
  EditBatch batch,
  EditPolicy policy,
) {
  return [
    for (final entry in batch.updatesByCtid.entries)
      ?_renderUpdate(table, entry.key, entry.value, policy),
    for (final id in batch.deleteCtids) _renderDelete(table, id, policy),
    for (final insert in batch.inserts) _renderInsert(table, insert, policy),
  ];
}

String? _renderUpdate(
  DbTable table,
  String rowId,
  Map<String, CellEditValue> assignments,
  EditPolicy policy,
) {
  final filtered = policy.updateDropsDefaultAssignments
      ? assignments.entries.where((e) => e.value is! CellDefault)
      : assignments.entries;
  final lines = filtered
      .map(
        (e) =>
            '  ${table.dialect.quoteIdent(e.key)} = '
            '${renderAssignment(e.value, table.dialect)}',
      )
      .join(',\n');
  if (lines.isEmpty) return null;
  return 'UPDATE ${table.qualifiedName} SET\n'
      '$lines\n'
      '${policy.rowIdPredicate(rowId)}';
}

String _renderDelete(DbTable table, String rowId, EditPolicy policy) =>
    'DELETE FROM ${table.qualifiedName}\n${policy.rowIdPredicate(rowId)}';

String _renderInsert(DbTable table, PendingInsert insert, EditPolicy policy) {
  final cols = policy.insertOmitsDefaultColumns
      ? [
          for (final entry in insert.values.entries)
            if (entry.value is! CellDefault) entry.key,
        ]
      : insert.values.keys.toList(growable: false);
  if (cols.isEmpty) {
    return switch (table.dialect) {
      SqlDialect.ansi => 'INSERT INTO ${table.qualifiedName} DEFAULT VALUES',
      SqlDialect.mysql => 'INSERT INTO ${table.qualifiedName} () VALUES ()',
    };
  }
  final colList = cols.map(table.dialect.quoteIdent).join(', ');
  final valList = cols
      .map((c) => renderAssignment(insert.values[c]!, table.dialect))
      .join(', ');
  return 'INSERT INTO ${table.qualifiedName} ($colList)\n'
      'VALUES ($valList)';
}
