import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../models/cell_edit.dart';
import '../../../models/value_format.dart';
import 'cell_interaction.dart';
import 'column_widths.dart';
import 'grid_metrics.dart';
import 'grid_selection.dart';
import 'grid_slots.dart';
import 'results_grid.dart';
import 'selection_controller.dart';
import 'tsv.dart';

/// Mutable bundle of grid state the keyboard handler reaches into. Holds
/// references to the controllers, the slot map, the result columns/rows, and
/// the cell picker dispatcher so the handler doesn't carry the dependency
/// graph of `_ResultsGridState`.
class GridKeyboard {
  GridKeyboard({
    required this.widget,
    required this.selection,
    required this.widths,
    required this.slots,
    required this.vBody,
    required this.hBody,
    required this.interaction,
    required this.bodyCtxOf,
  });

  final ResultsGrid widget;
  final SelectionController selection;
  final ColumnWidths widths;
  List<Slot> slots;
  final ScrollController vBody;
  final ScrollController hBody;
  final CellInteraction interaction;
  final BuildContext? Function() bodyCtxOf;

  int? get _selRow => selection.value.focus?.$1;
  int? get _selCol => selection.value.focus?.$2;
  int get _totalRowCount => slots.length;

  Object? _originalAt(int row, int column) {
    final slot = slots[row];
    return slot.isInsert ? null : widget.result.rows[slot.sourceIdx][column];
  }

  /// Textual form of the focus cell — pending edit wins over the original,
  /// mirroring what's painted in the grid.
  String _selectedCellText() {
    final focus = selection.value.focus!;
    return _cellTextAt(focus.$1, focus.$2);
  }

  String _cellTextAt(int row, int column) {
    final pending = interaction.pendingFor(row, column);
    if (pending is CellLiteral) return pending.value ?? 'NULL';
    if (pending is CellDefault) return 'DEFAULT';
    final slot = slots[row];
    if (slot.isInsert) return 'NULL';
    return formatCellValue(widget.result.rows[slot.sourceIdx][column]) ??
        'NULL';
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (selection.value.isEmpty) return KeyEventResult.ignored;
      selection.clear();
      return KeyEventResult.handled;
    }
    final cmd = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (cmd && key == LogicalKeyboardKey.keyC && !selection.value.isEmpty) {
      final sel = selection.value;
      final text = _isSingleCell(sel)
          ? _selectedCellText()
          : selectionToTsv(sel, _cellTextAt);
      Clipboard.setData(ClipboardData(text: text));
      return KeyEventResult.handled;
    }
    if (cmd &&
        key == LogicalKeyboardKey.keyV &&
        widget.editable &&
        widget.onEditCell != null &&
        !selection.value.isEmpty) {
      final sel = selection.value;
      final anchor = _selectionTopLeft(sel);
      _pasteFromClipboard(anchor.$1, anchor.$2, single: _isSingleCell(sel));
      return KeyEventResult.handled;
    }

    final moved = selection.moveBy(
      key,
      rows: _totalRowCount,
      cols: widget.result.columns.length,
    );
    if (moved != null) {
      _scrollToCell(moved.$1, moved.$2);
      return KeyEventResult.handled;
    }

    final bodyCtx = bodyCtxOf();
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.f2) &&
        widget.editable &&
        widget.onEditCell != null &&
        _selRow != null &&
        _selCol != null &&
        bodyCtx != null) {
      interaction.openCellPicker(
        bodyCtx,
        _selRow!,
        _selCol!,
        _originalAt(_selRow!, _selCol!),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isSingleCell(GridSelection sel) =>
      sel.ranges.length == 1 &&
      sel.ranges.first.r0 == sel.ranges.first.r1 &&
      sel.ranges.first.c0 == sel.ranges.first.c1;

  (int, int) _selectionTopLeft(GridSelection sel) {
    var minR = sel.ranges.first.r0;
    var minC = sel.ranges.first.c0;
    for (final rg in sel.ranges) {
      if (rg.r0 < minR) minR = rg.r0;
      if (rg.c0 < minC) minC = rg.c0;
    }
    return (minR, minC);
  }

  /// Clipboard read is async — we capture the anchor at keypress time and
  /// apply the edits once the platform clipboard returns. Cells outside the
  /// current grid or marked for delete are skipped silently; the rest paste.
  Future<void> _pasteFromClipboard(
    int anchorRow,
    int anchorCol, {
    required bool single,
  }) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (single) {
      _pasteCell(anchorRow, anchorCol, text);
      return;
    }
    final grid = parseTsv(text);
    for (var r = 0; r < grid.length; r++) {
      final cells = grid[r];
      for (var c = 0; c < cells.length; c++) {
        _pasteCell(anchorRow + r, anchorCol + c, cells[c]);
      }
    }
  }

  void _pasteCell(int row, int col, String text) {
    if (row < 0 || row >= slots.length) return;
    if (col < 0 || col >= widget.result.columns.length) return;
    if (interaction.isDeletedRow(row)) return;
    widget.onEditCell!(
      interaction.stateRowFor(row),
      col,
      CellLiteral(text),
    );
  }

  /// Nudge the body scrollers so the cell sits inside the viewport. We
  /// scroll only when the cell is off-screen — no jitter on every arrow.
  void _scrollToCell(int row, int col) {
    if (vBody.hasClients) {
      final top = row * kRowHeight;
      final bottom = top + kRowHeight;
      final viewport = vBody.position.viewportDimension;
      final offset = vBody.offset;
      if (top < offset) {
        vBody.jumpTo(top);
      } else if (bottom > offset + viewport) {
        vBody.jumpTo(bottom - viewport);
      }
    }
    if (hBody.hasClients) {
      final left = widths.offsetOf(col);
      final right = left + widths[col];
      final viewport = hBody.position.viewportDimension;
      final offset = hBody.offset;
      if (left < offset) {
        hBody.jumpTo(math.max(0, left));
      } else if (right > offset + viewport) {
        hBody.jumpTo(right - viewport);
      }
    }
  }
}
