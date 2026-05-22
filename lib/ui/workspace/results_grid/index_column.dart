import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'grid_metrics.dart';
import 'grid_selection.dart';
import 'grid_slots.dart';

/// The pinned left rail of row numbers. It tracks vertical scroll through
/// [controller] (a follower the grid mirrors against the body) but never
/// moves horizontally with the data area.
class IndexColumn extends StatelessWidget {
  const IndexColumn({
    super.key,
    required this.controller,
    required this.slots,
    required this.deletedRows,
    required this.selection,
  });

  final ScrollController controller;
  final List<Slot> slots;
  final Set<int>? deletedRows;
  final ValueListenable<GridSelection> selection;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kIndexWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: ScrollConfiguration(
          // Hide the system scrollbar — the index column piggybacks on the
          // data area's vertical scrollbar.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView.builder(
            controller: controller,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: slots.length,
            itemExtent: kRowHeight,
            addAutomaticKeepAlives: false,
            itemBuilder: (_, r) {
              final slot = slots[r];
              return _IndexCell(
                row: r,
                selection: selection,
                isInsert: slot.isInsert,
                isDeleted: !slot.isInsert &&
                    (deletedRows?.contains(slot.sourceIdx) ?? false),
                label: slot.isInsert ? '+' : '${slot.sourceIdx + 1}',
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One cell in the row-number rail. Rebuilds only when the selection touches
/// this row — most scroll ticks leave it untouched.
class _IndexCell extends StatelessWidget {
  const _IndexCell({
    required this.row,
    required this.selection,
    required this.label,
    this.isInsert = false,
    this.isDeleted = false,
  });

  final int row;
  final ValueListenable<GridSelection> selection;
  final bool isInsert;
  final bool isDeleted;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GridSelection>(
      valueListenable: selection,
      builder: (_, sel, _) {
        final hasSelection = sel.rowSegments(row).isNotEmpty;
        final Color color = isInsert
            ? AppColors.accent
            : isDeleted
            ? AppColors.error
            : hasSelection
            ? AppColors.accent
            : AppColors.text4;
        final FontWeight weight = (isInsert || isDeleted || hasSelection)
            ? FontWeight.w600
            : FontWeight.w400;
        return SizedBox(
          height: kRowHeight,
          child: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
            child: Text(
              label,
              style: AppTheme.mono(size: 10, color: color, weight: weight),
            ),
          ),
        );
      },
    );
  }
}
