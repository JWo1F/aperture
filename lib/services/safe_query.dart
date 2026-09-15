/// Heuristic that appends `LIMIT n` to bare top-level `SELECT` statements
/// so an unbounded `SELECT *` against a huge table can't OOM the isolate.
///
/// The transformation is intentionally conservative: only statements whose
/// first non-comment/non-whitespace keyword is `SELECT` (no `WITH`,
/// `INSERT`, DDL, …) and that don't already carry a `LIMIT` clause are
/// touched. Everything else passes through untouched.
library;

import 'sql_complete/text_scan.dart';

class SafeQuery {
  SafeQuery._(this.sql, this.appliedLimit);

  final String sql;
  final bool appliedLimit;
}

SafeQuery applyDefaultLimit(String sql, {required int limit}) {
  if (limit <= 0) return SafeQuery._(sql, false);
  final body = _stripLeadingCommentsAndWhitespace(sql);
  if (body == null) return SafeQuery._(sql, false);
  final head = body.toUpperCase();
  if (!head.startsWith('SELECT ') && head != 'SELECT') {
    return SafeQuery._(sql, false);
  }
  if (_hasRealLimit(body)) return SafeQuery._(sql, false);
  // Strip a single trailing `;` (and any following whitespace) before
  // appending so the rendered statement remains valid.
  var trimmed = body.trimRight();
  if (trimmed.endsWith(';')) {
    trimmed = trimmed.substring(0, trimmed.length - 1).trimRight();
  }
  // Newline, not a space: a statement ending in a `-- …` comment would
  // otherwise swallow the clause we just appended and run uncapped.
  return SafeQuery._('$trimmed\nLIMIT $limit', true);
}

/// True when [body] carries a `LIMIT <n>` that the engine will actually
/// honour. A textual match is not enough: `WHERE note = 'LIMIT 5'` and
/// `-- LIMIT 5 one day` both read as one, and skipping the cap on those
/// leaves an unbounded `SELECT *` free to materialise a whole relation.
bool _hasRealLimit(String body) {
  for (final m in RegExp(
    r'\bLIMIT\s+\d',
    caseSensitive: false,
  ).allMatches(body)) {
    if (!isInsideStringOrComment(body, m.start)) return true;
  }
  return false;
}

/// Skip line (`-- …`) and block (`/* … */`) comments plus surrounding
/// whitespace at the head of [sql]. Returns null if the trimmed input is
/// empty.
String? _stripLeadingCommentsAndWhitespace(String sql) {
  var i = 0;
  while (i < sql.length) {
    final c = sql.codeUnitAt(i);
    // ASCII whitespace
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    // line comment --
    if (c == 0x2D && i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x2D) {
      while (i < sql.length && sql.codeUnitAt(i) != 0x0A) {
        i++;
      }
      continue;
    }
    // block comment /* ... */
    if (c == 0x2F && i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x2A) {
      i += 2;
      while (i + 1 < sql.length &&
          !(sql.codeUnitAt(i) == 0x2A && sql.codeUnitAt(i + 1) == 0x2F)) {
        i++;
      }
      if (i + 1 < sql.length) i += 2;
      continue;
    }
    break;
  }
  if (i >= sql.length) return null;
  return sql.substring(i);
}
