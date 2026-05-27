import 'grid_selection.dart';

/// Excel-style TSV of [selection]: tabs between columns, newlines between
/// rows. A single rect is emitted as-is. Multiple disjoint rects are
/// projected into their bounding box, leaving blank cells where nothing is
/// selected. Tabs / newlines / quotes inside values are wrapped in `"…"` with
/// internal `"` doubled — the convention Excel and Sheets use for clipboard
/// TSV. [cellText] resolves the displayed text of a cell.
String selectionToTsv(
  GridSelection selection,
  String Function(int row, int col) cellText,
) {
  if (selection.isEmpty) return '';

  final ranges = selection.ranges;
  var minR = ranges.first.r0, maxR = ranges.first.r1;
  var minC = ranges.first.c0, maxC = ranges.first.c1;
  for (final rg in ranges) {
    if (rg.r0 < minR) minR = rg.r0;
    if (rg.r1 > maxR) maxR = rg.r1;
    if (rg.c0 < minC) minC = rg.c0;
    if (rg.c1 > maxC) maxC = rg.c1;
  }

  final out = StringBuffer();
  for (var r = minR; r <= maxR; r++) {
    for (var c = minC; c <= maxC; c++) {
      if (c > minC) out.write('\t');
      if (selection.contains(r, c)) out.write(_quote(cellText(r, c)));
    }
    if (r < maxR) out.write('\n');
  }
  return out.toString();
}

String _quote(String s) {
  if (s.contains('\t') || s.contains('\n') || s.contains('"')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Parse Excel-style TSV back into a 2D grid of strings. Tabs separate cells;
/// `\n` (or `\r\n`) separates rows. A cell that begins with `"` is treated as
/// a quoted cell: tabs and newlines inside are literal characters, and `""`
/// becomes a single `"`. A trailing newline is dropped so a round-tripped
/// selection doesn't grow a phantom empty row.
List<List<String>> parseTsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var cellStart = true;

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
      continue;
    }
    if (ch == '"' && cellStart) {
      inQuotes = true;
      cellStart = false;
    } else if (ch == '\t') {
      row.add(buf.toString());
      buf.clear();
      cellStart = true;
    } else if (ch == '\n') {
      row.add(buf.toString());
      buf.clear();
      rows.add(row);
      row = <String>[];
      cellStart = true;
    } else if (ch == '\r') {
      // Swallow the CR — the following LF (or EOF) commits the row.
    } else {
      buf.write(ch);
      cellStart = false;
    }
  }

  if (buf.isNotEmpty || row.isNotEmpty || inQuotes) {
    row.add(buf.toString());
    rows.add(row);
  }

  return rows;
}
