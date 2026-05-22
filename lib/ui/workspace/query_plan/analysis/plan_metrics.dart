import '../model/plan_node.dart';

/// Depth-first walk producing the same node order the card list renders.
List<PlanNode> flatten(PlanNode root) {
  final out = <PlanNode>[];
  _walk(root, out);
  return out;
}

void _walk(PlanNode node, List<PlanNode> out) {
  out.add(node);
  for (final c in node.children) {
    _walk(c, out);
  }
}

/// Aggregate view of a flattened plan: the [hottest] node (largest
/// `selfMs`, the one the summary header surfaces) and [maxSelfMs], the
/// denominator the timing bar fills against. A single tree-walk produces
/// both so the renderer doesn't recompute selfMs per card.
class PlanMetrics {
  PlanMetrics({required this.hottest, required this.maxSelfMs});

  final PlanNode hottest;
  final double maxSelfMs;
}

PlanMetrics computeMetrics(List<PlanNode> nodes) {
  PlanNode? hottest;
  var max = 0.0;
  for (final n in nodes) {
    final s = n.selfMs;
    if (hottest == null || s > max) {
      hottest = n;
      max = s;
    }
  }
  return PlanMetrics(hottest: hottest!, maxSelfMs: max);
}
