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
