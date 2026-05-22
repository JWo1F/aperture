import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Translucent row-state overlay blended in this order: insert/delete base,
/// then hover, then selection. Returns a partially-transparent colour so the
/// caller can either paint it over the (transparent) grid background as the
/// row does, or pre-blend it over an opaque backdrop as the hover expansion
/// does for its standalone overlay.
Color gridRowFill({
  required bool isInsert,
  required bool isDeleted,
  required bool isHovered,
  required bool isRowSelected,
}) {
  final Color baseBg = isInsert
      ? AppColors.gridRowInsert
      : isDeleted
      ? AppColors.gridRowDelete
      : Colors.transparent;
  final Color hoverBg = isHovered
      ? AppColors.gridRowHover
      : Colors.transparent;
  final Color selectionBg = isRowSelected
      ? AppColors.gridRowSelection
      : Colors.transparent;
  return Color.alphaBlend(
    selectionBg,
    Color.alphaBlend(hoverBg, baseBg),
  );
}

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

const int kCellMaxChars = 256;

/// Cuts [text] to a single line capped at [cap] characters, appending an
/// ellipsis when anything was dropped. Stops at the first newline so a
/// multi-line value collapses to its first line.
String truncateSingleLine(String text, int cap) {
  final firstNewline = text.indexOf('\n');
  final hardCap = firstNewline >= 0 && firstNewline < cap ? firstNewline : cap;
  if (text.length <= hardCap && firstNewline < 0) return text;
  return '${text.substring(0, hardCap).trimRight()}…';
}

/// Single-line, length-capped form of a cell value for grid rendering. The
/// grid only ever paints one ellipsized line, so handing `Text` a
/// multi-kilobyte value forces the layout engine to shape thousands of
/// glyphs that get clipped anyway — the dominant cost of a scroll frame.
String truncateForCell(String text) =>
    truncateSingleLine(text, kCellMaxChars);
