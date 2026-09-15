/// One SQL statement within a multi-statement script.
class SqlStatement {
  SqlStatement({
    required this.text,
    required this.startOffset,
    required this.endOffset,
    required this.startLine,
  });

  /// The trimmed statement text, semicolon retained when present in source.
  final String text;

  /// 0-based offset into the source where the statement begins (post leading
  /// whitespace).
  final int startOffset;
  final int endOffset;

  /// 0-based line index of the first non-blank line of this statement.
  final int startLine;
}

/// Splits [sql] into independent statements while respecting:
///
///   - standard string literals (`'…'`, with doubled `''` for escaped quote)
///   - E-strings and U&'…' strings (`\` is an escape, so `\'` stays inside)
///   - dollar-quoted strings (`$$ … $$` and `$tag$ … $tag$`) used by
///     `CREATE FUNCTION`, `DO`, plpgsql bodies — semicolons inside the
///     dollar quotes are part of the statement, not separators.
///   - double-quoted identifiers (`"…"`, with `""` for escaped quote)
///   - line comments (`-- …`) and block comments (`/* … */`)
///
/// Empty / whitespace-only fragments are dropped. A trailing statement
/// without `;` is included as the last entry.
List<SqlStatement> parseSqlStatements(String sql) {
  final out = <SqlStatement>[];
  final length = sql.length;

  var i = 0;
  var currentStart = 0;
  var currentStartLine = 0;
  var line = 0;

  // Skip leading whitespace so the first statement's startLine is correct.
  while (i < length && _isBlank(sql.codeUnitAt(i))) {
    if (sql.codeUnitAt(i) == 0x0A) line++;
    i++;
  }
  currentStart = i;
  currentStartLine = line;

  while (i < length) {
    final c = sql.codeUnitAt(i);

    // Standard single-quoted string. Handle doubled '' as an escaped
    // quote (not a new string).
    if (c == 0x27) {
      i++;
      while (i < length) {
        final cc = sql.codeUnitAt(i);
        if (cc == 0x27) {
          if (i + 1 < length && sql.codeUnitAt(i + 1) == 0x27) {
            i += 2; // doubled quote — part of the literal
            continue;
          }
          i++;
          break;
        }
        if (cc == 0x0A) line++;
        i++;
      }
      continue;
    }

    // E'…' or U&'…' (and the lowercase variants): backslash is an escape,
    // so a backslash-apostrophe does NOT close the string. Doubled ''
    // remains an escape too.
    if ((c == 0x45 || c == 0x65 || c == 0x55 || c == 0x75) &&
        _isEscapeStringStart(sql, i)) {
      // Skip the prefix to land on the opening quote.
      while (i < length && sql.codeUnitAt(i) != 0x27) {
        i++;
      }
      if (i >= length) break;
      i++; // past opening '
      while (i < length) {
        final cc = sql.codeUnitAt(i);
        if (cc == 0x5C && i + 1 < length) {
          // backslash escapes the next char (including ')
          if (sql.codeUnitAt(i + 1) == 0x0A) line++;
          i += 2;
          continue;
        }
        if (cc == 0x27) {
          if (i + 1 < length && sql.codeUnitAt(i + 1) == 0x27) {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        if (cc == 0x0A) line++;
        i++;
      }
      continue;
    }

    // Dollar-quoted string $tag$ … $tag$ (or $$ … $$).
    if (c == 0x24) {
      final tagEnd = _scanDollarTag(sql, i);
      if (tagEnd != -1) {
        final tag = sql.substring(i, tagEnd + 1);
        i = tagEnd + 1;
        while (i < length) {
          if (sql.codeUnitAt(i) == 0x24 &&
              i + tag.length <= length &&
              sql.substring(i, i + tag.length) == tag) {
            i += tag.length;
            break;
          }
          if (sql.codeUnitAt(i) == 0x0A) line++;
          i++;
        }
        continue;
      }
      // Not a dollar tag — fall through to normal advance.
    }

    // Double-quoted identifier with doubled "" escape.
    if (c == 0x22) {
      i++;
      while (i < length) {
        final cc = sql.codeUnitAt(i);
        if (cc == 0x22) {
          if (i + 1 < length && sql.codeUnitAt(i + 1) == 0x22) {
            i += 2;
            continue;
          }
          i++;
          break;
        }
        if (cc == 0x0A) line++;
        i++;
      }
      continue;
    }

    // Line comment -- …
    if (c == 0x2D && i + 1 < length && sql.codeUnitAt(i + 1) == 0x2D) {
      while (i < length && sql.codeUnitAt(i) != 0x0A) {
        i++;
      }
      continue;
    }

    // Block comment /* … */. Treated as non-nesting, which Postgres is
    // not — it nests. The difference only makes this over-reject (a
    // nested comment can look like it ends early), which is the safe
    // direction for a gate whose job is refusing smuggled statements.
    if (c == 0x2F && i + 1 < length && sql.codeUnitAt(i + 1) == 0x2A) {
      i += 2;
      while (i + 1 < length) {
        if (sql.codeUnitAt(i) == 0x2A && sql.codeUnitAt(i + 1) == 0x2F) {
          i += 2;
          break;
        }
        if (sql.codeUnitAt(i) == 0x0A) line++;
        i++;
      }
      continue;
    }

    // Statement separator.
    if (c == 0x3B) {
      i++;
      final raw = sql.substring(currentStart, i);
      final trimmed = raw.trim();
      if (_containsSql(trimmed)) {
        out.add(
          SqlStatement(
            text: trimmed,
            startOffset: currentStart,
            endOffset: i,
            startLine: currentStartLine,
          ),
        );
      }
      while (i < length && _isBlank(sql.codeUnitAt(i))) {
        if (sql.codeUnitAt(i) == 0x0A) line++;
        i++;
      }
      currentStart = i;
      currentStartLine = line;
      continue;
    }

    if (c == 0x0A) line++;
    i++;
  }

  // Tail (no trailing ;)
  if (currentStart < length) {
    final raw = sql.substring(currentStart);
    final trimmed = raw.trim();
    if (_containsSql(trimmed)) {
      out.add(
        SqlStatement(
          text: trimmed,
          startOffset: currentStart,
          endOffset: length,
          startLine: currentStartLine,
        ),
      );
    }
  }

  return out;
}

/// True when [fragment] holds something an engine would actually execute,
/// rather than only whitespace, comments and semicolons.
///
/// A script ending `-- done` used to yield that comment as a final
/// statement. The run-all loop executes every entry, and SQLite's
/// `prepare` throws `Must contain an SQL statement` on a bare comment — so
/// a perfectly good script reported itself as having failed.
bool _containsSql(String fragment) {
  var i = 0;
  while (i < fragment.length) {
    final c = fragment.codeUnitAt(i);
    if (_isBlank(c) || c == 0x3B) {
      i++;
      continue;
    }
    if (c == 0x2D &&
        i + 1 < fragment.length &&
        fragment.codeUnitAt(i + 1) == 0x2D) {
      while (i < fragment.length && fragment.codeUnitAt(i) != 0x0A) {
        i++;
      }
      continue;
    }
    if (c == 0x2F &&
        i + 1 < fragment.length &&
        fragment.codeUnitAt(i + 1) == 0x2A) {
      i += 2;
      while (i + 1 < fragment.length &&
          !(fragment.codeUnitAt(i) == 0x2A &&
              fragment.codeUnitAt(i + 1) == 0x2F)) {
        i++;
      }
      i = i + 1 < fragment.length ? i + 2 : fragment.length;
      continue;
    }
    return true;
  }
  return false;
}

/// Returns the statement that contains [offset], or null if [offset] sits in
/// the whitespace/comments between statements.
SqlStatement? statementAtOffset(List<SqlStatement> stmts, int offset) {
  for (var i = 0; i < stmts.length; i++) {
    final s = stmts[i];
    if (offset < s.startOffset) continue;
    if (offset < s.endOffset) return s;
    // The caret sitting exactly on `endOffset` — just past the final `;` —
    // still belongs to this statement, because that is where it lands
    // after typing one. The exception is an abutting neighbour: in
    // `SELECT 1;SELECT 2` offset 9 is the start of the second statement,
    // and Run-statement was sending the first.
    if (offset == s.endOffset) {
      final next = i + 1 < stmts.length ? stmts[i + 1] : null;
      if (next == null || next.startOffset != offset) return s;
    }
  }
  return null;
}

/// True if the cursor [i] points at the start of an `E'…'` / `U&'…'`
/// escape-string. Only matches when the prefix sits on a word boundary
/// (so we don't mis-identify identifiers like `error` or `users`).
bool _isEscapeStringStart(String sql, int i) {
  if (i > 0) {
    final prev = sql.codeUnitAt(i - 1);
    if (_isIdentChar(prev)) return false;
  }
  final c = sql.codeUnitAt(i);
  if (c == 0x45 || c == 0x65) {
    // 'E' or 'e' followed by '
    return i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x27;
  }
  // U&' — 'U' or 'u', '&', '
  if (c == 0x55 || c == 0x75) {
    return i + 2 < sql.length &&
        sql.codeUnitAt(i + 1) == 0x26 &&
        sql.codeUnitAt(i + 2) == 0x27;
  }
  return false;
}

/// If [i] points at a `$`, returns the index of the closing `$` of the
/// tag (so the substring sql[i..end+1] = `$$` or `$tag$`); else -1.
///
/// A valid tag is `$ [A-Za-z_][A-Za-z0-9_]* $` or the empty `$$`.
int _scanDollarTag(String sql, int i) {
  if (i + 1 >= sql.length) return -1;
  if (sql.codeUnitAt(i + 1) == 0x24) return i + 1;
  var j = i + 1;
  if (!_isTagStartChar(sql.codeUnitAt(j))) return -1;
  j++;
  while (j < sql.length) {
    final c = sql.codeUnitAt(j);
    if (c == 0x24) return j;
    if (!_isIdentChar(c)) return -1;
    j++;
  }
  return -1;
}

bool _isTagStartChar(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

bool _isIdentChar(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x5F;

bool _isBlank(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
