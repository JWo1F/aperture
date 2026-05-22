import 'package:flutter/widgets.dart';

import '../../../theme/app_theme.dart';

/// Type-aware foreground colour for a cell value. The runtime value class
/// decides first; for nulls and plain strings the catalog [dataType] is the
/// only signal, so it acts as the fallback.
Color cellColor(Object? value, {String? dataType}) {
  if (value == null) return AppColors.tNull;
  if (value is bool) return value ? AppColors.tBool : AppColors.textMuted;
  if (value is num || value is BigInt) return AppColors.tNum;
  if (value is DateTime) return AppColors.tDate;
  if (value is Map || value is List) return AppColors.tJson;
  final dt = dataType?.toLowerCase() ?? '';
  if (dt.contains('uuid')) return AppColors.tUuid;
  if (dt.contains('date') || dt.contains('time') || dt.contains('stamp')) {
    return AppColors.tDate;
  }
  if (dt.contains('json')) return AppColors.tJson;
  return AppColors.tStr;
}

/// Whether a cell's full value is worth a hover tooltip — structured values
/// always are, plain text only once it's long enough to be ellipsized.
bool wantsTooltip(Object? original, String text) {
  if (original is Map || original is List) return true;
  return text.length > 36;
}

const int _tooltipMaxChars = 512;
const int _cellMaxChars = 256;

/// Cuts [text] to a single line capped at [cap] characters, appending an
/// ellipsis when anything was dropped. Stops at the first newline so a
/// multi-line value collapses to its first line.
String _truncateSingleLine(String text, int cap) {
  final firstNewline = text.indexOf('\n');
  final hardCap = firstNewline >= 0 && firstNewline < cap ? firstNewline : cap;
  if (text.length <= hardCap && firstNewline < 0) return text;
  return '${text.substring(0, hardCap).trimRight()}…';
}

/// Caps tooltip text at the first newline or [_tooltipMaxChars], whichever
/// comes first — a tooltip is a peek, not a viewer.
String truncateForTooltip(String text) =>
    _truncateSingleLine(text, _tooltipMaxChars);

/// Single-line, length-capped form of a cell value for grid rendering. The
/// grid only ever paints one ellipsized line, so handing `Text` a
/// multi-kilobyte value forces the layout engine to shape thousands of
/// glyphs that get clipped anyway — the dominant cost of a scroll frame.
String truncateForCell(String text) =>
    _truncateSingleLine(text, _cellMaxChars);
