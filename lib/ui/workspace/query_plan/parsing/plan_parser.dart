import '../model/plan_node.dart';

/// Parses a Postgres `EXPLAIN (FORMAT JSON)` top-level JSON object into a
/// [PlanNode] tree, returning the root node or null when the payload had
/// no `Plan` entry.
///
/// Postgres' JSON shape stays remarkably consistent across versions, so
/// the parser is intentionally thin: it walks `Plans` recursively, copies
/// the parent's `Node Type` into the child for relationship labels, and
/// tags each child with the "is last sibling" bookkeeping the tree
/// renderer needs.
PlanNode? parsePlan(Map<String, dynamic> planJson) {
  final root = planJson['Plan'] as Map<String, dynamic>?;
  if (root == null) return null;
  return _buildNode(root, 0, const [], null);
}

PlanNode _buildNode(
  Map<String, dynamic> raw,
  int depth,
  List<bool> ancestorIsLast,
  String? parentType,
) {
  final kids = (raw['Plans'] as List?)?.cast<Map<String, dynamic>>() ??
      const <Map<String, dynamic>>[];
  final myType = raw['Node Type'] as String?;
  final children = <PlanNode>[];
  for (var i = 0; i < kids.length; i++) {
    children.add(
      _buildNode(
        kids[i],
        depth + 1,
        [...ancestorIsLast, i == kids.length - 1],
        myType,
      ),
    );
  }
  return PlanNode(
    raw: raw,
    depth: depth,
    ancestorIsLast: ancestorIsLast,
    parentType: parentType,
    children: children,
  );
}
