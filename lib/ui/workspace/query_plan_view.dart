import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Renders a Postgres `EXPLAIN (FORMAT JSON)` plan as an indented tree.
///
/// Triggers [AppState.loadQueryPlan] on first paint when there's a
/// [QueryTab.lastRunSql] but no cached plan. Re-fetch happens on tab
/// re-entry when [QueryTab.planSourceSql] no longer matches the latest
/// run.
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
    // Defer to next frame so we don't notifyListeners during build.
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
    if (tab.lastRunSql == null) {
      // Nothing's been run yet. If the editor has SQL, offer to run it
      // through EXPLAIN directly — no need to execute the query first.
      final hasSql = tab.sql.trim().isNotEmpty;
      if (tab.planLoading) {
        return _Spinner();
      }
      if (tab.planError != null) {
        return _PlanError(message: tab.planError!);
      }
      if (tab.planJson != null) {
        // We have a plan from "Run as EXPLAIN" even though no real run
        // happened — fall through to the tree.
      } else {
        return _PlanSuggestion(
          enabled: hasSql,
          onRun: hasSql ? _runAsExplain : null,
        );
      }
    }
    if (tab.planLoading) {
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
    if (tab.planError != null) {
      return _PlanError(message: tab.planError!);
    }
    final json = tab.planJson;
    if (json == null) {
      return const EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No plan',
        message: 'Switch to the Plan tab after a run to fetch its plan.',
      );
    }
    final stale = tab.lastRunSql != null &&
        tab.planSourceSql != tab.lastRunSql;
    return _PlanTree(planJson: json, stale: stale, tab: tab);
  }
}

class _Spinner extends StatelessWidget {
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

/// Empty state for the Plan tab before any plan has been computed —
/// offers to run the editor's current SQL through EXPLAIN directly so
/// the user doesn't have to execute the query first.
class _PlanSuggestion extends StatelessWidget {
  const _PlanSuggestion({required this.enabled, required this.onRun});

  final bool enabled;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 28, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(
              'No plan yet',
              style: AppTheme.ui(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              enabled
                  ? 'Plan the SQL in the editor through EXPLAIN — no '
                      'execution required for read-only statements.'
                  : 'Write SQL in the editor, then come back here to '
                      'see its plan.',
              textAlign: TextAlign.center,
              style: AppTheme.mono(size: 11.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
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
              Icon(Icons.error_outline,
                  size: 14, color: AppColors.error),
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

class _PlanTree extends StatelessWidget {
  const _PlanTree({
    required this.planJson,
    required this.stale,
    required this.tab,
  });

  final Map<String, dynamic> planJson;
  final bool stale;
  final QueryTab tab;

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
    final rows = <_PlanRowData>[];
    _flatten(root, 0, const [], rows);
    final maxMetric = rows.fold<double>(0, (m, r) {
      final v = r.metric;
      return v > m ? v : m;
    });
    final planningMs = (planJson['Planning Time'] as num?)?.toDouble();
    final executionMs = (planJson['Execution Time'] as num?)?.toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stale) const _StaleBanner(),
          if (planningMs != null || executionMs != null)
            _SummaryStrip(planning: planningMs, execution: executionMs),
          const SizedBox(height: 4),
          for (final r in rows)
            _PlanRow(data: r, maxMetric: maxMetric),
        ],
      ),
    );
  }

  /// Walks the plan tree depth-first, producing one [_PlanRowData] per node
  /// with the ancestor-is-last flags we need to draw `├─ │ └─` connectors.
  void _flatten(
    Map<String, dynamic> node,
    int depth,
    List<bool> ancestorIsLast,
    List<_PlanRowData> out,
  ) {
    final children = (node['Plans'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    out.add(_PlanRowData(
      node: node,
      depth: depth,
      ancestorIsLast: ancestorIsLast,
    ));
    for (var i = 0; i < children.length; i++) {
      final isLast = i == children.length - 1;
      _flatten(
        children[i],
        depth + 1,
        [...ancestorIsLast, isLast],
        out,
      );
    }
  }
}

class _PlanRowData {
  _PlanRowData({
    required this.node,
    required this.depth,
    required this.ancestorIsLast,
  });

  final Map<String, dynamic> node;
  final int depth;
  final List<bool> ancestorIsLast;

  String get nodeType => node['Node Type'] as String? ?? 'Unknown';
  String? get relation => node['Relation Name'] as String?;
  String? get indexName => node['Index Name'] as String?;
  String? get alias => node['Alias'] as String?;
  double? get actualTotalTime =>
      (node['Actual Total Time'] as num?)?.toDouble();
  int? get actualRows => (node['Actual Rows'] as num?)?.toInt();
  int? get actualLoops => (node['Actual Loops'] as num?)?.toInt();
  int? get planRows => (node['Plan Rows'] as num?)?.toInt();
  double? get totalCost => (node['Total Cost'] as num?)?.toDouble();

  /// Time the bar visualisation is proportional to. Prefer ANALYZE's real
  /// time (per-loop × loops); fall back to planner-estimated cost so the
  /// bar still conveys relative weight on plain EXPLAIN.
  double get metric {
    final t = actualTotalTime;
    if (t != null) return t * (actualLoops ?? 1);
    return totalCost ?? 0;
  }

  String? get extraLine {
    final parts = <String>[];
    final filter = node['Filter'] as String?;
    if (filter != null) parts.add('Filter: $filter');
    final cond = node['Index Cond'] as String? ??
        node['Hash Cond'] as String? ??
        node['Merge Cond'] as String? ??
        node['Join Filter'] as String?;
    if (cond != null) parts.add(cond);
    final sortKey = node['Sort Key'] as List?;
    if (sortKey != null && sortKey.isNotEmpty) {
      parts.add('Sort Key: ${sortKey.join(', ')}');
    }
    final groupKey = node['Group Key'] as List?;
    if (groupKey != null && groupKey.isNotEmpty) {
      parts.add('Group Key: ${groupKey.join(', ')}');
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.data, required this.maxMetric});

  final _PlanRowData data;
  final double maxMetric;

  @override
  Widget build(BuildContext context) {
    final fraction = maxMetric > 0 ? (data.metric / maxMetric) : 0.0;
    final extra = data.extraLine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TreeConnector(data: data),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NodeHeader(data: data),
                    if (extra != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          extra,
                          style: AppTheme.mono(
                            size: 10.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: _TimeBar(fraction: fraction),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: _RowMetrics(data: data),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Draws `│   ├─` style indent connectors using monospace box-drawing
/// glyphs. Each ancestor depth contributes either a vertical bar (more
/// children to come) or whitespace (last child in that branch).
class _TreeConnector extends StatelessWidget {
  const _TreeConnector({required this.data});

  final _PlanRowData data;

  @override
  Widget build(BuildContext context) {
    if (data.depth == 0) return const SizedBox(width: 0);
    final buf = StringBuffer();
    for (var i = 0; i < data.depth - 1; i++) {
      buf.write(data.ancestorIsLast[i] ? '    ' : '│   ');
    }
    final isLast = data.ancestorIsLast.isNotEmpty &&
        data.ancestorIsLast.last;
    buf.write(isLast ? '└── ' : '├── ');
    return Text(
      buf.toString(),
      style: AppTheme.mono(
        size: 11.5,
        color: AppColors.text4,
      ),
    );
  }
}

class _NodeHeader extends StatelessWidget {
  const _NodeHeader({required this.data});
  final _PlanRowData data;

  @override
  Widget build(BuildContext context) {
    final targetParts = <String>[];
    if (data.indexName != null) targetParts.add('using ${data.indexName}');
    if (data.relation != null) {
      targetParts.add(data.alias != null && data.alias != data.relation
          ? 'on ${data.relation} ${data.alias}'
          : 'on ${data.relation}');
    }
    final target = targetParts.join(' ');
    return RichText(
      text: TextSpan(
        style: AppTheme.mono(size: 12, color: AppColors.textPrimary),
        children: [
          TextSpan(
            text: data.nodeType,
            style: AppTheme.mono(
              size: 12,
              color: _colorForNode(data.nodeType),
              weight: FontWeight.w600,
            ),
          ),
          if (target.isNotEmpty)
            TextSpan(
              text: '  $target',
              style: AppTheme.mono(
                size: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  /// Tint node types by category so scans, joins and aggregates stand out
  /// at a glance.
  Color _colorForNode(String type) {
    final t = type.toLowerCase();
    if (t.contains('join')) return AppColors.accent;
    if (t.contains('scan')) return AppColors.sqlKeyword;
    if (t.contains('aggregate') || t.contains('group')) {
      return AppColors.sqlFunction;
    }
    if (t.contains('sort') || t.contains('limit')) {
      return AppColors.sqlString;
    }
    return AppColors.textPrimary;
  }
}

class _TimeBar extends StatelessWidget {
  const _TimeBar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0).toDouble();
    // Color the bar by intensity — dim when proportionally cheap, hotter
    // (toward accent) when proportionally expensive.
    final intense = Color.lerp(
      AppColors.surfaceAlt,
      AppColors.accent,
      clamped,
    )!;
    return Stack(
      children: [
        Container(
          height: 4,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            height: 4,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: intense,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}

class _RowMetrics extends StatelessWidget {
  const _RowMetrics({required this.data});
  final _PlanRowData data;

  @override
  Widget build(BuildContext context) {
    final t = data.actualTotalTime;
    final rows = data.actualRows;
    final estRows = data.planRows;
    String primary;
    String? secondary;
    if (t != null) {
      final total = t * (data.actualLoops ?? 1);
      primary = '${total.toStringAsFixed(2)} ms';
      if (rows != null) {
        secondary = estRows != null && estRows != rows
            ? '$rows rows · est $estRows'
            : '$rows rows';
      }
    } else {
      primary = 'cost ${data.totalCost?.toStringAsFixed(1) ?? '?'}';
      if (estRows != null) secondary = 'est $estRows rows';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          primary,
          style: AppTheme.mono(
            size: 11,
            color: AppColors.textPrimary,
            weight: FontWeight.w600,
          ),
        ),
        if (secondary != null)
          Text(
            secondary,
            style: AppTheme.mono(size: 10, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({this.planning, this.execution});
  final double? planning;
  final double? execution;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (planning != null)
            _SummaryStat(label: 'planning', valueMs: planning!),
          if (planning != null && execution != null)
            const SizedBox(width: 12),
          if (execution != null)
            _SummaryStat(label: 'execution', valueMs: execution!),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.label, required this.valueMs});
  final String label;
  final double valueMs;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: AppTheme.mono(size: 11, color: AppColors.textMuted),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: '${valueMs.toStringAsFixed(2)} ms',
            style: AppTheme.mono(
              size: 11,
              color: AppColors.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: Radii.brSm,
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
