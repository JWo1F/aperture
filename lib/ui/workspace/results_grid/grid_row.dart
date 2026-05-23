import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/cell_edit.dart';
import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import 'cell_content.dart';
import 'cell_style.dart';
import 'column_widths.dart';
import 'format_cache.dart';
import 'grid_cell.dart';
import 'grid_metrics.dart';
import 'grid_selection.dart';

/// One rendered grid row: the cell strip plus the selection / hover / row-state
/// overlays painted on top of it.
///
/// Cells are built once per row — their content doesn't depend on the
/// selection, so the selection ring + tint are drawn as `Positioned` overlays
/// at the row level rather than giving every cell its own listener.
class GridRow extends StatelessWidget {
  const GridRow({
    super.key,
    required this.row,
    required this.sourceIdx,
    required this.isInsert,
    required this.isDeleted,
    required this.values,
    required this.minRowWidth,
    required this.columns,
    required this.columnMeta,
    required this.widths,
    required this.selection,
    required this.pendingFor,
    required this.formatCache,
  });

  /// Slot index — addresses the selection and the focus cell.
  final int row;

  /// Source index — the result-row or insert index that keys [formatCache].
  final int sourceIdx;
  final bool isInsert;
  final bool isDeleted;

  /// Raw cell values; empty for pending-insert rows.
  final List<Object?> values;

  /// Lower bound for the row's painted width — typically the data area's
  /// viewport width, so when the columns don't fill it the row still draws
  /// its background and bottom hairline edge-to-edge.
  final double minRowWidth;
  final List<String> columns;
  final Map<String, DbColumn>? columnMeta;
  final ColumnWidths widths;
  final ValueListenable<GridSelection> selection;
  final CellEditValue? Function(int column) pendingFor;
  final FormatCache formatCache;

  @override
  Widget build(BuildContext context) {
    return _RowHoverScope(
      builder: (_, hovering) => ValueListenableBuilder<GridSelection>(
        valueListenable: selection,
        builder: (_, sel, _) => ListenableBuilder(
          // Subscribing at the row level means a column-resize tick rebuilds
          // each visible row's cell strip in place — no `ResultsGrid.setState`
          // and no `ListView.builder` re-walk above.
          listenable: widths,
          builder: (_, _) => _buildRow(hovering, sel),
        ),
      ),
    );
  }

  Widget _buildRow(bool hovering, GridSelection sel) {
    final colCount = columns.length;
    final cells = <Widget>[
      for (var c = 0; c < colCount; c++)
        _buildCell(c, c < values.length ? values[c] : null),
    ];

    final segments = sel.rowSegments(row);
    final hasSelection = segments.isNotEmpty;
    // Insert / delete row tints layer below the selection tint so a
    // selected pending-insert still reads as selected. The row paints
    // hover / selection / focus once at the row level (overlay below),
    // so [GridCell] is told not to repaint those — only the per-cell
    // edit decoration lives inside each cell.
    final bg = gridRowFill(
      isInsert: isInsert,
      isDeleted: isDeleted,
      isHovered: hovering,
      isRowSelected: hasSelection,
    );

    final rowWidth = math.max(widths.total, minRowWidth);
    final body = Container(
      width: rowWidth,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(children: cells),
    );

    // Insert / delete left stripe rides on top of the row content as a
    // Positioned overlay — a left BorderSide on the body would shrink
    // the row's inner width by 2px and the cells would overflow.
    final overlays = <Widget>[];
    if (isInsert || isDeleted) {
      overlays.add(
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 2,
          child: IgnorePointer(
            child: ColoredBox(
              color: isInsert ? AppColors.accent : AppColors.error,
            ),
          ),
        ),
      );
    }

    if (!hasSelection && overlays.isEmpty) return body;

    // Layer a tint over each contiguous selected column segment and, if
    // this row owns the focus cell, draw the indigo ring on top.
    for (final segment in segments) {
      final (sc0, sc1) = segment;
      final x = widths.offsetOf(sc0);
      var w = 0.0;
      for (var c = sc0; c <= sc1 && c < widths.length; c++) {
        w += widths[c];
      }
      overlays.add(
        Positioned(
          left: x,
          top: 0,
          width: w,
          height: kRowHeight,
          child: IgnorePointer(
            child: ColoredBox(color: AppColors.gridRowSelection),
          ),
        ),
      );
    }

    final focus = sel.focus;
    if (focus != null && focus.$1 == row && focus.$2 < widths.length) {
      overlays.add(
        Positioned(
          left: widths.offsetOf(focus.$2),
          top: 0,
          width: widths[focus.$2],
          height: kRowHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(children: [body, ...overlays]);
  }

  Widget _buildCell(int column, Object? original) {
    final pending = pendingFor(column);
    // Insert rows don't get the per-cell accent stripe — the whole row is
    // already accent-tinted, so per-cell highlighting becomes noise.
    final isEdited = pending != null && !isInsert;

    return GridCell(
      width: widths[column],
      isInsert: isInsert,
      isDeleted: isDeleted,
      isEdited: isEdited,
      content: gridCellSpan(
        pending: pending,
        isInsert: isInsert,
        sourceIdx: sourceIdx,
        column: column,
        original: original,
        formatCache: formatCache,
        dataType: columnMeta?[columns[column]]?.dataType,
      ),
    );
  }
}

/// Owns per-row hover state so it persists across the parent's rebuilds.
///
/// `MouseRegion` only fires `onEnter` when the pointer first crosses into the
/// widget's bounds. Holding the hover flag in a real [State] means selection
/// changes and `ValueListenableBuilder` updates inside the row all preserve
/// the hover indicator instead of flickering it off on the next pointer event.
class _RowHoverScope extends StatefulWidget {
  const _RowHoverScope({required this.builder});

  final Widget Function(BuildContext context, bool hovering) builder;

  @override
  State<_RowHoverScope> createState() => _RowHoverScopeState();
}

class _RowHoverScopeState extends State<_RowHoverScope> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!_hover) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: widget.builder(context, _hover),
    );
  }
}
