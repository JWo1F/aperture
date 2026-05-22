import '../../../../models/count_format.dart';
import '../model/advice.dart';
import '../model/plan_node.dart';
import 'advice_rules.dart';

/// Signature for a per-node advice rule. Pure: returns null when the rule
/// doesn't apply, an [Advice] when it fires. The caller walks the tree
/// once and offers each node to every rule.
typedef AdviceRule = Advice? Function(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
);

/// Ordered list of every rule shipped with the app. Adding an 11th rule
/// means writing a top-level `Advice? Function(PlanNode, PlanNode?, bool)`
/// in `advice_rules.dart` and appending it here.
///
/// The estimate-mismatch detection is intentionally *not* a rule — it
/// keeps the single worst offender per plan instead of one per node, so
/// it's handled separately by [_collectMismatchCandidates] below.
const List<AdviceRule> adviceRules = [
  ruleSeqScanSelectiveFilter,
  ruleSortSpilledToDisk,
  ruleHashBatched,
  ruleTempSpill,
  ruleIndexOnlyHeapFetches,
  ruleNestedLoopUnindexedInner,
  ruleFullSortUnderLimit,
  ruleLikeFilterNoIndex,
  ruleWorkersCapped,
];

/// Runs every rule against every node in the tree (plus the mismatch
/// aggregator) and returns advice in priority order. When [analyzed] is
/// false, rules that depend on actual rows/times silently produce nothing
/// and the caller can show an "estimates only" banner instead.
List<Advice> runAdvice({
  required PlanNode root,
  required bool analyzed,
  required double? totalExecutionMs,
}) {
  final out = <Advice>[];
  final mismatches = <MismatchCandidate>[];

  _walk(root, null, analyzed, out, mismatches);

  // Estimate-mismatch is per-node noisy: keep only the single worst
  // offender (largest fold) to avoid drowning the panel.
  if (mismatches.isNotEmpty) {
    mismatches.sort((a, b) => b.fold.compareTo(a.fold));
    out.add(mismatches.first.toAdvice());
  }

  if (out.isEmpty && analyzed) {
    out.add(
      Advice(
        severity: AdviceSeverity.good,
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

void _walk(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
  List<Advice> out,
  List<MismatchCandidate> mismatches,
) {
  for (final rule in adviceRules) {
    final advice = rule(node, parent, analyzed);
    if (advice != null) out.add(advice);
  }
  final candidate = mismatchCandidateOf(node, analyzed);
  if (candidate != null) mismatches.add(candidate);
  for (final c in node.children) {
    _walk(c, node, analyzed, out, mismatches);
  }
}

/// Human-readable size string for a kB count. `Sort Space Used` is kB,
/// and we convert `Temp * Blocks` (8 KB pages) to kB before calling.
String formatKb(int kb) {
  if (kb < 1024) return '$kb kB';
  if (kb < 1024 * 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
  return '${(kb / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// `123,456`-style — re-exported from the shared count formatter so rule
/// authors don't have to remember which package to import.
String formatInt(int n) => withCommas(n);
