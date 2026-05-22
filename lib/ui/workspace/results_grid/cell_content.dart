import 'package:flutter/widgets.dart';

import '../../../models/cell_edit.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/code_theme.dart';
import 'cell_style.dart';
import 'format_cache.dart';
import 'grid_metrics.dart';

/// Character cap for the hover expansion. Wider than the grid cell's
/// [kCellMaxChars] — the expansion is a single transient widget, not text
/// shaped on every scroll frame, so it can afford to render far more.
const int kExpandedMaxChars = 1024;

/// The styled text span painted inside one grid cell.
///
/// Plain values, NULL, DEFAULT and highlighted JSON all collapse to a single
/// [InlineSpan] so the grid cell, the off-screen width measurer and the
/// hover-expansion overlay all render the cell from one source of truth.
///
/// [maxChars] caps the rendered value. The grid cell passes [kCellMaxChars]
/// and reuses the [formatCache]'s memoised truncation + JSON highlight; the
/// expansion passes [kExpandedMaxChars] and truncates / highlights fresh,
/// since the cache is sized for the narrower cell.
InlineSpan gridCellSpan({
  required CellEditValue? pending,
  required bool isInsert,
  required int sourceIdx,
  required int column,
  required Object? original,
  required FormatCache formatCache,
  required String? dataType,
  int maxChars = kCellMaxChars,
}) {
  final isEdited = pending != null && !isInsert;

  if (pending is CellDefault) {
    return TextSpan(
      text: 'DEFAULT',
      style: gridCellStyle.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // Pending edits (raw user-typed strings) bypass the cache — they can change
  // on every keystroke. Original values flow through the cache.
  final bool fromPending = pending is CellLiteral;
  final String? displayValue = fromPending
      ? pending.value
      : formatCache.format(sourceIdx, column, original);

  if (displayValue == null) {
    return TextSpan(text: 'NULL', style: gridNullStyle);
  }

  // The grid cell reuses the cache's 256-char memoised forms; the wider
  // expansion truncates straight off the full value.
  final bool cellCap = maxChars <= kCellMaxChars;
  final String display = cellCap
      ? (fromPending
            ? truncateForCell(displayValue)
            : formatCache.displayText(sourceIdx, column, original)!)
      : truncateSingleLine(displayValue, maxChars);

  if (!isEdited && (original is Map || original is List)) {
    final spans = cellCap
        ? formatCache.spans(sourceIdx, column, display)
        : jsonSpans(display, gridCellStyle);
    return TextSpan(children: spans);
  }

  return TextSpan(
    text: display,
    style: gridCellStyle.copyWith(
      color: isEdited
          ? AppColors.textPrimary
          : cellColor(original, dataType: dataType),
    ),
  );
}
