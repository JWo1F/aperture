import 'package:flutter/material.dart';

import '../../../models/db_object.dart';
import '../../../models/order_term.dart';
import '../../../theme/app_theme.dart';
import 'column_widths.dart';
import 'grid_metrics.dart';
import 'header_cell.dart';

/// The full results-grid header row: pinned `#` index header plus the
/// horizontally scrolling cells header. The body owns the horizontal
/// scroll controller; this widget mirrors its offset through an
/// [AnimatedBuilder] so each gesture frame lines up with the cells below.
class HeaderStrip extends StatelessWidget {
  const HeaderStrip({
    super.key,
    required this.columns,
    required this.widths,
    required this.hBody,
    required this.columnMeta,
    required this.foreignKeys,
    required this.order,
    required this.onSortColumn,
    required this.savedWidths,
    required this.onWidthChanged,
  });

  final List<String> columns;
  final ColumnWidths widths;
  final ScrollController hBody;
  final Map<String, DbColumn>? columnMeta;
  final Map<String, DbForeignKey>? foreignKeys;
  final List<OrderTerm>? order;
  final void Function(String column)? onSortColumn;
  final Map<String, double>? savedWidths;
  final void Function(String column, double width)? onWidthChanged;

  OrderTerm? _sortFor(String column) {
    for (final term in order ?? const <OrderTerm>[]) {
      if (term.column == column) return term;
    }
    return null;
  }

  int _sortPriority(String column) {
    final terms = order ?? const <OrderTerm>[];
    if (terms.length < 2) return 0;
    final index = terms.indexWhere((t) => t.column == column);
    return index == -1 ? 0 : index + 1;
  }

  @override
  Widget build(BuildContext context) {
    // The header subscribes directly to [widths] — a resize tick rebuilds the
    // header strip (its `SizedBox` width + each `HeaderCell.width`) without
    // touching the body subtree below.
    final dataHeaderRow = ListenableBuilder(
      listenable: widths,
      builder: (_, _) => SizedBox(
        width: widths.total,
        child: Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              HeaderCell(
                label: columns[i],
                width: widths[i],
                sort: _sortFor(columns[i]),
                sortPriority: _sortPriority(columns[i]),
                meta: columnMeta?[columns[i]],
                foreignKey: foreignKeys?[columns[i]],
                onSort: onSortColumn == null
                    ? null
                    : () => onSortColumn!(columns[i]),
                onResize: (delta) {
                  widths.resize(i, delta);
                  final w = widths[i];
                  savedWidths?[columns[i]] = w;
                  onWidthChanged?.call(columns[i], w);
                },
              ),
          ],
        ),
      ),
    );

    final indexHeader = Container(
      width: kIndexWidth,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(
          right: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Text('#', style: AppTheme.mono(size: 10, color: AppColors.text4)),
    );

    // RepaintBoundary isolates the header's pixels from the body's, so a
    // header repaint (sort indicator, resize-handle hover) doesn't
    // invalidate the cells layer underneath.
    return RepaintBoundary(
      child: SizedBox(
        height: 28,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            indexHeader,
            Expanded(
              // Border sits in the foreground: each HeaderCell paints an
              // opaque bgDeep fill over the full 28px height, so a
              // background-position border would be hidden behind the cells.
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: ColoredBox(
                  color: AppColors.bgDeep,
                  // ClipRect alone would force the header row to fit the
                  // viewport. OverflowBox grants it the same unbounded
                  // horizontal space the body's scroll view has, so the Row
                  // lays out at `dataWidth` and we translate it sideways to
                  // mirror the body's scroll offset.
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: hBody,
                      builder: (_, child) {
                        final offset = hBody.hasClients ? hBody.offset : 0.0;
                        return OverflowBox(
                          minWidth: 0,
                          maxWidth: double.infinity,
                          alignment: Alignment.topLeft,
                          child: Transform.translate(
                            offset: Offset(-offset, 0),
                            child: child,
                          ),
                        );
                      },
                      child: dataHeaderRow,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
