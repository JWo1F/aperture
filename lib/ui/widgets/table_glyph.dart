import 'package:flutter/material.dart';

/// A small custom glyph: outlined rectangle with a filled header band and a
/// single body row. Distinctive enough to telegraph "table" at 12px without
/// reaching for Material's generic table icons.
class TableGlyph extends StatelessWidget {
  const TableGlyph({super.key, this.size = 12, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TablePainter(color)),
    );
  }
}

class _TablePainter extends CustomPainter {
  _TablePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..isAntiAlias = true;

    final fill = Paint()
      ..color = color.withValues(alpha: 0.32)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;
    final inset = 0.6;
    final rect = Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2);
    final r = const Radius.circular(1.6);
    final outer = RRect.fromRectAndRadius(rect, r);

    // Filled header band — clipped to the outer rounded rectangle so its
    // corners match.
    canvas.save();
    canvas.clipRRect(outer);
    final headerHeight = (h - inset * 2) * 0.34;
    canvas.drawRect(
      Rect.fromLTWH(inset, inset, w - inset * 2, headerHeight),
      fill,
    );
    canvas.restore();

    canvas.drawRRect(outer, stroke);

    // Single row separator below the header.
    final divider = inset + headerHeight + (h - inset * 2 - headerHeight) * 0.5;
    canvas.drawLine(
      Offset(inset + 0.3, divider),
      Offset(w - inset - 0.3, divider),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_TablePainter old) => old.color != color;
}

/// Key badge drawn over a [ColumnGlyph]'s bottom-left corner.
enum ColumnMark { none, primaryKey, foreignKey }

/// Companion to [TableGlyph] for a single column: an outlined rectangle
/// sliced by a vertical divider. The narrow "column" slice is filled solid
/// when the column is NOT NULL, and a small key tucks into the bottom-left
/// corner for primary- and foreign-key columns, legible at 12px.
class ColumnGlyph extends StatelessWidget {
  const ColumnGlyph({
    super.key,
    this.size = 12,
    required this.color,
    this.filled = false,
    this.mark = ColumnMark.none,
    this.markColor,
  });

  final double size;
  final Color color;

  /// NOT NULL columns fill the column slice solid; nullable ones leave it
  /// as an empty outline.
  final bool filled;

  /// Which key badge, if any, to draw over the bottom-left corner.
  final ColumnMark mark;

  /// Colour of the [mark] badge; ignored when [mark] is [ColumnMark.none].
  final Color? markColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ColumnPainter(color, filled, mark, markColor),
      ),
    );
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter(this.color, this.filled, this.mark, this.markColor);

  final Color color;
  final bool filled;
  final ColumnMark mark;
  final Color? markColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;
    const inset = 0.6;
    final rect = Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2);
    const r = Radius.circular(1.6);
    final outer = RRect.fromRectAndRadius(rect, r);
    final bandWidth = (w - inset * 2) * 0.36;

    // The column slice is filled solid only for NOT NULL columns; clipped to
    // the outer rounded rectangle so its corners match.
    if (filled) {
      final bandFill = Paint()
        ..color = color.withValues(alpha: 0.32)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.save();
      canvas.clipRRect(outer);
      canvas.drawRect(
        Rect.fromLTWH(inset, inset, bandWidth, h - inset * 2),
        bandFill,
      );
      canvas.restore();
    }

    canvas.drawRRect(outer, stroke);

    // Divider separating the column slice from the rest of the relation.
    final dividerX = inset + bandWidth;
    canvas.drawLine(
      Offset(dividerX, inset + 0.3),
      Offset(dividerX, h - inset - 0.3),
      stroke,
    );

    if (mark != ColumnMark.none) {
      _paintKey(canvas, w, h, markColor ?? color);
    }
  }

  /// A compact key tucked into the bottom-left corner — the primary- and
  /// foreign-key badge. Identical shape for both; only the colour differs.
  void _paintKey(Canvas canvas, double w, double h, Color keyColor) {
    final fill = Paint()
      ..color = keyColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final shaft = Paint()
      ..color = keyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Bow: a filled ring (outer circle minus inner circle, even-odd).
    final bow = Offset(w * 0.26, h * 0.74);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: bow, radius: 2.2))
        ..addOval(Rect.fromCircle(center: bow, radius: 1.0)),
      fill,
    );

    // Shaft running diagonally up-right out of the bow.
    final shaftStart = Offset(bow.dx + 1.5, bow.dy - 1.5);
    final tip = Offset(w * 0.62, h * 0.38);
    canvas.drawLine(shaftStart, tip, shaft);

    // Two teeth on one side near the tip.
    final dir = (tip - shaftStart) / (tip - shaftStart).distance;
    final perp = Offset(-dir.dy, dir.dx);
    canvas.drawLine(tip, tip + perp * 2.2, shaft);
    final back = tip - dir * 1.7;
    canvas.drawLine(back, back + perp * 1.6, shaft);
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.color != color ||
      old.filled != filled ||
      old.mark != mark ||
      old.markColor != markColor;
}
