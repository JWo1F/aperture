import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Renders a Postgres `EXPLAIN (FORMAT JSON)` plan as a stack of cards.
///
/// The goal of this view is to be legible to someone who has never read
/// a Postgres plan before. Every node carries a plain-English subtitle
/// describing what the operation does, the heaviest node in the tree is
/// surfaced in the summary header, and unexpected row counts trigger a
/// "estimate is off" chip so the planner's bad guesses don't go quiet.
class QueryPlanView extends StatefulWidget {
  const QueryPlanView({super.key, required this.tab});

  final QueryTab tab;

  @override
  State<QueryPlanView> createState() => _QueryPlanViewState();
}

class _QueryPlanViewState extends State<QueryPlanView> {
  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant QueryPlanView old) {
    super.didUpdateWidget(old);
    _maybeLoad();
  }

  void _maybeLoad() {
    final tab = widget.tab;
    if (tab.lastRunSql == null) return;
    if (tab.planLoading) return;
    if (tab.planSourceSql == tab.lastRunSql && tab.planJson != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().loadQueryPlan(tab);
    });
  }

  void _runAsExplain() {
    final tab = widget.tab;
    final sql = tab.sql.trim();
    if (sql.isEmpty) return;
    context.read<AppState>().loadQueryPlan(tab, sqlOverride: sql);
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    if (tab.planLoading) return const _Spinner();
    if (tab.planError != null) return _PlanError(message: tab.planError!);
    final json = tab.planJson;
    if (json == null) {
      return _PlanSuggestion(
        enabled: tab.sql.trim().isNotEmpty,
        onRun: tab.sql.trim().isNotEmpty ? _runAsExplain : null,
      );
    }
    final stale = tab.lastRunSql != null &&
        tab.planSourceSql != tab.lastRunSql;
    return _PlanTree(planJson: json, stale: stale);
  }
}

// --- empty / loading / error states ---------------------------------------

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _PlanSuggestion extends StatelessWidget {
  const _PlanSuggestion({required this.enabled, required this.onRun});

  final bool enabled;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 30, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(
              'See how Postgres runs your query',
              style: AppTheme.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              enabled
                  ? 'EXPLAIN walks every step of the plan: which tables it '
                      'reads, how it joins them, and where time is spent.'
                  : 'Write SQL in the editor above and the plan will '
                      'become available here.',
              textAlign: TextAlign.center,
              style: AppTheme.mono(size: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Run as EXPLAIN',
              icon: Icons.account_tree_outlined,
              primary: true,
              onPressed: onRun,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanError extends StatelessWidget {
  const _PlanError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Text(
                'EXPLAIN failed',
                style: AppTheme.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            message,
            style: AppTheme.mono(size: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// --- node-type glossary ---------------------------------------------------

/// Plain-English single-sentence descriptions of the operations a
/// Postgres plan can contain. Used as the subtitle of every node card so
/// readers don't need to look up what "Bitmap Heap Scan" means.
const Map<String, String> _nodeDescriptions = {
  'Seq Scan': 'Reads every row in the table from start to end.',
  'Index Scan':
      'Walks an index to locate rows, then reads those rows from the table.',
  'Index Only Scan':
      'Walks an index and answers from it directly — no table lookup needed.',
  'Bitmap Index Scan':
      'Builds a bitmap of matching rows from one or more indexes.',
  'Bitmap Heap Scan':
      'Fetches the rows the bitmap pointed at, in disk-block order.',
  'Tid Scan': 'Reads rows by their physical row identifiers.',
  'Sample Scan': 'Reads a random sample of rows from the table.',
  'Subquery Scan': 'Iterates a subquery as if it were a table.',
  'Function Scan': 'Iterates the rows returned by a set-returning function.',
  'Values Scan': 'Reads an inline VALUES list.',
  'CTE Scan': 'Iterates rows produced by a WITH clause.',
  'WorkTable Scan':
      'Iterates the working set of a recursive WITH clause.',
  'Foreign Scan': 'Reads rows from a foreign (remote) table.',
  'Nested Loop':
      'For each row on the left, finds the matching rows on the right.',
  'Hash Join':
      'Builds an in-memory hash of one side and probes it from the other.',
  'Merge Join':
      'Merges two sorted inputs together, the way mergesort merges runs.',
  'Hash': 'Builds an in-memory hash table to feed the join above it.',
  'Materialize':
      'Caches its input so the parent can scan it more than once.',
  'Sort': 'Sorts its input by the requested keys.',
  'Incremental Sort':
      'Sorts within groups that are already partly sorted.',
  'Group': 'Groups consecutive rows with equal keys.',
  'Aggregate': 'Reduces input rows to one row per group (count, sum, …).',
  'WindowAgg': 'Computes window-function values over partitions.',
  'Unique': 'Removes adjacent duplicate rows.',
  'SetOp': 'Computes UNION/INTERSECT/EXCEPT between sorted inputs.',
  'LockRows': 'Locks the rows it sees (FOR UPDATE / SHARE).',
  'Limit': 'Stops emitting rows after the requested number is reached.',
  'Gather': 'Collects rows from parallel worker processes.',
  'Gather Merge':
      'Collects already-sorted rows from parallel workers, in order.',
  'Append': 'Concatenates rows from several child plans (UNION ALL etc.).',
  'Merge Append': 'Concatenates already-sorted inputs in order.',
  'Result': 'Emits a single row, often a computed expression.',
  'ProjectSet': 'Expands a set-returning function in the target list.',
  'ModifyTable': 'Performs the actual INSERT, UPDATE or DELETE.',
  'Recursive Union': 'Drives a recursive CTE to a fixed point.',
};

String _describeNode(String type) {
  return _nodeDescriptions[type] ?? 'A planner operation.';
}

// --- main tree ------------------------------------------------------------

class _PlanTree extends StatelessWidget {
  const _PlanTree({required this.planJson, required this.stale});

  final Map<String, dynamic> planJson;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final root = planJson['Plan'] as Map<String, dynamic>?;
    if (root == null) {
      return const EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Plan was empty',
        message: 'Postgres returned a result with no Plan node.',
      );
    }
    final rows = <_PlanNode>[];
    _flatten(root, 0, const [], null, rows);
    final totalMs = rows.fold<double>(0, (m, r) {
      final v = r.nodeMs;
      return v > m ? v : m;
    });
    final slowest = rows.reduce((a, b) => a.nodeMs >= b.nodeMs ? a : b);
    final planningMs = (planJson['Planning Time'] as num?)?.toDouble();
    final executionMs = (planJson['Execution Time'] as num?)?.toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.md,
      ),
      // `stretch` forces every child (summary + each card row) to fill
      // horizontally, so the right-side ms/% column lands at the same x
      // for every node regardless of indent or content width.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stale) const _StaleBanner(),
          _SummaryHeader(
            planningMs: planningMs,
            executionMs: executionMs,
            totalNodes: rows.length,
            slowest: slowest,
            totalMs: totalMs == 0 ? null : totalMs,
          ),
          const SizedBox(height: 10),
          for (final node in rows)
            _NodeCard(
              node: node,
              totalMs: totalMs,
              isSlowest: identical(node, slowest),
            ),
        ],
      ),
    );
  }

  void _flatten(
    Map<String, dynamic> node,
    int depth,
    List<bool> ancestorIsLast,
    String? parentType,
    List<_PlanNode> out,
  ) {
    out.add(_PlanNode(
      node: node,
      depth: depth,
      ancestorIsLast: ancestorIsLast,
      parentType: parentType,
    ));
    final children = (node['Plans'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final type = node['Node Type'] as String?;
    for (var i = 0; i < children.length; i++) {
      _flatten(
        children[i],
        depth + 1,
        [...ancestorIsLast, i == children.length - 1],
        type,
        out,
      );
    }
  }
}

class _PlanNode {
  _PlanNode({
    required this.node,
    required this.depth,
    required this.ancestorIsLast,
    required this.parentType,
  });

  final Map<String, dynamic> node;
  final int depth;

  /// One flag per ancestor depth: true when this branch's ancestor at
  /// that depth was the last child of its parent (so the rail above this
  /// node should stop, not continue downward).
  final List<bool> ancestorIsLast;

  /// `Node Type` of the immediate parent, used by [relationshipLabel] to
  /// pick a beginner-friendly description of how this node feeds the one
  /// above it ("hash input" vs. "outer side" vs. "feeds Aggregate").
  final String? parentType;

  bool get isLastChild =>
      ancestorIsLast.isNotEmpty && ancestorIsLast.last;

  String get type => node['Node Type'] as String? ?? 'Unknown';
  String? get relation => node['Relation Name'] as String?;
  String? get indexName => node['Index Name'] as String?;
  String? get alias => node['Alias'] as String?;
  String? get schema => node['Schema'] as String?;
  String? get strategy => node['Strategy'] as String?;
  String? get joinType => node['Join Type'] as String?;
  String? get parentRelationship => node['Parent Relationship'] as String?;

  double? get actualTotalTime =>
      (node['Actual Total Time'] as num?)?.toDouble();
  int? get actualRows => (node['Actual Rows'] as num?)?.toInt();
  int? get actualLoops => (node['Actual Loops'] as num?)?.toInt();
  int? get planRows => (node['Plan Rows'] as num?)?.toInt();
  double? get totalCost => (node['Total Cost'] as num?)?.toDouble();

  /// Total wall-time spent inside this node — per-loop time × loop count.
  /// Falls back to planner cost when ANALYZE wasn't used, so the bar still
  /// conveys relative weight on plain EXPLAIN.
  double get nodeMs {
    final t = actualTotalTime;
    if (t != null) return t * (actualLoops ?? 1);
    return totalCost ?? 0;
  }

  /// Headline target — the relation/index this node operates on.
  String? get target {
    final parts = <String>[];
    if (indexName != null) parts.add('via ${indexName!}');
    if (relation != null) {
      parts.add(alias != null && alias != relation
          ? '${relation!} (as $alias)'
          : relation!);
    }
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  /// Conditions to surface as chip rows: filters, join keys, sort keys.
  List<(String, String)> get conditions {
    final out = <(String, String)>[];
    final filter = node['Filter'] as String?;
    if (filter != null) out.add(('Filter', filter));
    final indexCond = node['Index Cond'] as String?;
    if (indexCond != null) out.add(('Index', indexCond));
    final hashCond = node['Hash Cond'] as String?;
    if (hashCond != null) out.add(('Join', hashCond));
    final mergeCond = node['Merge Cond'] as String?;
    if (mergeCond != null) out.add(('Join', mergeCond));
    final joinFilter = node['Join Filter'] as String?;
    if (joinFilter != null) out.add(('Join filter', joinFilter));
    final recheck = node['Recheck Cond'] as String?;
    if (recheck != null) out.add(('Recheck', recheck));
    final sortKey = node['Sort Key'] as List?;
    if (sortKey != null && sortKey.isNotEmpty) {
      out.add(('Sort by', sortKey.cast<String>().join(', ')));
    }
    final groupKey = node['Group Key'] as List?;
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
    final rel = node['Parent Relationship'] as String?;
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

  /// Classifies actual-vs-estimate skew.
  ///
  /// Postgres relies on the planner's row estimates to decide between
  /// index/seq scans and join strategies. Wildly wrong estimates are the
  /// most common cause of "this should be fast but isn't", so we surface
  /// the mismatch loudly when it's severe.
  _Mismatch get mismatch {
    final a = actualRows;
    final e = planRows;
    if (a == null || e == null || a == 0 && e == 0) return _Mismatch.none;
    final ratio = a == 0
        ? e.toDouble()
        : e == 0
            ? a.toDouble()
            : (a / e).clamp(1 / 10000, 10000.0);
    final fold = ratio >= 1 ? ratio : 1 / ratio;
    if (fold < 2) return _Mismatch.none;
    if (fold < 10) return _Mismatch.mild;
    return _Mismatch.severe;
  }
}

enum _Mismatch { none, mild, severe }

// --- summary header -------------------------------------------------------

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.planningMs,
    required this.executionMs,
    required this.totalNodes,
    required this.slowest,
    required this.totalMs,
  });

  final double? planningMs;
  final double? executionMs;
  final int totalNodes;
  final _PlanNode slowest;
  final double? totalMs;

  String _insight() {
    final pct = totalMs == null || totalMs == 0
        ? null
        : ((slowest.nodeMs / totalMs!) * 100).round();
    final type = slowest.type;
    if (pct != null && pct >= 60) {
      return '$type dominates execution ($pct% of total time).';
    }
    if (slowest.mismatch == _Mismatch.severe) {
      return 'Planner row estimate is far off for $type — consider ANALYZE.';
    }
    if (totalNodes == 1) {
      return 'Single-node plan — no joins or sorts to worry about.';
    }
    return '$totalNodes operations · slowest is $type.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.border),
        borderRadius: Radii.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (executionMs != null)
                _BigMetric(label: 'execution', valueMs: executionMs!),
              if (executionMs != null) const SizedBox(width: 22),
              if (planningMs != null)
                _BigMetric(
                  label: 'planning',
                  valueMs: planningMs!,
                  muted: true,
                ),
              const Spacer(),
              _NodeBadge(type: slowest.type, small: true),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 12,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _insight(),
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({
    required this.label,
    required this.valueMs,
    this.muted = false,
  });

  final String label;
  final double valueMs;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final primary = muted ? AppColors.textSecondary : AppColors.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.mono(
            size: 9.5,
            color: AppColors.textMuted,
            weight: FontWeight.w600,
          ).copyWith(letterSpacing: 0.6),
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            style: AppTheme.mono(
              size: 18,
              color: primary,
              weight: FontWeight.w600,
            ),
            children: [
              TextSpan(text: valueMs.toStringAsFixed(2)),
              TextSpan(
                text: ' ms',
                style: AppTheme.mono(
                  size: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- node card ------------------------------------------------------------

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.totalMs,
    required this.isSlowest,
  });

  final _PlanNode node;
  final double totalMs;
  final bool isSlowest;

  static const double _indentStep = 22;

  @override
  Widget build(BuildContext context) {
    final fraction = totalMs > 0 ? (node.nodeMs / totalMs) : 0.0;
    final pct = (fraction * 100).round();
    final cardColor = isSlowest
        ? AppColors.warning.withValues(alpha: 0.06)
        : AppColors.surface;
    final borderColor = isSlowest
        ? AppColors.warning.withValues(alpha: 0.4)
        : AppColors.border;
    // Row(Spacer + indent + Expanded card) forces every card to extend to
    // the same right edge regardless of depth or content width. Without
    // the Expanded the card shrinks around its content, so the right-side
    // ms/% drift left in cards with shorter text.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (node.depth > 0)
            SizedBox(
              width: node.depth * _indentStep,
              child: _IndentRail(
                node: node,
                indentStep: _indentStep,
              ),
            ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: cardColor,
                border: Border.all(color: borderColor),
                borderRadius: Radii.brMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (node.relationshipLabel != null) ...[
                    _RelationshipKicker(
                      label: node.relationshipLabel!,
                      parentType: node.parentType,
                    ),
                    const SizedBox(height: 4),
                  ],
                  _CardHeader(
                    node: node,
                    pct: pct,
                    isSlowest: isSlowest,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _describeNode(node.type),
                    style: AppTheme.mono(
                      size: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (node.conditions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final c in node.conditions)
                          _ConditionChip(label: c.$1, value: c.$2),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  _MetricsRow(node: node, pct: pct),
                  const SizedBox(height: 6),
                  _TimeBar(fraction: fraction, isSlowest: isSlowest),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

/// Indent space to the left of a non-root card. Draws:
///
/// - Continuous vertical "rails" for every ancestor branch that still
///   has siblings below this node, so the user can trace a child back to
///   its parent by following the line up.
/// - A corner connector ending in a `→` arrow that points at the card.
/// - A small label above the arrow naming this node's role in its parent
///   ("hash input", "outer side", …) so beginners aren't left guessing
///   what each level of indent means.
class _IndentRail extends StatelessWidget {
  const _IndentRail({required this.node, required this.indentStep});

  final _PlanNode node;
  final double indentStep;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RailPainter(
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
class _RailPainter extends CustomPainter {
  _RailPainter({
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

    // Ancestor verticals — every ancestor depth except the immediate
    // parent (handled below). Drawn only when the branch is still open
    // (i.e. siblings remain at that depth below this row).
    for (var d = 0; d < depth - 1; d++) {
      if (ancestorIsLast[d]) continue;
      final x = d * indentStep + indentStep / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), railPaint);
    }

    // Immediate parent slot: corner + arrow.
    final parentX = (depth - 1) * indentStep + indentStep / 2;
    final isLast =
        ancestorIsLast.isNotEmpty && ancestorIsLast.last;

    // Vertical down from the top — stop at the corner if this is the
    // last child of its parent, continue to the bottom otherwise so the
    // line keeps the sibling rail visible.
    final vBottom = isLast ? cornerY : size.height;
    canvas.drawLine(Offset(parentX, 0), Offset(parentX, vBottom), railPaint);

    // Horizontal stub from the corner to just shy of the card edge.
    final arrowTipX = depth * indentStep - 2;
    canvas.drawLine(
      Offset(parentX, cornerY),
      Offset(arrowTipX, cornerY),
      arrowPaint,
    );

    // Arrowhead.
    final headPath = Path()
      ..moveTo(arrowTipX, cornerY)
      ..lineTo(arrowTipX - 4, cornerY - 3)
      ..moveTo(arrowTipX, cornerY)
      ..lineTo(arrowTipX - 4, cornerY + 3);
    canvas.drawPath(headPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) {
    return depth != old.depth ||
        indentStep != old.indentStep ||
        !_listEq(ancestorIsLast, old.ancestorIsLast) ||
        railColor != old.railColor ||
        arrowColor != old.arrowColor;
  }

  static bool _listEq(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Tiny breadcrumb above a card's header that names this node's role
/// inside its parent ("hash input ↑ Hash Join"). Disambiguates levels
/// of the tree so the indent stops being the only hierarchy cue.
class _RelationshipKicker extends StatelessWidget {
  const _RelationshipKicker({required this.label, required this.parentType});

  final String label;
  final String? parentType;

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.mono(
      size: 9.5,
      color: AppColors.textMuted,
      weight: FontWeight.w500,
    ).copyWith(letterSpacing: 0.4);
    final emph = AppTheme.mono(
      size: 9.5,
      color: AppColors.textSecondary,
      weight: FontWeight.w600,
    ).copyWith(letterSpacing: 0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.arrow_upward, size: 10, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(text: label.toUpperCase(), style: muted),
                if (parentType != null) ...[
                  TextSpan(text: '  →  ', style: muted),
                  TextSpan(text: parentType!.toUpperCase(), style: emph),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.node,
    required this.pct,
    required this.isSlowest,
  });

  final _PlanNode node;
  final int pct;
  final bool isSlowest;

  @override
  Widget build(BuildContext context) {
    final target = node.target;
    final t = node.actualTotalTime;
    final ms = t == null ? null : t * (node.actualLoops ?? 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _NodeBadge(type: node.type, small: false),
        if (target != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              target,
              style: AppTheme.mono(
                size: 12,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (isSlowest) ...[
          const SizedBox(width: 8),
          _SlowestPill(),
        ],
        const Spacer(),
        if (ms != null) ...[
          Text(
            '${ms.toStringAsFixed(2)} ms',
            style: AppTheme.mono(
              size: 12,
              color: AppColors.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          _PercentChip(pct: pct),
        ] else if (node.totalCost != null) ...[
          Text(
            'cost ${node.totalCost!.toStringAsFixed(1)}',
            style: AppTheme.mono(
              size: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _SlowestPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'slowest',
        style: AppTheme.mono(
          size: 9.5,
          color: AppColors.warning,
          weight: FontWeight.w600,
        ).copyWith(letterSpacing: 0.4),
      ),
    );
  }
}

class _PercentChip extends StatelessWidget {
  const _PercentChip({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (pct >= 60) {
      color = AppColors.warning;
    } else if (pct >= 25) {
      color = AppColors.accent;
    } else {
      color = AppColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$pct%',
        style: AppTheme.mono(
          size: 10,
          color: color,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NodeBadge extends StatelessWidget {
  const _NodeBadge({required this.type, required this.small});
  final String type;
  final bool small;

  /// Tint by operation family so the eye picks up joins / scans / sorts
  /// without reading the label.
  Color _color() {
    final t = type.toLowerCase();
    if (t.contains('join')) return AppColors.accent;
    if (t.contains('scan')) return AppColors.sqlKeyword;
    if (t.contains('aggregate') ||
        t.contains('group') ||
        t.contains('window')) {
      return AppColors.sqlFunction;
    }
    if (t.contains('sort') || t.contains('limit')) {
      return AppColors.sqlString;
    }
    if (t.contains('hash')) return AppColors.accent;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final size = small ? 10.5 : 12.0;
    final pad = small ? 5.0 : 7.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type,
        style: AppTheme.mono(
          size: size,
          color: color,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTheme.mono(size: 10.5, color: AppColors.textPrimary),
          children: [
            TextSpan(
              text: '$label ',
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textMuted,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.node, required this.pct});
  final _PlanNode node;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    final actual = node.actualRows;
    final est = node.planRows;
    if (actual != null) {
      segments.add(_Metric(label: 'rows', value: _fmt(actual)));
      if (est != null) {
        segments.add(_Metric(
          label: 'estimated',
          value: _fmt(est),
          muted: true,
        ));
      }
    } else if (est != null) {
      segments.add(_Metric(label: 'rows est', value: _fmt(est)));
    }
    final loops = node.actualLoops;
    if (loops != null && loops > 1) {
      segments.add(_Metric(label: 'loops', value: '$loops'));
    }

    final mismatch = node.mismatch;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          segments[i],
          if (i != segments.length - 1) const SizedBox(width: 12),
        ],
        if (mismatch != _Mismatch.none) ...[
          if (segments.isNotEmpty) const SizedBox(width: 12),
          _MismatchChip(severity: mismatch, actual: actual, estimated: est),
        ],
      ],
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.muted = false,
  });
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: AppTheme.mono(size: 11, color: AppColors.textMuted),
        children: [
          TextSpan(
            text: value,
            style: AppTheme.mono(
              size: 11,
              color:
                  muted ? AppColors.textMuted : AppColors.textPrimary,
              weight: muted ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
    );
  }
}

class _MismatchChip extends StatelessWidget {
  const _MismatchChip({
    required this.severity,
    required this.actual,
    required this.estimated,
  });

  final _Mismatch severity;
  final int? actual;
  final int? estimated;

  @override
  Widget build(BuildContext context) {
    final color = severity == _Mismatch.severe
        ? AppColors.error
        : AppColors.warning;
    final label = severity == _Mismatch.severe
        ? 'estimate way off'
        : 'estimate off';
    final tip = (actual == null || estimated == null)
        ? label
        : '$label · expected $estimated, got $actual';
    return Tooltip(
      message: tip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_outlined, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTheme.mono(
                size: 9.5,
                color: color,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeBar extends StatelessWidget {
  const _TimeBar({required this.fraction, required this.isSlowest});
  final double fraction;
  final bool isSlowest;

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0).toDouble();
    final fillColor = isSlowest
        ? AppColors.warning
        : clamped >= 0.6
            ? AppColors.warning
            : clamped >= 0.25
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: 0.55);
    return Stack(
      children: [
        Container(
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined,
              size: 12, color: AppColors.warning),
          const SizedBox(width: 6),
          Text(
            'Plan is for an earlier run — re-fetching.',
            style: AppTheme.mono(size: 11, color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}
