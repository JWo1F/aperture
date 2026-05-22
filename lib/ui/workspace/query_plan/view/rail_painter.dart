import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../model/plan_node.dart';

/// Indent space to the left of a non-root card. Draws:
///
/// - Continuous vertical "rails" for every ancestor branch that still
///   has siblings below this node, so the user can trace a child back to
///   its parent by following the line up.
/// - A corner connector ending in a `→` arrow that points at the card.
class IndentRail extends StatelessWidget {
  const IndentRail({
    super.key,
    required this.node,
    required this.indentStep,
  });

  final PlanNode node;
  final double indentStep;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: RailPainter(
        depth: node.depth,
        ancestorIsLast: node.ancestorIsLast,
        indentStep: indentStep,
        railColor: AppColors.hairline,
        arrowColor: AppColors.textMuted,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Paints the tree-connector graphics for one card row.
///
/// Each ancestor at depth `d` contributes a vertical line at the centre
/// of slot `d` when [ancestorIsLast]\[d] is false (meaning there's still
/// a sibling below this row in that branch). The immediate parent (the
/// last ancestor) contributes a corner: vertical from the top of the
/// slot down to the card's mid-line, then horizontal to the slot's
/// right edge, ending in a small arrowhead pointing at the card.
class RailPainter extends CustomPainter {
  RailPainter({
    required this.depth,
    required this.ancestorIsLast,
    required this.indentStep,
    required this.railColor,
    required this.arrowColor,
  });

  final int depth;
  final List<bool> ancestorIsLast;
  final double indentStep;
  final Color railColor;
  final Color arrowColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth == 0) return;
    final railPaint = Paint()
      ..color = railColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final arrowPaint = Paint()
      ..color = arrowColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // y-position of the card's header row (where the arrow lands and the
    // corner bends). Matches the card's internal top padding so the
    // horizontal line points at the badge instead of the timing bar.
    final cornerY = 18.0;

    for (var d = 0; d < depth - 1; d++) {
      if (ancestorIsLast[d]) continue;
      final x = d * indentStep + indentStep / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), railPaint);
    }

    final parentX = (depth - 1) * indentStep + indentStep / 2;
    final isLast = ancestorIsLast.isNotEmpty && ancestorIsLast.last;

    final vBottom = isLast ? cornerY : size.height;
    canvas.drawLine(Offset(parentX, 0), Offset(parentX, vBottom), railPaint);

    final arrowTipX = depth * indentStep - 2;
    canvas.drawLine(
      Offset(parentX, cornerY),
      Offset(arrowTipX, cornerY),
      arrowPaint,
    );

    final headPath = Path()
      ..moveTo(arrowTipX, cornerY)
      ..lineTo(arrowTipX - 4, cornerY - 3)
      ..moveTo(arrowTipX, cornerY)
      ..lineTo(arrowTipX - 4, cornerY + 3);
    canvas.drawPath(headPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant RailPainter old) {
    return depth != old.depth ||
        indentStep != old.indentStep ||
        !listEquals(ancestorIsLast, old.ancestorIsLast) ||
        railColor != old.railColor ||
        arrowColor != old.arrowColor;
  }
}
