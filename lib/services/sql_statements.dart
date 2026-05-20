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

/// Splits [sql] into independent statements, respecting string literals
/// (single/double quoted), line comments (`-- …`), and block comments
/// (`/* … */`). Empty / whitespace-only fragments are dropped.
///
/// Trailing tail (no terminating `;`) is included as the last statement.
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

    // Single-quoted string.
    if (c == 0x27) {
      i++;
      while (i < length) {
        if (sql.codeUnitAt(i) == 0x27) {
          i++;
          break;
        }
        if (sql.codeUnitAt(i) == 0x0A) line++;
        i++;
      }
      continue;
    }

    // Double-quoted identifier.
    if (c == 0x22) {
      i++;
      while (i < length) {
        if (sql.codeUnitAt(i) == 0x22) {
          i++;
          break;
        }
        if (sql.codeUnitAt(i) == 0x0A) line++;
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

    // Block comment /* … */
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
      if (trimmed.isNotEmpty && trimmed != ';') {
        out.add(SqlStatement(
          text: trimmed,
          startOffset: currentStart,
          endOffset: i,
          startLine: currentStartLine,
        ));
      }
      // Advance past blank space + newlines to the next statement's first
      // meaningful character; that becomes the next startLine.
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
    if (trimmed.isNotEmpty) {
      out.add(SqlStatement(
        text: trimmed,
        startOffset: currentStart,
        endOffset: length,
        startLine: currentStartLine,
      ));
    }
  }

  return out;
}

/// Returns the statement that contains [offset], or null if [offset] sits in
/// the whitespace/comments between statements.
SqlStatement? statementAtOffset(List<SqlStatement> stmts, int offset) {
  for (final s in stmts) {
    if (offset >= s.startOffset && offset <= s.endOffset) return s;
  }
  return null;
}

bool _isBlank(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
