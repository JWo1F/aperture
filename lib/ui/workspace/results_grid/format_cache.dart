import 'package:flutter/widgets.dart';

import '../../../models/value_format.dart';
import '../../../theme/code_theme.dart';
import 'grid_metrics.dart';

/// Per-result-page memo of cell formatting work.
///
/// `formatCellValue` runs jsonEncode / toString for Map/List values, and
/// `jsonSpans` runs `highlight.parse` for JSON cells — both dominate the
/// per-cell cost and were repeated on every row rebuild before this cache.
/// Entries are keyed by *source* row (not slot row) so the cache stays valid
/// as pending inserts reorder slots without touching `result.rows`. Callers
/// must [clear] it whenever a fresh result page replaces the current one.
class FormatCache {
  final Map<int, Map<int, String?>> _format = {};
  final Map<int, Map<int, List<InlineSpan>>> _spans = {};

  /// Formatted text for [sourceRow], [column] with [original] as the input.
  String? format(int sourceRow, int column, Object? original) {
    final byRow = _format.putIfAbsent(sourceRow, () => <int, String?>{});
    if (byRow.containsKey(column)) return byRow[column];
    final formatted = formatCellValue(original);
    byRow[column] = formatted;
    return formatted;
  }

  /// Highlighted JSON spans for [sourceRow], [column] using [source] as the
  /// input. Source is bounded to 255 chars by `jsonSpans` itself.
  List<InlineSpan> spans(int sourceRow, int column, String source) {
    final byRow = _spans.putIfAbsent(sourceRow, () => <int, List<InlineSpan>>{});
    final cached = byRow[column];
    if (cached != null) return cached;
    final result = jsonSpans(source, gridCellStyle);
    byRow[column] = result;
    return result;
  }

  void clear() {
    _format.clear();
    _spans.clear();
  }
}
