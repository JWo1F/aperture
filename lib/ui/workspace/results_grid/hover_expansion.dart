import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../models/cell_edit.dart';
import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import 'cell_content.dart';
import 'column_widths.dart';
import 'format_cache.dart';
import 'grid_cell.dart';
import 'grid_metrics.dart';
import 'grid_selection.dart';
import 'grid_slots.dart';

/// Excel-style hover expansion — a single overlay owned by the grid. While
/// the pointer rests on a cell the grid draws an exact clone of it, grown
/// rightward over its neighbours so the full (≤1024-char) value fits on one
/// line. The clone carries the cell's own selection / focus / edit / row
/// state so it reads as the cell itself widening, not a floating overlay.
/// One pointer-driven overlay (vs. a per-cell Tooltip, each of which spun up
/// an AnimationController on build) keeps scroll frames free of that churn.
class HoverExpansion {
  HoverExpansion();

  final OverlayPortalController controller = OverlayPortalController();

  /// Cell currently under the pointer, or null. A [ValueNotifier] so the
  /// overlay child rebuilds on hover changes without rebuilding the grid.
  final ValueNotifier<(int, int)?> hoverCell = ValueNotifier(null);

  void dispose() {
    hoverCell.dispose();
  }

  /// Pointer moved within the grid body — point the expansion at the cell
  /// now under the cursor, or hide it on a miss. Re-entering the same cell
  /// is a cheap no-op so ordinary mouse movement does no work.
  void update((int, int)? cell) {
    if (cell == hoverCell.value) return;
    hoverCell.value = cell;
    if (cell == null) {
      controller.hide();
    } else if (!controller.isShowing) {
      controller.show();
    }
  }

  void dismiss() {
    hoverCell.value = null;
    if (controller.isShowing) controller.hide();
  }

  /// The overlay child. Rebuilds on hover changes and on [selection] changes
  /// so a click that selects the hovered cell repaints the expansion in its
  /// new selected state. [contextFactory] returns the per-frame snapshot of
  /// grid state needed to draw the clone, or null when no body context has
  /// rendered yet.
  Widget buildOverlay({
    required ValueListenable<GridSelection> selection,
    required ExpansionContext? Function() contextFactory,
  }) {
    return ValueListenableBuilder<(int, int)?>(
      valueListenable: hoverCell,
      builder: (context, cell, _) {
        final ctx = contextFactory();
        if (cell == null || ctx == null) return const SizedBox.shrink();
        return ValueListenableBuilder<GridSelection>(
          valueListenable: selection,
          builder: (context, sel, _) => buildExpansionCell(
            ctx,
            cell.$1,
            cell.$2,
            sel,
          ),
        );
      },
    );
  }
}

/// Per-frame inputs the expansion overlay needs to render a cell clone in the
/// same visual state as its source cell.
class ExpansionContext {
  ExpansionContext({
    required this.bodyCtx,
    required this.slots,
    required this.widths,
    required this.formatCache,
    required this.columns,
    required this.columnMeta,
    required this.deletedRows,
    required this.inserts,
    required this.edits,
    required this.rows,
    required this.vBody,
    required this.hBody,
  });

  final BuildContext bodyCtx;
  final List<Slot> slots;
  final ColumnWidths widths;
  final FormatCache formatCache;
  final List<String> columns;
  final Map<String, DbColumn>? columnMeta;
  final Set<int>? deletedRows;
  final List<PendingInsert>? inserts;
  final Map<CellEdit, CellEditValue>? edits;
  final List<List<Object?>> rows;
  final ScrollController vBody;
  final ScrollController hBody;

  bool isDeletedRow(int row) {
    final slot = slots[row];
    if (slot.isInsert) return false;
    return deletedRows?.contains(slot.sourceIdx) ?? false;
  }

  CellEditValue? pendingFor(int row, int column) {
    final slot = slots[row];
    if (slot.isInsert) {
      if (inserts == null || slot.sourceIdx >= inserts!.length) return null;
      return inserts![slot.sourceIdx].values[columns[column]];
    }
    return edits?[CellEdit(slot.sourceIdx, column)];
  }

  Object? originalAt(int row, int column) {
    final slot = slots[row];
    return slot.isInsert ? null : rows[slot.sourceIdx][column];
  }

  Rect cellRect(int row, int col) {
    final box = bodyCtx.findRenderObject();
    if (box is! RenderBox) return Rect.zero;
    final origin = box.localToGlobal(Offset.zero);
    final contentX = widths.offsetOf(col);
    final viewportY =
        row * kRowHeight - (vBody.hasClients ? vBody.offset : 0);
    return Rect.fromLTWH(
      origin.dx + contentX,
      origin.dy + viewportY,
      widths[col],
      kRowHeight,
    );
  }
}

/// An exact clone of the hovered cell, grown rightward so its full value
/// fits on one line. Width spans from the value's natural width (min: the
/// column) up to the data viewport's right edge. The visual contract —
/// row-fill blend, edit decoration, focus ring, deleted-row dimming — is
/// shared with [GridRow] through [GridCell].
Widget buildExpansionCell(
  ExpansionContext ctx,
  int row,
  int column,
  GridSelection sel,
) {
  final rect = ctx.cellRect(row, column);
  final colWidth = ctx.widths[column];
  // Cap: the distance from the cell's left edge to the viewport's right.
  final double maxWidth;
  if (ctx.hBody.hasClients) {
    final toRight = ctx.hBody.position.viewportDimension -
        ctx.widths.offsetOf(column) +
        ctx.hBody.offset;
    maxWidth = math.max(toRight, colWidth);
  } else {
    maxWidth = colWidth;
  }

  final slot = ctx.slots[row];
  final isInsert = slot.isInsert;
  final isDeleted = ctx.isDeletedRow(row);
  final pending = ctx.pendingFor(row, column);

  return Positioned(
    left: rect.left,
    top: rect.top,
    child: IgnorePointer(
      child: GridCell(
        width: colWidth,
        maxWidth: maxWidth,
        isInsert: isInsert,
        isDeleted: isDeleted,
        isEdited: pending != null && !isInsert,
        // The expansion is standalone — it paints the row's hover/selection
        // tints itself (hovered by definition) and pre-blends them over an
        // opaque grid bg so they don't vanish into whatever sits behind.
        isHovered: true,
        isRowSelected: sel.rowSegments(row).isNotEmpty,
        isSelected: sel.contains(row, column),
        isFocus: sel.focus == (row, column),
        backdrop: AppColors.gridRowBg,
        bottomBorder: true,
        content: gridCellSpan(
          pending: pending,
          isInsert: isInsert,
          sourceIdx: slot.sourceIdx,
          column: column,
          original: ctx.originalAt(row, column),
          formatCache: ctx.formatCache,
          dataType: ctx.columnMeta?[ctx.columns[column]]?.dataType,
          maxChars: kExpandedMaxChars,
        ),
      ),
    ),
  );
}
