import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'grid_selection.dart';

/// Mutable owner of the grid's [GridSelection] plus the in-progress drag
/// anchor. A [ValueNotifier] so a selection change rebuilds only the visible
/// rows that observe it, not the whole grid.
class SelectionController extends ValueNotifier<GridSelection> {
  SelectionController() : super(GridSelection.empty);

  /// The cell where a pointer drag went down. While non-null, every
  /// [extendDrag] grows the last range from this point.
  ({int row, int col})? _drag;

  bool get isDragging => _drag != null;

  void selectCell(int row, int column) {
    value = GridSelection.single(row, column);
  }

  /// Begin (or extend) a selection at the pointer-down cell. Shift extends
  /// the last range from the anchor; Cmd/Ctrl adds a disjoint range.
  void beginPointer(int row, int column) {
    final cmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final current = value;

    if (shift && current.anchor != null) {
      final a = current.anchor!;
      value =
          current.replaceLast(a.$1, a.$2, row, column, focus: (row, column));
      _drag = (row: a.$1, col: a.$2);
    } else if (cmd && !current.isEmpty) {
      value = current.addRange(row, column);
      _drag = (row: row, col: column);
    } else {
      value = GridSelection.single(row, column);
      _drag = (row: row, col: column);
    }
  }

  /// Extend the last range from the drag anchor to (row, column).
  void extendDrag(int row, int column) {
    final d = _drag;
    if (d == null) return;
    value = value.replaceLast(d.row, d.col, row, column, focus: (row, column));
  }

  void endDrag() => _drag = null;

  void clear() {
    if (value.isEmpty) return;
    value = GridSelection.empty;
  }

  /// Clears the selection and any in-progress drag — used when a fresh
  /// result page replaces the current one.
  void reset() {
    value = GridSelection.empty;
    _drag = null;
  }

  /// Moves the focus cell for an arrow / Home / End / PageUp / PageDown key,
  /// clamped to the [rows] × [cols] grid. Returns the new focus cell, or null
  /// when [key] isn't a navigation key. With no selection, any arrow lands on
  /// (0, 0). Holding Shift extends the last range from the anchor.
  (int, int)? moveBy(
    LogicalKeyboardKey key, {
    required int rows,
    required int cols,
    int pageJump = 20,
  }) {
    if (rows == 0 || cols == 0) return null;

    int? r = value.focus?.$1;
    int? c = value.focus?.$2;
    if (key == LogicalKeyboardKey.arrowUp) {
      r = r == null ? 0 : (r - 1).clamp(0, rows - 1);
      c = c ?? 0;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      r = r == null ? 0 : (r + 1).clamp(0, rows - 1);
      c = c ?? 0;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      c = c == null ? 0 : (c - 1).clamp(0, cols - 1);
      r = r ?? 0;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      c = c == null ? 0 : (c + 1).clamp(0, cols - 1);
      r = r ?? 0;
    } else if (key == LogicalKeyboardKey.home) {
      r = r ?? 0;
      c = 0;
    } else if (key == LogicalKeyboardKey.end) {
      r = r ?? 0;
      c = cols - 1;
    } else if (key == LogicalKeyboardKey.pageUp) {
      r = r == null ? 0 : (r - pageJump).clamp(0, rows - 1);
      c = c ?? 0;
    } else if (key == LogicalKeyboardKey.pageDown) {
      r = r == null ? 0 : (r + pageJump).clamp(0, rows - 1);
      c = c ?? 0;
    } else {
      return null;
    }

    final shift = HardwareKeyboard.instance.isShiftPressed;
    final anchor = value.anchor;
    if (shift && anchor != null) {
      value = value.replaceLast(anchor.$1, anchor.$2, r, c, focus: (r, c));
    } else {
      value = GridSelection.single(r, c);
    }
    return (r, c);
  }
}
