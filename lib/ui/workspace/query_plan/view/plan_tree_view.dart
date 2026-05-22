import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../analysis/advice_engine.dart';
import '../analysis/plan_metrics.dart';
import '../parsing/plan_parser.dart';
import 'plan_advice_panel.dart';
import 'plan_node_card.dart';
import 'plan_states.dart';
import 'plan_summary_header.dart';

/// Renders a parsed `EXPLAIN (FORMAT JSON)` payload: a stale banner when
/// the plan no longer matches the last run, the summary header, the
/// advice panel, then a card per node.
class PlanTreeView extends StatelessWidget {
  const PlanTreeView({
    super.key,
    required this.planJson,
    required this.stale,
    required this.onRerun,
  });

  final Map<String, dynamic> planJson;
  final bool stale;
  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    final root = parsePlan(planJson);
    if (root == null) {
      return const EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Plan was empty',
        message: 'Postgres returned a result with no Plan node.',
      );
    }
    final rows = flatten(root);
    final metrics = computeMetrics(rows);
    final planningMs = (planJson['Planning Time'] as num?)?.toDouble();
    final executionMs = (planJson['Execution Time'] as num?)?.toDouble();
    final analyzed = executionMs != null;
    final advice = runAdvice(
      root: root,
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
          if (stale) PlanStaleBanner(onRerun: onRerun),
          PlanSummaryHeader(
            planningMs: planningMs,
            executionMs: executionMs,
            totalNodes: rows.length,
            slowest: metrics.hottest,
          ),
          const SizedBox(height: 10),
          PlanAdvicePanel(items: advice, analyzed: analyzed),
          const SizedBox(height: 4),
          for (final node in rows)
            PlanNodeCard(
              node: node,
              totalMs: metrics.maxSelfMs,
              isSlowest: identical(node, metrics.hottest),
            ),
        ],
      ),
    );
  }
}
