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
///
/// EXPLAIN is never issued automatically. For read queries the plan uses
/// EXPLAIN ANALYZE, which executes the statement for real, so every
/// round-trip is gated behind an explicit button press — selecting the
/// Plan tab only shows the prompt.
class QueryPlanView extends StatelessWidget {
  const QueryPlanView({super.key, required this.tab});

  final QueryTab tab;

  void _runExplain(BuildContext context) {
    final sql = tab.sql.trim();
    if (sql.isEmpty) return;
    context.read<AppState>().loadQueryPlan(tab, sqlOverride: sql);
  }

  @override
  Widget build(BuildContext context) {
    if (tab.planLoading) return const _Spinner();
    if (tab.planError != null) {
      return _PlanError(
        message: tab.planError!,
        onRetry: tab.sql.trim().isNotEmpty ? () => _runExplain(context) : null,
      );
    }
    final json = tab.planJson;
    if (json == null) {
      return _PlanSuggestion(
        enabled: tab.sql.trim().isNotEmpty,
        onRun: tab.sql.trim().isNotEmpty ? () => _runExplain(context) : null,
      );
    }
    final stale = tab.lastRunSql != null && tab.planSourceSql != tab.lastRunSql;
    return _PlanTree(
      planJson: json,
      stale: stale,
      onRerun: () => _runExplain(context),
    );
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
            Icon(
              Icons.account_tree_outlined,
              size: 30,
              color: AppColors.textMuted,
            ),
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
  const _PlanError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Run again',
              icon: Icons.refresh,
              onPressed: onRetry,
            ),
          ],
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
  'WorkTable Scan': 'Iterates the working set of a recursive WITH clause.',
  'Foreign Scan': 'Reads rows from a foreign (remote) table.',
  'Nested Loop':
      'For each row on the left, finds the matching rows on the right.',
  'Hash Join':
      'Builds an in-memory hash of one side and probes it from the other.',
  'Merge Join':
      'Merges two sorted inputs together, the way mergesort merges runs.',
  'Hash': 'Builds an in-memory hash table to feed the join above it.',
  'Materialize': 'Caches its input so the parent can scan it more than once.',
  'Sort': 'Sorts its input by the requested keys.',
  'Incremental Sort': 'Sorts within groups that are already partly sorted.',
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
  const _PlanTree({
    required this.planJson,
    required this.stale,
    required this.onRerun,
  });

  final Map<String, dynamic> planJson;
  final bool stale;
  final VoidCallback onRerun;

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
    final analyzed = executionMs != null;
    final advice = _deriveAdvice(
      planJson: planJson,
      analyzed: analyzed,
      totalExecutionMs: executionMs,
    );

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
          if (stale) _StaleBanner(onRerun: onRerun),
          _SummaryHeader(
            planningMs: planningMs,
            executionMs: executionMs,
            totalNodes: rows.length,
            slowest: slowest,
          ),
          const SizedBox(height: 10),
          _AdviceSection(items: advice, analyzed: analyzed),
          const SizedBox(height: 4),
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
    out.add(
      _PlanNode(
        node: node,
        depth: depth,
        ancestorIsLast: ancestorIsLast,
        parentType: parentType,
      ),
    );
    final children =
        (node['Plans'] as List?)?.cast<Map<String, dynamic>>() ??
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

  bool get isLastChild => ancestorIsLast.isNotEmpty && ancestorIsLast.last;

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
  });

  final double? planningMs;
  final double? executionMs;
  final int totalNodes;
  final _PlanNode slowest;

  @override
  Widget build(BuildContext context) {
    final subtitle = totalNodes == 1
        ? 'Single-node plan'
        : '$totalNodes operations · slowest is ${slowest.type}';
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
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTheme.mono(size: 11, color: AppColors.textMuted),
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
                style: AppTheme.mono(size: 11, color: AppColors.textMuted),
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
                child: _IndentRail(node: node, indentStep: _indentStep),
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
                    _CardHeader(node: node, pct: pct, isSlowest: isSlowest),
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
    final isLast = ancestorIsLast.isNotEmpty && ancestorIsLast.last;

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
              style: AppTheme.mono(size: 12, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (isSlowest) ...[const SizedBox(width: 8), _SlowestPill()],
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
            style: AppTheme.mono(size: 11.5, color: AppColors.textSecondary),
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
        style: AppTheme.mono(size: 10, color: color, weight: FontWeight.w600),
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
        style: AppTheme.mono(size: size, color: color, weight: FontWeight.w600),
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
              style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
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
        segments.add(
          _Metric(label: 'estimated', value: _fmt(est), muted: true),
        );
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
  const _Metric({required this.label, required this.value, this.muted = false});

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
              color: muted ? AppColors.textMuted : AppColors.textPrimary,
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
  const _StaleBanner({required this.onRerun});

  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 12,
            color: AppColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Plan is for an earlier run.',
              style: AppTheme.mono(size: 11, color: AppColors.warning),
            ),
          ),
          AppButton(
            label: 'Re-run EXPLAIN',
            icon: Icons.refresh,
            onPressed: onRerun,
          ),
        ],
      ),
    );
  }
}

// --- advice ---------------------------------------------------------------

enum _AdviceSeverity { good, info, warn, critical }

class _PlanAdvice {
  _PlanAdvice({
    required this.severity,
    required this.title,
    required this.body,
  });

  final _AdviceSeverity severity;
  final String title;
  final String body;
}

/// Walks the plan tree and returns advice items in priority order.
///
/// Each rule fires from one EXPLAIN field combination; together they
/// surface the most common "this looks slow because…" patterns without
/// needing catalog lookups. When ANALYZE wasn't used, rules that depend
/// on actual rows / times stay silent and the empty result becomes an
/// "estimates only" notice in [_AdviceSection].
List<_PlanAdvice> _deriveAdvice({
  required Map<String, dynamic> planJson,
  required bool analyzed,
  required double? totalExecutionMs,
}) {
  final root = planJson['Plan'] as Map<String, dynamic>?;
  if (root == null) return const [];
  final out = <_PlanAdvice>[];
  final mismatchCandidates = <_MismatchCandidate>[];
  _walkAdvice(root, null, analyzed, out, mismatchCandidates);

  // Estimate-mismatch is per-node noisy: keep only the single worst
  // offender (largest fold) to avoid drowning the panel.
  if (mismatchCandidates.isNotEmpty) {
    mismatchCandidates.sort((a, b) => b.fold.compareTo(a.fold));
    out.add(mismatchCandidates.first.toAdvice());
  }

  if (out.isEmpty && analyzed) {
    out.add(
      _PlanAdvice(
        severity: _AdviceSeverity.good,
        title: 'Plan looks healthy',
        body: totalExecutionMs == null
            ? 'No bottlenecks worth flagging — nothing actionable here.'
            : 'Finished in ${totalExecutionMs.toStringAsFixed(2)} ms with no '
                  'obvious bottlenecks.',
      ),
    );
  }
  return out;
}

class _MismatchCandidate {
  _MismatchCandidate({
    required this.type,
    required this.relation,
    required this.actual,
    required this.estimated,
    required this.fold,
  });

  final String type;
  final String? relation;
  final int actual;
  final int estimated;
  final double fold;

  _PlanAdvice toAdvice() {
    final fixHint = relation != null
        ? 'Run `ANALYZE $relation` to refresh statistics — the planner is '
              'choosing strategies blind right now.'
        : 'Refresh table stats with `ANALYZE` so the planner can pick a '
              'better strategy.';
    return _PlanAdvice(
      severity: _AdviceSeverity.warn,
      title: 'Planner estimate off by ${fold.round()}× on $type',
      body:
          'Expected ${_fmtAdviceInt(estimated)} rows, got '
          '${_fmtAdviceInt(actual)}. $fixHint',
    );
  }
}

void _walkAdvice(
  Map<String, dynamic> node,
  Map<String, dynamic>? parent,
  bool analyzed,
  List<_PlanAdvice> out,
  List<_MismatchCandidate> mismatchOut,
) {
  final type = node['Node Type'] as String? ?? '';
  final actualRows = (node['Actual Rows'] as num?)?.toInt();
  final planRows = (node['Plan Rows'] as num?)?.toInt();
  final rowsRemoved = (node['Rows Removed by Filter'] as num?)?.toInt();
  final relation = node['Relation Name'] as String?;
  final schema = node['Schema'] as String?;
  final filter = node['Filter'] as String?;

  String? qualified() {
    if (relation == null) return null;
    if (schema == null || schema == 'public') return relation;
    return '$schema.$relation';
  }

  // 1. Seq Scan with selective filter on a large table.
  if (type == 'Seq Scan' &&
      rowsRemoved != null &&
      actualRows != null &&
      qualified() != null) {
    final total = rowsRemoved + actualRows;
    if (total >= 10000 && rowsRemoved >= actualRows * 9) {
      out.add(
        _PlanAdvice(
          severity: _AdviceSeverity.warn,
          title: 'Seq Scan with selective filter on ${qualified()}',
          body:
              'Read ${_fmtAdviceInt(total)} rows and discarded '
              '${_fmtAdviceInt(rowsRemoved)} of them. An index on the '
              'filtered column(s) would let Postgres skip most of the table.',
        ),
      );
    }
  }

  // 2. Sort spilled to disk.
  if (type == 'Sort' || type == 'Incremental Sort') {
    final spaceType = node['Sort Space Type'] as String?;
    final spaceUsedKb = (node['Sort Space Used'] as num?)?.toInt();
    if (spaceType == 'Disk') {
      out.add(
        _PlanAdvice(
          severity: _AdviceSeverity.critical,
          title: '$type spilled to disk',
          body:
              'Wrote ${spaceUsedKb == null ? "data" : _fmtKb(spaceUsedKb)} '
              'to temp files. Raise `work_mem` for this session, or return '
              'fewer rows before sorting.',
        ),
      );
    }
  }

  // 3. Hash join split into batches (work_mem too small).
  if (type == 'Hash') {
    final batches = (node['Hash Batches'] as num?)?.toInt();
    if (batches != null && batches > 1) {
      out.add(
        _PlanAdvice(
          severity: _AdviceSeverity.warn,
          title: 'Hash table did not fit in memory',
          body:
              'Postgres split the hash into $batches batches because '
              '`work_mem` was too small. Raise `work_mem` if this query is '
              'on the hot path.',
        ),
      );
    }
  }

  // 4. Temp blocks spilled by a non-Sort/Hash node (catch-all).
  final tempBlocks =
      ((node['Temp Read Blocks'] as num?)?.toInt() ?? 0) +
      ((node['Temp Written Blocks'] as num?)?.toInt() ?? 0);
  if (tempBlocks > 0 && type != 'Sort' && type != 'Hash') {
    out.add(
      _PlanAdvice(
        severity: _AdviceSeverity.warn,
        title: '$type spilled to temp files',
        body:
            'Used ${_fmtKb(tempBlocks * 8)} of temp files. Raise `work_mem` '
            'or break the query into smaller pieces.',
      ),
    );
  }

  // 5. Index Only Scan still hits the heap (stale visibility map).
  if (type == 'Index Only Scan') {
    final heap = (node['Heap Fetches'] as num?)?.toInt() ?? 0;
    if (heap > 0 && actualRows != null && heap > actualRows * 0.05) {
      out.add(
        _PlanAdvice(
          severity: _AdviceSeverity.info,
          title: 'Index Only Scan still reads the table',
          body:
              'Postgres had to fetch from the heap ${_fmtAdviceInt(heap)} '
              'times because the visibility map is stale. '
              '${qualified() != null ? "Run `VACUUM ${qualified()}` to "
                        "restore true index-only behavior." : "VACUUM the table to "
                        "restore true index-only behavior."}',
        ),
      );
    }
  }

  // 6. Estimate severely off. Only collect candidates here; the caller
  //    keeps the single worst one to avoid drowning the panel.
  if (analyzed && actualRows != null && planRows != null) {
    final a = actualRows == 0 ? 1 : actualRows;
    final e = planRows == 0 ? 1 : planRows;
    final fold = a > e ? a / e : e / a;
    if (fold >= 10 && (actualRows > 100 || qualified() != null)) {
      mismatchOut.add(
        _MismatchCandidate(
          type: type,
          relation: qualified(),
          actual: actualRows,
          estimated: planRows,
          fold: fold.toDouble(),
        ),
      );
    }
  }

  // 7. Nested Loop driving a non-indexed inner side with a big outer.
  if (type == 'Nested Loop') {
    final children =
        (node['Plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (children.length == 2) {
      final outer = children[0];
      final inner = children[1];
      final outerRows = (outer['Actual Rows'] as num?)?.toInt() ?? 0;
      final outerLoops = (outer['Actual Loops'] as num?)?.toInt() ?? 1;
      final outerTotal = outerRows * outerLoops;
      final innerType = inner['Node Type'] as String? ?? '';
      final innerIndexed = innerType.contains('Index');
      if (outerTotal >= 1000 && !innerIndexed) {
        out.add(
          _PlanAdvice(
            severity: _AdviceSeverity.warn,
            title: 'Nested Loop without an index on the inner side',
            body:
                'Outer side feeds ${_fmtAdviceInt(outerTotal)} rows into a '
                '$innerType inner side. A Hash/Merge join — or an index on '
                'the join key — would scale much better.',
          ),
        );
      }
    }
  }

  // 8. Full Sort under a Limit (Top-N would be faster).
  if (type == 'Sort' && parent != null) {
    final parentType = parent['Node Type'];
    final method = node['Sort Method'] as String? ?? '';
    if (parentType == 'Limit' && !method.contains('top-N')) {
      out.add(
        _PlanAdvice(
          severity: _AdviceSeverity.info,
          title: 'Full sort feeding a LIMIT',
          body:
              'Sort processed all input rows before LIMIT trimmed it. An '
              'index matching the ORDER BY would let Postgres stop early.',
        ),
      );
    }
  }

  // 9. LIKE/ILIKE filter on a heap scan large enough to matter.
  if (filter != null && (type == 'Seq Scan' || type == 'Bitmap Heap Scan')) {
    final hasLike =
        filter.contains('~~') ||
        filter.toLowerCase().contains(' like ') ||
        filter.toLowerCase().contains(' ilike ');
    final scanned = (actualRows ?? 0) + (rowsRemoved ?? 0);
    if (hasLike && scanned >= 1000) {
      out.add(
        _PlanAdvice(
          severity: _AdviceSeverity.info,
          title: 'Pattern match runs without an index',
          body:
              'A LIKE/ILIKE filter is being evaluated row-by-row. A '
              '`pg_trgm` GIN or GIST index on the column would let Postgres '
              'narrow the rows first.',
        ),
      );
    }
  }

  // 10. Parallelism capped below planned.
  final workersPlanned = (node['Workers Planned'] as num?)?.toInt();
  final workersLaunched = (node['Workers Launched'] as num?)?.toInt();
  if (workersPlanned != null &&
      workersLaunched != null &&
      workersLaunched < workersPlanned) {
    out.add(
      _PlanAdvice(
        severity: _AdviceSeverity.info,
        title: 'Parallel workers capped',
        body:
            'Postgres planned $workersPlanned workers but only launched '
            '$workersLaunched. `max_parallel_workers` (or '
            '`max_parallel_workers_per_gather`) is the ceiling.',
      ),
    );
  }

  final children =
      (node['Plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  for (final c in children) {
    _walkAdvice(c, node, analyzed, out, mismatchOut);
  }
}

String _fmtAdviceInt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Human-readable size string for a kB count. `Sort Space Used` is kB,
/// and we convert `Temp * Blocks` (8 KB pages) to kB before calling.
String _fmtKb(int kb) {
  if (kb < 1024) return '$kb kB';
  if (kb < 1024 * 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
  return '${(kb / 1024 / 1024).toStringAsFixed(2)} GB';
}

class _AdviceSection extends StatelessWidget {
  const _AdviceSection({required this.items, required this.analyzed});

  final List<_PlanAdvice> items;
  final bool analyzed;

  @override
  Widget build(BuildContext context) {
    final effective = items.isEmpty && !analyzed
        ? [
            _PlanAdvice(
              severity: _AdviceSeverity.info,
              title: 'Plan shown without execution',
              body:
                  'This statement was not run under ANALYZE, so costs are '
                  'estimates and row counts are guesses. Run it as a SELECT '
                  'to see measured times and targeted advice.',
            ),
          ]
        : items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in effective)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _AdviceCard(advice: a),
          ),
      ],
    );
  }
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.advice});

  final _PlanAdvice advice;

  @override
  Widget build(BuildContext context) {
    final color = switch (advice.severity) {
      _AdviceSeverity.critical => AppColors.error,
      _AdviceSeverity.warn => AppColors.warning,
      _AdviceSeverity.info => AppColors.accent,
      _AdviceSeverity.good => AppColors.success,
    };
    final icon = switch (advice.severity) {
      _AdviceSeverity.critical => Icons.error_outline,
      _AdviceSeverity.warn => Icons.warning_amber_outlined,
      _AdviceSeverity.info => Icons.lightbulb_outline,
      _AdviceSeverity.good => Icons.check_circle_outline,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: Radii.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  advice.title,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  advice.body,
                  style: AppTheme.mono(
                    size: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
