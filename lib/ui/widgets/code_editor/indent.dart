import 'package:flutter/services.dart' show TextSelection;

/// Soft-tab width — Tab inserts this, Enter copies it, Shift-Tab strips it.
const String indentUnit = '  ';

/// New text + selection produced by a pure indent operation.
typedef EditResult = ({String text, TextSelection selection});

/// First word-character offset preceding [cursor], inclusive. A word char
/// is `[A-Za-z0-9_]`. With no word chars behind the caret returns [cursor].
int tokenStart(String text, int cursor) {
  var i = cursor;
  while (i > 0 && _isWord(text.codeUnitAt(i - 1))) {
    i--;
  }
  return i;
}

bool _isWord(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F; // _

/// Tab / Shift-Tab handling. A plain caret or single-line selection gets
/// a soft tab inserted; a selection spanning lines (or any Shift-Tab)
/// shifts every touched line by one [indentUnit].
EditResult handleTab({
  required String text,
  required TextSelection selection,
  required bool dedent,
}) {
  if (!selection.isValid) return (text: text, selection: selection);
  final start = selection.start;
  final end = selection.end;

  if (!dedent && !text.substring(start, end).contains('\n')) {
    return (
      text: text.replaceRange(start, end, indentUnit),
      selection: TextSelection.collapsed(offset: start + indentUnit.length),
    );
  }
  return shiftLines(
    text: text,
    selStart: start,
    selEnd: end,
    dedent: dedent,
  );
}

/// Indents or dedents every line touched by [selStart]..[selEnd], keeping
/// the selection over the same span of lines. Returns the original
/// `(text, selection)` unchanged if a dedent has nothing to strip.
EditResult shiftLines({
  required String text,
  required int selStart,
  required int selEnd,
  required bool dedent,
}) {
  final firstLineStart =
      selStart == 0 ? 0 : text.lastIndexOf('\n', selStart - 1) + 1;
  // Modern-editor convention: a selection that ends *at* the offset
  // immediately after a '\n' is treated as "the caret sits at the start
  // of the next line but hasn't entered it" — so the next line is NOT
  // pulled into the shift. Only a selection that reaches strictly past
  // that boundary (≥ 1 char into the next line) includes it. Walking
  // scanEnd back by one when it lands on '\n' implements both cases.
  var scanEnd = selEnd;
  if (scanEnd > selStart && text.codeUnitAt(scanEnd - 1) == 0x0A) {
    scanEnd -= 1;
  }
  var lastLineEnd = text.indexOf('\n', scanEnd);
  if (lastLineEnd < 0) lastLineEnd = text.length;

  final lines = text.substring(firstLineStart, lastLineEnd).split('\n');
  final out = <String>[];
  var firstDelta = 0;
  var totalDelta = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (dedent) {
      var remove = 0;
      while (remove < indentUnit.length &&
          remove < line.length &&
          line.codeUnitAt(remove) == 0x20) {
        remove++;
      }
      if (remove == 0 && line.isNotEmpty && line.codeUnitAt(0) == 0x09) {
        remove = 1; // strip a hard tab if that's the leading char
      }
      out.add(line.substring(remove));
      if (i == 0) firstDelta = -remove;
      totalDelta -= remove;
    } else {
      out.add('$indentUnit$line');
      if (i == 0) firstDelta = indentUnit.length;
      totalDelta += indentUnit.length;
    }
  }

  final newText =
      text.substring(0, firstLineStart) +
      out.join('\n') +
      text.substring(lastLineEnd);
  if (newText == text) {
    return (
      text: text,
      selection: TextSelection(baseOffset: selStart, extentOffset: selEnd),
    );
  }

  final newStart = (selStart + firstDelta).clamp(
    firstLineStart,
    newText.length,
  );
  final newEnd = (selEnd + totalDelta).clamp(newStart, newText.length);
  return (
    text: newText,
    selection: TextSelection(baseOffset: newStart, extentOffset: newEnd),
  );
}

/// Enter in the multi-line editor — inserts a newline followed by the
/// current line's leading whitespace so indentation carries down.
EditResult handleNewlineInsert({
  required String text,
  required TextSelection selection,
}) {
  if (!selection.isValid) return (text: text, selection: selection);
  final start = selection.start;
  final lineStart =
      start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  var i = lineStart;
  while (i < start) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) break;
    i++;
  }
  final insert = '\n${text.substring(lineStart, i)}';
  return (
    text: text.replaceRange(start, selection.end, insert),
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}
