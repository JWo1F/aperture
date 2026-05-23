import 'package:flutter/widgets.dart';

/// Soft-wrap pixel metrics for the editor.
///
/// `lineTopsPx[i]` is the painter-y of logical line `i`'s first visual
/// row; `lineHeightsPx[i]` is the pixel height of that whole logical
/// line (one or more visual rows). Both arrays are read in *painter
/// pixels* so the gutter, line icons, the band overlay, and the popup
/// anchor never round through `(fontSize * lineHeight)` — bold keywords
/// that nudge a row to wrap early stay tracked exactly.
///
/// Cached on `(text, bodyWidth)`; [ensure] is a no-op when both match.
class LineMetrics {
  String? _text;
  double _width = -1;
  List<double> _tops = const [0];
  List<double> _heights = const [0];
  double _rowHeight = 0;
  double _totalHeight = 0;

  double get width => _width;
  double get rowHeight => _rowHeight;

  /// Total painted text height at the cached [width] — the sum of every
  /// logical line's visual rows. Zero before the first [ensure].
  double get totalHeightPx => _totalHeight;

  /// Lays out [span] at [bodyWidth] and records each logical line's top
  /// + height. Caller is responsible for passing the same styled span
  /// the field paints, so wrap differences (bold keywords, etc.) are
  /// reflected here.
  void ensure({
    required BuildContext context,
    required TextSpan span,
    required String text,
    required double bodyWidth,
  }) {
    if (bodyWidth <= 0) return;
    if (text == _text && bodyWidth == _width) return;

    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    )..layout(maxWidth: bodyWidth);

    final lines = text.split('\n');
    final topsPx = List<double>.filled(lines.length, 0);
    final heightsPx = List<double>.filled(lines.length, 0);

    var lineStart = 0;
    for (var i = 0; i < lines.length; i++) {
      final off = tp.getOffsetForCaret(
        TextPosition(offset: lineStart),
        Rect.zero,
      );
      topsPx[i] = off.dy;
      lineStart += lines[i].length + 1; // skip the newline
    }

    final totalHeight = tp.height;
    for (var i = 0; i < lines.length; i++) {
      final nextTop = i + 1 < lines.length ? topsPx[i + 1] : totalHeight;
      heightsPx[i] = (nextTop - topsPx[i]).clamp(0, double.infinity);
    }

    _rowHeight = tp.preferredLineHeight;
    tp.dispose();

    _text = text;
    _width = bodyWidth;
    _tops = topsPx;
    _heights = heightsPx;
    _totalHeight = totalHeight;
  }

  double topPx(int logical) {
    if (_tops.isEmpty) return 0;
    final clamped = logical.clamp(0, _tops.length - 1);
    return _tops[clamped];
  }

  double heightPx(int logical) {
    if (_heights.isEmpty) return _rowHeight;
    final clamped = logical.clamp(0, _heights.length - 1);
    final h = _heights[clamped];
    return h > 0 ? h : _rowHeight;
  }

  /// Pixel offset just below the caret at [cursor], relative to the painter
  /// origin. Returns `Offset.zero` if metrics haven't been measured yet.
  Offset caretOffset({
    required BuildContext context,
    required TextSpan span,
    required int cursor,
    required int textLength,
  }) {
    if (_width <= 0) return Offset.zero;
    final upTo = cursor.clamp(0, textLength);
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    )..layout(maxWidth: _width);
    final caret = tp.getOffsetForCaret(TextPosition(offset: upTo), Rect.zero);
    tp.dispose();
    return caret;
  }
}
