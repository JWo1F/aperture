/// Heuristic that appends `LIMIT n` to bare top-level `SELECT` statements
/// so an unbounded `SELECT *` against a huge table can't OOM the isolate.
///
/// The transformation is intentionally conservative: only statements whose
/// first non-comment/non-whitespace keyword is `SELECT` (no `WITH`,
/// `INSERT`, DDL, …) and that don't already carry a row-limiting clause of
/// their own are touched. Everything else passes through untouched.
library;

class SafeQuery {
  SafeQuery._(this.sql, this.appliedLimit);

  final String sql;
  final bool appliedLimit;
}

SafeQuery applyDefaultLimit(String sql, {required int limit}) {
  if (limit <= 0) return SafeQuery._(sql, false);
  final scan = _scanStatement(sql);
  if (!scan.startsWithSelect || scan.alreadyLimited) {
    return SafeQuery._(sql, false);
  }
  // Append to the ORIGINAL text, not to the comment-stripped body: the
  // leading comments are part of what the user asked to run and of what
  // the activity log will show.
  var out = sql.trimRight();
  if (out.endsWith(';')) {
    out = out.substring(0, out.length - 1).trimRight();
  }
  // Newline, not a space: a statement ending in a `-- …` comment would
  // otherwise swallow the clause we just appended and run uncapped.
  return SafeQuery._('$out\nLIMIT $limit', true);
}

class _Scan {
  const _Scan({required this.startsWithSelect, required this.alreadyLimited});

  final bool startsWithSelect;

  /// True when the statement carries its own top-level row limit — `LIMIT`
  /// or the SQL-standard `FETCH FIRST … ROWS`. Appending to either is an
  /// error (`multiple LIMIT clauses not allowed`), and treating a
  /// subquery's limit as the statement's own leaves the outer `SELECT`
  /// unbounded.
  final bool alreadyLimited;
}

/// Single pass over [sql] that answers both questions the cap needs, while
/// ignoring text the engine won't execute.
///
/// A plain regex is not enough in either direction. `WHERE note = 'LIMIT 5'`
/// and `-- LIMIT 5 one day` are not limits, and skipping the cap on those
/// leaves a whole relation free to materialise. Nor is a bare keyword
/// search: the `LIMIT` in `id IN (SELECT id FROM small LIMIT 5)` bounds the
/// subquery, not the statement, so only depth 0 counts.
_Scan _scanStatement(String sql) {
  var i = 0;
  var depth = 0;
  bool? startsWithSelect;
  var limited = false;

  bool isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
  bool isWordChar(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5F;

  while (i < sql.length) {
    final c = sql.codeUnitAt(i);

    if (isSpace(c)) {
      i++;
      continue;
    }

    // -- line comment
    if (c == 0x2D && i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x2D) {
      while (i < sql.length && sql.codeUnitAt(i) != 0x0A) {
        i++;
      }
      continue;
    }

    // /* block comment */ — non-nested, matching the engines' own parsers
    // closely enough for a safety heuristic.
    if (c == 0x2F && i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x2A) {
      i += 2;
      while (i + 1 < sql.length &&
          !(sql.codeUnitAt(i) == 0x2A && sql.codeUnitAt(i + 1) == 0x2F)) {
        i++;
      }
      i = i + 1 < sql.length ? i + 2 : sql.length;
      continue;
    }

    // '…' string, with '' as an escaped quote. A preceding E/e means
    // backslash escapes too.
    if (c == 0x27) {
      final escapes =
          i > 0 && (sql.codeUnitAt(i - 1) | 0x20) == 0x65 &&
          (i < 2 || !isWordChar(sql.codeUnitAt(i - 2)));
      i++;
      while (i < sql.length) {
        final cc = sql.codeUnitAt(i);
        if (escapes && cc == 0x5C && i + 1 < sql.length) {
          i += 2;
          continue;
        }
        if (cc == 0x27) {
          if (i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x27) {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    // "…" quoted identifier, with "" as an escaped quote.
    if (c == 0x22) {
      i++;
      while (i < sql.length) {
        final cc = sql.codeUnitAt(i);
        if (cc == 0x22) {
          if (i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x22) {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    // $tag$ … $tag$ dollar-quoted body.
    if (c == 0x24) {
      final close = _dollarTagEnd(sql, i);
      if (close != -1) {
        final tag = sql.substring(i, close + 1);
        i = close + 1;
        while (i < sql.length) {
          if (sql.codeUnitAt(i) == 0x24 &&
              i + tag.length <= sql.length &&
              sql.substring(i, i + tag.length) == tag) {
            i += tag.length;
            break;
          }
          i++;
        }
        continue;
      }
    }

    if (c == 0x28) {
      depth++;
      i++;
      continue;
    }
    if (c == 0x29) {
      if (depth > 0) depth--;
      i++;
      continue;
    }

    if (isWordChar(c)) {
      final start = i;
      while (i < sql.length && isWordChar(sql.codeUnitAt(i))) {
        i++;
      }
      final word = sql.substring(start, i).toUpperCase();
      startsWithSelect ??= word == 'SELECT';
      if (depth == 0 && (word == 'LIMIT' || word == 'FETCH')) limited = true;
      continue;
    }

    i++;
  }

  return _Scan(
    startsWithSelect: startsWithSelect ?? false,
    alreadyLimited: limited,
  );
}

/// If [i] points at a `$`, the index of the closing `$` of a valid
/// dollar-quote tag (`$$` or `$tag$`); otherwise -1.
int _dollarTagEnd(String sql, int i) {
  if (i + 1 >= sql.length) return -1;
  if (sql.codeUnitAt(i + 1) == 0x24) return i + 1;
  var j = i + 1;
  bool tagStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
  bool tagChar(int c) => tagStart(c) || (c >= 0x30 && c <= 0x39);
  if (!tagStart(sql.codeUnitAt(j))) return -1;
  j++;
  while (j < sql.length) {
    final c = sql.codeUnitAt(j);
    if (c == 0x24) return j;
    if (!tagChar(c)) return -1;
    j++;
  }
  return -1;
}
