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
