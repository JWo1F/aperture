/// Low-level lexical scanning for the SQL autocomplete engine: string and
/// comment detection, cursor-relative word lookups, and the shared
/// tokenizer. Pure string functions — no catalog or suggestion awareness.
library;

bool isSpaceCode(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool isWordCode(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F;

/// True when the caret sits inside a single-quoted literal, a `--` line
/// comment, or a `/* … */` block comment. The editor uses this to
/// suppress the popup so we don't pop suggestions while typing string
/// content. Scans the *full* text — string scope is decided by whether
/// the cursor lies inside an open-close pair, so we have to look past
/// the cursor for the closing delimiter.
bool isInsideStringOrComment(String text, int cursor) {
  final upto = cursor.clamp(0, text.length);
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);

    if (c == 0x27 /* ' */ ) {
      final openedBeforeCursor = i < upto;
      i++;
      var closed = false;
      while (i < text.length) {
        final cc = text.codeUnitAt(i);
        if (cc == 0x27) {
          if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x27) {
            i += 2;
            continue;
          }
          i++;
          closed = true;
          break;
        }
        i++;
      }
      // Cursor falls inside the literal when the opener is before it
      // *and* the closer (if any) is at or after it.
      if (openedBeforeCursor && (!closed || i > upto)) return true;
      continue;
    }

    if (c == 0x2D /* - */ &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == 0x2D) {
      final openedBeforeCursor = i < upto;
      while (i < text.length && text.codeUnitAt(i) != 0x0A) {
        i++;
      }
      // Cursor is in the comment when the `--` opens before it and the
      // newline (which we stop on) lands at or after it.
      if (openedBeforeCursor && i >= upto) return true;
      continue;
    }

    if (c == 0x2F /* / */ &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) == 0x2A) {
      final openedBeforeCursor = i < upto;
      i += 2;
      var closed = false;
      while (i + 1 < text.length) {
        if (text.codeUnitAt(i) == 0x2A && text.codeUnitAt(i + 1) == 0x2F) {
          i += 2;
          closed = true;
          break;
        }
        i++;
      }
      if (!closed) i = text.length;
      if (openedBeforeCursor && (!closed || i > upto)) return true;
      continue;
    }

    i++;
  }
  return false;
}

/// Returns [text] truncated at [upto] with every string-literal and
/// comment region replaced by spaces. Used by the clause/statement
/// scanners so a stray keyword inside a string doesn't fool them.
String stripStringsAndComments(String text, int upto) {
  final end = upto.clamp(0, text.length);
  final buf = StringBuffer();
  var i = 0;
  while (i < end) {
    final c = text.codeUnitAt(i);
    if (c == 0x27) {
      buf.write(' ');
      i++;
      while (i < end) {
        final cc = text.codeUnitAt(i);
        if (cc == 0x27) {
          if (i + 1 < end && text.codeUnitAt(i + 1) == 0x27) {
            buf.write('  ');
            i += 2;
            continue;
          }
          buf.write(' ');
          i++;
          break;
        }
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (c == 0x2D && i + 1 < end && text.codeUnitAt(i + 1) == 0x2D) {
      while (i < end && text.codeUnitAt(i) != 0x0A) {
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (c == 0x2F && i + 1 < end && text.codeUnitAt(i + 1) == 0x2A) {
      buf.write('  ');
      i += 2;
      while (i + 1 < end) {
        if (text.codeUnitAt(i) == 0x2A && text.codeUnitAt(i + 1) == 0x2F) {
          buf.write('  ');
          i += 2;
          break;
        }
        buf.write(' ');
        i++;
      }
      continue;
    }
    buf.writeCharCode(c);
    i++;
  }
  return buf.toString();
}

/// Returns the lowercased word immediately preceding [tokenStart], skipping
/// any whitespace. Used for "right after a JOIN/FROM" tests.
String previousWord(String text, int tokenStart) {
  var i = tokenStart.clamp(0, text.length);
  while (i > 0 && isSpaceCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  final end = i;
  while (i > 0 && isWordCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  return text.substring(i, end).toLowerCase();
}

/// Returns the qualifier when [tokenStart] sits right after `<qualifier>.`,
/// e.g. given `… users u WHERE u.id|`, the qualifier of the token at the
/// caret is `u`. Returns null when no dot precedes the token.
String? qualifierBefore(String text, int tokenStart) {
  if (tokenStart <= 0 || tokenStart > text.length) return null;
  if (text.codeUnitAt(tokenStart - 1) != 0x2E /* . */ ) return null;
  var i = tokenStart - 1;
  while (i > 0 && isWordCode(text.codeUnitAt(i - 1))) {
    i--;
  }
  if (i == tokenStart - 1) return null;
  return text.substring(i, tokenStart - 1);
}

/// Walks `.identifier.identifier.…` backwards from [tokenStart],
/// returning the dot-separated chain as a list of names in the order
/// they appear in the source. Bare identifiers come back unquoted;
/// `"quoted identifiers"` come back with their surrounding quotes
/// intact so the caller can tell them apart and match the same shapes
/// that `parseScope` accepts in FROM / JOIN / UPDATE / INTO clauses.
///
/// `public.users.id|`       → `['public', 'users']`
/// `u.|`                    → `['u']`
/// `"My Table".|`           → `['"My Table"']`
/// `schema."My Table".|`    → `['schema', '"My Table"']`
/// `id|`                    → `[]`
List<String> qualifierChainBefore(String text, int tokenStart) {
  if (tokenStart <= 0 || tokenStart > text.length) return const [];
  if (text.codeUnitAt(tokenStart - 1) != 0x2E /* . */ ) return const [];
  final parts = <String>[];
  var i = tokenStart - 1;
  while (i > 0 && text.codeUnitAt(i) == 0x2E) {
    final int segStart;
    if (text.codeUnitAt(i - 1) == 0x22 /* " */ ) {
      var q = i - 2;
      while (q >= 0 && text.codeUnitAt(q) != 0x22) {
        q--;
      }
      if (q < 0) break;
      segStart = q;
    } else {
      var j = i;
      while (j > 0 && isWordCode(text.codeUnitAt(j - 1))) {
        j--;
      }
      if (j == i) break;
      segStart = j;
    }
    parts.insert(0, text.substring(segStart, i));
    if (segStart == 0 || text.codeUnitAt(segStart - 1) != 0x2E) break;
    i = segStart - 1;
  }
  return parts;
}

/// Tokenizes [text] up to [upto] into bare words (original case), with
/// string literals and comments masked out first. The shared skeleton
/// reader for the clause and statement matchers.
List<String> scanWords(String text, int upto) {
  final clean = stripStringsAndComments(text, upto);
  return wordsIn(clean);
}

/// Splits already-stripped [clean] text into bare words (original case).
List<String> wordsIn(String clean) {
  final words = <String>[];
  var i = 0;
  while (i < clean.length) {
    if (isWordCode(clean.codeUnitAt(i))) {
      final start = i;
      while (i < clean.length && isWordCode(clean.codeUnitAt(i))) {
        i++;
      }
      words.add(clean.substring(start, i));
    } else {
      i++;
    }
  }
  return words;
}

/// Code unit of the last non-whitespace character in [clean], or 0 when
/// [clean] is blank. Lets the matchers tell `…(` / `…,` / `…)` apart.
int lastNonSpaceCode(String clean) {
  for (var i = clean.length - 1; i >= 0; i--) {
    final c = clean.codeUnitAt(i);
    if (!isSpaceCode(c)) return c;
  }
  return 0;
}

/// Net `(` minus `)` depth across [clean].
int parenDepth(String clean) {
  var depth = 0;
  for (var i = 0; i < clean.length; i++) {
    final c = clean.codeUnitAt(i);
    if (c == 0x28) {
      depth++;
    } else if (c == 0x29) {
      depth--;
    }
  }
  return depth;
}
