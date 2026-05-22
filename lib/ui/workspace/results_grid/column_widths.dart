import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../models/db_object.dart';
import '../../../theme/app_theme.dart';
import 'format_cache.dart';
import 'grid_metrics.dart';

/// Owns the grid's per-column pixel widths and the off-screen [TextPainter]
/// used to auto-size them. A column's width comes from the caller's saved
/// store when present, otherwise from sampling the widest visible value.
class ColumnWidths {
  final TextPainter _measurer = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );

  List<double> _widths = [];
  List<String> _keys = [];

  static const double _autoMin = 64;
  static const double _autoMax = 200;
  static const double _cellPad = 20; // 9px each side + 2 fudge
  // 10px padding L + 10px R + small fudge.
  static const double _headerChrome = 30;
  static const double _headerKeyIcon = 15; // 10px icon + 5px spacing
  static const double _headerSortIcon = 13; // 11px icon + 2px spacing
  static const int _sampleRows = 50;

  int get length => _widths.length;

  double operator [](int index) => _widths[index];

  /// Total width of every column — the data area's intrinsic width.
  double get total => _widths.fold<double>(0, (s, w) => s + w);

  /// Left edge of [col] — the summed width of every column before it.
  double offsetOf(int col) {
    var x = 0.0;
    final end = col < _widths.length ? col : _widths.length;
    for (var i = 0; i < end; i++) {
      x += _widths[i];
    }
    return x;
  }

  /// True when the widths are already in sync with [columns]; lets the caller
  /// skip a re-sync when only the row data changed.
  bool matches(List<String> columns) => listEquals(columns, _keys);

  /// (Re)derive every column width. Saved widths win; the rest are auto-sized
  /// by sampling. Auto-size routes sample-row formatting through [formatCache]
  /// so the work is reused when those rows scroll into view.
  void sync({
    required List<String> columns,
    required List<List<Object?>> rows,
    required Map<String, double>? saved,
    required FormatCache formatCache,
    required Map<String, DbColumn>? columnMeta,
    required Map<String, DbForeignKey>? foreignKeys,
    required bool sortable,
  }) {
    _keys = List.of(columns);
    _widths = [
      for (var i = 0; i < columns.length; i++)
        saved?[columns[i]] ??
            _autoWidth(
              columns[i],
              i,
              rows,
              formatCache,
              columnMeta,
              foreignKeys,
              sortable,
            ),
    ];
  }

  /// Apply a resize-handle drag delta to [index], clamped to sane bounds.
  void resize(int index, double delta) {
    _widths[index] = (_widths[index] + delta).clamp(64.0, 900.0);
  }

  void dispose() => _measurer.dispose();

  /// Default width = widest visible cell (and the header) in this column,
  /// clamped between [_autoMin] and [_autoMax]. Cells already ellipsize, so we
  /// measure at most the first 200 chars of each value.
  ///
  /// Only the first [_sampleRows] rows are sampled: pages can hit several
  /// thousand rows and measuring every one ran formatCellValue + layout in a
  /// tight loop on the UI thread, blocking the first frame for ~500 ms+.
  double _autoWidth(
    String column,
    int columnIndex,
    List<List<Object?>> rows,
    FormatCache formatCache,
    Map<String, DbColumn>? columnMeta,
    Map<String, DbForeignKey>? foreignKeys,
    bool sortable,
  ) {
    final headerStyle = AppTheme.mono(size: 11, weight: FontWeight.w600);
    _measurer
      ..text = TextSpan(text: column, style: headerStyle)
      ..layout();
    var headerExtra = _headerChrome;
    final meta = columnMeta?[column];
    final hasKeyIcon = (meta?.isPrimaryKey ?? false) ||
        (foreignKeys?.containsKey(column) ?? false);
    if (hasKeyIcon) headerExtra += _headerKeyIcon;
    if (sortable) headerExtra += _headerSortIcon;
    var widest = _measurer.width + headerExtra;

    final n = rows.length < _sampleRows ? rows.length : _sampleRows;
    for (var r = 0; r < n; r++) {
      final raw = rows[r][columnIndex];
      final formatted = formatCache.format(r, columnIndex, raw);
      final text = formatted ?? 'NULL';
      final sample = text.length > 200 ? text.substring(0, 200) : text;
      _measurer
        ..text = TextSpan(text: sample, style: gridCellStyle)
        ..layout();
      final w = _measurer.width + _cellPad;
      if (w > widest) widest = w;
    }

    return widest.clamp(_autoMin, _autoMax);
  }
}
