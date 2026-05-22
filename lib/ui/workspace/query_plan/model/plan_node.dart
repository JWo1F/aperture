/// Parsed view of one Postgres `EXPLAIN (FORMAT JSON)` plan node.
///
/// Stays close to the raw JSON — kept as a single class keyed by [kind]
/// rather than a sealed hierarchy because nearly every operation-family
/// reads the same handful of fields, and the parser is a one-shot pass
/// over a `Map<String, dynamic>` that doesn't benefit from per-kind
/// subtypes.
library;

/// Inclusive wall-time (or planner cost) for a raw plan-node map.
///
/// Postgres' `Actual Total Time` is per-loop, so we multiply by
/// `Actual Loops` to get the real cumulative cost. Falls back to
/// `Total Cost` when ANALYZE wasn't used so non-analyzed plans still
/// rank consistently.
double inclusiveMsOfRaw(Map<String, dynamic> node) {
  final t = (node['Actual Total Time'] as num?)?.toDouble();
  if (t != null) return t * ((node['Actual Loops'] as num?)?.toInt() ?? 1);
  return (node['Total Cost'] as num?)?.toDouble() ?? 0;
}

/// Classifies the actual-vs-estimate row-count skew for one node. The
/// planner relies on these estimates to pick scan/join strategies — a
/// 10× miss is usually the root cause of "this should be fast but isn't".
enum PlanMismatch { none, mild, severe }

class PlanNode {
  PlanNode({
    required this.raw,
    required this.depth,
    required this.ancestorIsLast,
    required this.parentType,
    required this.children,
  });

  /// Original JSON object. Rules and renderers that need rarely-used
  /// fields read straight from here rather than padding the class API.
  final Map<String, dynamic> raw;

  final int depth;

  /// One flag per ancestor depth: true when this branch's ancestor at
  /// that depth was the last child of its parent (so the rail above this
  /// node should stop, not continue downward).
  final List<bool> ancestorIsLast;

  /// `Node Type` of the immediate parent, used by [relationshipLabel] to
  /// pick a beginner-friendly description of how this node feeds the one
  /// above it ("hash input" vs. "outer side" vs. "feeds Aggregate").
  final String? parentType;

  final List<PlanNode> children;

  bool get isLastChild => ancestorIsLast.isNotEmpty && ancestorIsLast.last;

  String get kind => raw['Node Type'] as String? ?? 'Unknown';

  String? get relation => raw['Relation Name'] as String?;

  String? get indexName => raw['Index Name'] as String?;

  String? get alias => raw['Alias'] as String?;

  String? get schema => raw['Schema'] as String?;

  double? get actualTotalTime => (raw['Actual Total Time'] as num?)?.toDouble();

  int? get actualRows => (raw['Actual Rows'] as num?)?.toInt();

  int? get actualLoops => (raw['Actual Loops'] as num?)?.toInt();

  int? get planRows => (raw['Plan Rows'] as num?)?.toInt();

  double? get totalCost => (raw['Total Cost'] as num?)?.toDouble();

  /// Cumulative wall-time for this node *and its entire subtree* — per-loop
  /// time × loop count. Postgres reports time inclusively, so the root's
  /// value is always the whole query; this is not the figure to rank nodes
  /// by (see [selfMs]). Falls back to planner cost when ANALYZE wasn't used.
  double get inclusiveMs => inclusiveMsOfRaw(raw);

  /// Wall-time spent in this node *alone* — its inclusive time minus the
  /// inclusive time of its direct children. This is what answers "where did
  /// the query spend its time": ranking by [inclusiveMs] would always crown
  /// the root, since by definition it contains every other node. Clamped at
  /// zero — rounding and parallel-worker accounting can make the
  /// subtraction land slightly negative.
  double get selfMs {
    var childSum = 0.0;
    for (final c in children) {
      childSum += c.inclusiveMs;
    }
    final self = inclusiveMs - childSum;
    return self < 0 ? 0 : self;
  }

  /// `schema.relation` (or just `relation` for the default `public`
  /// schema). Returns null when the node isn't tied to a relation.
  String? get qualifiedRelation {
    if (relation == null) return null;
    if (schema == null || schema == 'public') return relation;
    return '$schema.$relation';
  }

  /// Headline target — the relation/index this node operates on.
  String? get target {
    final parts = <String>[];
    if (indexName != null) parts.add('via ${indexName!}');
    if (relation != null) {
      parts.add(
        alias != null && alias != relation
            ? '${relation!} (as $alias)'
            : relation!,
      );
    }
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  /// Conditions to surface as chip rows: filters, join keys, sort keys.
  List<(String, String)> get conditions {
    final out = <(String, String)>[];
    final filter = raw['Filter'] as String?;
    if (filter != null) out.add(('Filter', filter));
    final indexCond = raw['Index Cond'] as String?;
    if (indexCond != null) out.add(('Index', indexCond));
    final hashCond = raw['Hash Cond'] as String?;
    if (hashCond != null) out.add(('Join', hashCond));
    final mergeCond = raw['Merge Cond'] as String?;
    if (mergeCond != null) out.add(('Join', mergeCond));
    final joinFilter = raw['Join Filter'] as String?;
    if (joinFilter != null) out.add(('Join filter', joinFilter));
    final recheck = raw['Recheck Cond'] as String?;
    if (recheck != null) out.add(('Recheck', recheck));
    final sortKey = raw['Sort Key'] as List?;
    if (sortKey != null && sortKey.isNotEmpty) {
      out.add(('Sort by', sortKey.cast<String>().join(', ')));
    }
    final groupKey = raw['Group Key'] as List?;
    if (groupKey != null && groupKey.isNotEmpty) {
      out.add(('Group by', groupKey.cast<String>().join(', ')));
    }
    return out;
  }

  /// Beginner-friendly description of how this node feeds its parent.
  /// Single-input parents (Hash, Sort, Materialize, …) yield a label that
  /// names the role directly; join parents yield "outer side" / "inner
  /// side" using the explicit `Parent Relationship` from EXPLAIN. Returns
  /// null for the root node.
  String? get relationshipLabel {
    if (depth == 0) return null;
    final pt = parentType;
    if (pt != null) {
      switch (pt) {
        case 'Hash':
          return 'hash input';
        case 'Sort':
        case 'Incremental Sort':
          return 'sort input';
        case 'Materialize':
          return 'cached for reuse';
        case 'Limit':
          return 'rows to limit';
        case 'Aggregate':
        case 'WindowAgg':
        case 'Group':
        case 'Unique':
          return 'input rows';
        case 'Gather':
        case 'Gather Merge':
          return 'worker output';
        case 'Append':
        case 'Merge Append':
          return 'union member';
        case 'ModifyTable':
          return 'rows to modify';
      }
    }
    final rel = raw['Parent Relationship'] as String?;
    switch (rel) {
      case 'Outer':
        return 'outer side';
      case 'Inner':
        return 'inner side';
      case 'Member':
        return 'union member';
      case 'InitPlan':
        return 'init plan';
      case 'SubPlan':
        return 'subplan';
    }
    return pt == null ? 'child' : 'feeds $pt';
  }

  PlanMismatch get mismatch {
    final a = actualRows;
    final e = planRows;
    if (a == null || e == null || a == 0 && e == 0) return PlanMismatch.none;
    final ratio = a == 0
        ? e.toDouble()
        : e == 0
        ? a.toDouble()
        : (a / e).clamp(1 / 10000, 10000.0);
    final fold = ratio >= 1 ? ratio : 1 / ratio;
    if (fold < 2) return PlanMismatch.none;
    if (fold < 10) return PlanMismatch.mild;
    return PlanMismatch.severe;
  }
}
