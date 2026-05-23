import 'package:flutter/material.dart';

import '../../../../state/app_globals.dart';
import '../../../../state/workspace_tab.dart';
import 'plan_states.dart';
import 'plan_tree_view.dart';

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

  void _runExplain() {
    if ((tab.lastRunSql ?? '').trim().isEmpty) return;
    appState.tabsController.loadQueryPlan(tab);
  }

  @override
  Widget build(BuildContext context) {
    if (tab.planLoading) return const PlanSpinner();
    // The plan always describes `lastRunSql` — the query the Results tab
    // shows — so it can't be requested before the query has been run.
    final canExplain = (tab.lastRunSql ?? '').trim().isNotEmpty;
    if (tab.planError != null) {
      return PlanError(
        message: tab.planError!,
        onRetry: canExplain ? _runExplain : null,
      );
    }
    final json = tab.planJson;
    if (json == null) {
      return PlanSuggestion(
        enabled: canExplain,
        onRun: canExplain ? _runExplain : null,
      );
    }
    final stale = tab.lastRunSql != null && tab.planSourceSql != tab.lastRunSql;
    return PlanTreeView(
      planJson: json,
      stale: stale,
      onRerun: _runExplain,
    );
  }
}
