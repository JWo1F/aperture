/// One rectangular block of selected cells, stored in canonical form
/// (r0 ≤ r1, c0 ≤ c1) so callers don't have to normalize at every read.
class CellRange {
  const CellRange._(this.r0, this.c0, this.r1, this.c1);

  factory CellRange.of(int r0, int c0, int r1, int c1) => CellRange._(
    r0 < r1 ? r0 : r1,
    c0 < c1 ? c0 : c1,
    r0 > r1 ? r0 : r1,
    c0 > c1 ? c0 : c1,
  );

  final int r0, c0, r1, c1;

  bool contains(int r, int c) => r >= r0 && r <= r1 && c >= c0 && c <= c1;

  bool containsRow(int r) => r >= r0 && r <= r1;
}

/// Excel-style selection: a stack of ranges plus an anchor (the cell that
/// shift-extension grows from) and a focus (the active cell — the one
/// keyboard navigation, the cell picker, and the context menu act on).
class GridSelection {
  const GridSelection({this.ranges = const [], this.anchor, this.focus});

  static const empty = GridSelection();

  final List<CellRange> ranges;
  final (int, int)? anchor;
  final (int, int)? focus;

  bool get isEmpty => ranges.isEmpty;

  factory GridSelection.single(int row, int col) => GridSelection(
    ranges: [CellRange._(row, col, row, col)],
    anchor: (row, col),
    focus: (row, col),
  );

  bool contains(int row, int col) {
    for (final rg in ranges) {
      if (rg.contains(row, col)) return true;
    }
    return false;
  }

  /// Column intervals (c0, c1) that intersect [row]. Overlapping or
  /// adjacent intervals are merged so the row paints one continuous tint
  /// strip per visual block.
  List<(int, int)> rowSegments(int row) {
    final hits = <(int, int)>[];
    for (final rg in ranges) {
      if (rg.containsRow(row)) hits.add((rg.c0, rg.c1));
    }
    if (hits.length < 2) return hits;
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    var (lo, hi) = hits.first;
    for (var i = 1; i < hits.length; i++) {
      final (nlo, nhi) = hits[i];
      if (nlo <= hi + 1) {
        if (nhi > hi) hi = nhi;
      } else {
        merged.add((lo, hi));
        lo = nlo;
        hi = nhi;
      }
    }
    merged.add((lo, hi));
    return merged;
  }

  GridSelection addRange(int row, int col) => GridSelection(
    ranges: [...ranges, CellRange._(row, col, row, col)],
    anchor: (row, col),
    focus: (row, col),
  );

  /// Replace the last range with bbox((r0,c0), (r1,c1)). Anchor stays at
  /// (r0,c0); focus moves to the supplied [focus] (defaults to (r1,c1)).
  /// If there are no ranges yet, the bbox is added as the only range.
  GridSelection replaceLast(
    int r0,
    int c0,
    int r1,
    int c1, {
    (int, int)? focus,
  }) {
    final next = CellRange.of(r0, c0, r1, c1);
    final list = ranges.isEmpty
        ? [next]
        : [...ranges.sublist(0, ranges.length - 1), next];
    return GridSelection(
      ranges: list,
      anchor: (r0, c0),
      focus: focus ?? (r1, c1),
    );
  }
}
