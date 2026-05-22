import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/cell_edit.dart';
import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import 'cell_content.dart';
import 'column_widths.dart';
import 'format_cache.dart';
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
    required this.rowWidth,
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
  final double rowWidth;
  final List<String> columns;
  final Map<String, DbColumn>? columnMeta;
  final ColumnWidths widths;
  final ValueListenable<GridSelection> selection;
  final CellEditValue? Function(int column) pendingFor;
  final FormatCache formatCache;

  @override
  Widget build(BuildContext context) {
    final colCount = columns.length;
    final cells = <Widget>[
      for (var c = 0; c < colCount; c++)
        _buildCell(c, c < values.length ? values[c] : null),
    ];

    return _RowHoverScope(
      builder: (_, hovering) => ValueListenableBuilder<GridSelection>(
        valueListenable: selection,
        builder: (_, sel, _) {
          final segments = sel.rowSegments(row);
          final hasSelection = segments.isNotEmpty;
          // Insert / delete row tints layer below the selection tint so a
          // selected pending-insert still reads as selected.
          final Color baseBg = isInsert
              ? AppColors.gridRowInsert
              : isDeleted
              ? AppColors.gridRowDelete
              : Colors.transparent;
          final Color hoverBg = hovering
              ? AppColors.gridRowHover
              : Colors.transparent;
          final Color selectionBg = hasSelection
              ? AppColors.gridRowSelection
              : Colors.transparent;
          final bg = Color.alphaBlend(
            selectionBg,
            Color.alphaBlend(hoverBg, baseBg),
          );

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
        },
      ),
    );
  }

  Widget _buildCell(int column, Object? original) {
    final pending = pendingFor(column);
    // Insert rows don't get the per-cell accent stripe — the whole row is
    // already accent-tinted, so per-cell highlighting becomes noise.
    final isEdited = pending != null && !isInsert;

    final content = Text.rich(
      gridCellSpan(
        pending: pending,
        isInsert: isInsert,
        sourceIdx: sourceIdx,
        column: column,
        original: original,
        formatCache: formatCache,
        dataType: columnMeta?[columns[column]]?.dataType,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    // Pointer handling and the hover expansion live at the body level — cells
    // reduce to a sized Container, which keeps the per-row widget allocation
    // small. See ResultsGrid._handleCellHover for the single hover overlay.
    // The right hairline draws the column separator (the header cells carry
    // the matching one); an edited cell adds the accent stripe on the left.
    final cell = Container(
      width: widths[column],
      height: kRowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: isEdited ? AppColors.accentSoft : null,
        border: Border(
          right: BorderSide(color: AppColors.hairline, width: 1),
          left: isEdited
              ? BorderSide(color: AppColors.accent, width: 2)
              : BorderSide.none,
        ),
      ),
      child: content,
    );
    // Dim deleted cells without losing legibility — pairs with the red row
    // tint + stripe for an unmistakable "going away" read.
    return isDeleted ? Opacity(opacity: 0.55, child: cell) : cell;
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
