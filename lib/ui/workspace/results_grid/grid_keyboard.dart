import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../models/cell_edit.dart';
import '../../../models/value_format.dart';
import 'cell_interaction.dart';
import 'column_widths.dart';
import 'grid_metrics.dart';
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
    final isCopyChord = key == LogicalKeyboardKey.keyC &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (isCopyChord && !selection.value.isEmpty) {
      final sel = selection.value;
      final singleCell = sel.ranges.length == 1 &&
          sel.ranges.first.r0 == sel.ranges.first.r1 &&
          sel.ranges.first.c0 == sel.ranges.first.c1;
      final text = singleCell
          ? _selectedCellText()
          : selectionToTsv(sel, _cellTextAt);
      Clipboard.setData(ClipboardData(text: text));
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
