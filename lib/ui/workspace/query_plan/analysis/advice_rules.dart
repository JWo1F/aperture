import '../model/advice.dart';
import '../model/plan_node.dart';
import 'advice_engine.dart';

/// 1. Seq Scan reading a large table where a filter throws most rows
/// away. The classic "missing index" smell — when 90%+ of the rows are
/// discarded after the scan and the table is at least 10k rows total,
/// an index on the filtered column(s) would prune most of the work.
Advice? ruleSeqScanSelectiveFilter(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
) {
  if (node.kind != 'Seq Scan') return null;
  final actualRows = node.actualRows;
  final rowsRemoved = (node.raw['Rows Removed by Filter'] as num?)?.toInt();
  final qualified = node.qualifiedRelation;
  if (actualRows == null || rowsRemoved == null || qualified == null) {
    return null;
  }
  final total = rowsRemoved + actualRows;
  if (total < 10000) return null;
  if (rowsRemoved < actualRows * 9) return null;
  return Advice(
    severity: AdviceSeverity.warn,
    title: 'Seq Scan with selective filter on $qualified',
    body:
        'Read ${formatInt(total)} rows and discarded '
        '${formatInt(rowsRemoved)} of them. An index on the '
        'filtered column(s) would let Postgres skip most of the table.',
  );
}

/// 2. Sort node spilled to disk — `work_mem` wasn't enough so the sort
/// wrote temp files. Raise `work_mem` or shrink the input.
Advice? ruleSortSpilledToDisk(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
) {
  if (node.kind != 'Sort' && node.kind != 'Incremental Sort') return null;
  final spaceType = node.raw['Sort Space Type'] as String?;
  if (spaceType != 'Disk') return null;
  final spaceUsedKb = (node.raw['Sort Space Used'] as num?)?.toInt();
  return Advice(
    severity: AdviceSeverity.critical,
    title: '${node.kind} spilled to disk',
    body:
        'Wrote ${spaceUsedKb == null ? "data" : formatKb(spaceUsedKb)} '
        'to temp files. Raise `work_mem` for this session, or return '
        'fewer rows before sorting.',
  );
}

/// 3. Hash table didn't fit in `work_mem`, so Postgres split it into
/// multiple batches — each probe row hashes against every batch.
Advice? ruleHashBatched(PlanNode node, PlanNode? parent, bool analyzed) {
  if (node.kind != 'Hash') return null;
  final batches = (node.raw['Hash Batches'] as num?)?.toInt();
  if (batches == null || batches <= 1) return null;
  return Advice(
    severity: AdviceSeverity.warn,
    title: 'Hash table did not fit in memory',
    body:
        'Postgres split the hash into $batches batches because '
        '`work_mem` was too small. Raise `work_mem` if this query is '
        'on the hot path.',
  );
}

/// 4. Catch-all for temp-block spills from nodes that aren't Sort/Hash
/// (those have their own rules). Reports the combined read+written
/// block volume converted to kB (8 KB pages).
Advice? ruleTempSpill(PlanNode node, PlanNode? parent, bool analyzed) {
  if (node.kind == 'Sort' || node.kind == 'Hash') return null;
  final tempBlocks =
      ((node.raw['Temp Read Blocks'] as num?)?.toInt() ?? 0) +
      ((node.raw['Temp Written Blocks'] as num?)?.toInt() ?? 0);
  if (tempBlocks <= 0) return null;
  return Advice(
    severity: AdviceSeverity.warn,
    title: '${node.kind} spilled to temp files',
    body:
        'Used ${formatKb(tempBlocks * 8)} of temp files. Raise `work_mem` '
        'or break the query into smaller pieces.',
  );
}

/// 5. Index Only Scan that still touched the heap. Heap fetches happen
/// when the visibility map is stale; a `VACUUM` rebuilds it and
/// restores the "no table lookup" property of the scan.
Advice? ruleIndexOnlyHeapFetches(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
) {
  if (node.kind != 'Index Only Scan') return null;
  final heap = (node.raw['Heap Fetches'] as num?)?.toInt() ?? 0;
  final actualRows = node.actualRows;
  if (heap <= 0 || actualRows == null) return null;
  if (heap <= actualRows * 0.05) return null;
  final qualified = node.qualifiedRelation;
  final tail = qualified != null
      ? 'Run `VACUUM $qualified` to restore true index-only behavior.'
      : 'VACUUM the table to restore true index-only behavior.';
  return Advice(
    severity: AdviceSeverity.info,
    title: 'Index Only Scan still reads the table',
    body:
        'Postgres had to fetch from the heap ${formatInt(heap)} '
        'times because the visibility map is stale. $tail',
  );
}

/// 6. Estimate-mismatch detector. Lives outside [adviceRules] because
/// it needs to dedupe across the tree — see [runAdvice].
class MismatchCandidate {
  MismatchCandidate({
    required this.kind,
    required this.relation,
    required this.actual,
    required this.estimated,
    required this.fold,
  });

  final String kind;
  final String? relation;
  final int actual;
  final int estimated;
  final double fold;

  Advice toAdvice() {
    final fixHint = relation != null
        ? 'Run `ANALYZE $relation` to refresh statistics — the planner is '
            'choosing strategies blind right now.'
        : 'Refresh table stats with `ANALYZE` so the planner can pick a '
            'better strategy.';
    return Advice(
      severity: AdviceSeverity.warn,
      title: 'Planner estimate off by ${fold.round()}× on $kind',
      body:
          'Expected ${formatInt(estimated)} rows, got '
          '${formatInt(actual)}. $fixHint',
    );
  }
}

MismatchCandidate? mismatchCandidateOf(PlanNode node, bool analyzed) {
  if (!analyzed) return null;
  final actualRows = node.actualRows;
  final planRows = node.planRows;
  if (actualRows == null || planRows == null) return null;
  final a = actualRows == 0 ? 1 : actualRows;
  final e = planRows == 0 ? 1 : planRows;
  final fold = a > e ? a / e : e / a;
  if (fold < 10) return null;
  if (actualRows <= 100 && node.qualifiedRelation == null) return null;
  return MismatchCandidate(
    kind: node.kind,
    relation: node.qualifiedRelation,
    actual: actualRows,
    estimated: planRows,
    fold: fold.toDouble(),
  );
}

/// 7. Nested Loop with a big outer side feeding a non-indexed inner side
/// — each outer row triggers a full re-scan of the inner. Hash or Merge
/// join (or an index on the join key) scales better past ~1k outer rows.
Advice? ruleNestedLoopUnindexedInner(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
) {
  if (node.kind != 'Nested Loop') return null;
  if (node.children.length != 2) return null;
  final outer = node.children[0];
  final inner = node.children[1];
  final outerRows = outer.actualRows ?? 0;
  final outerLoops = outer.actualLoops ?? 1;
  final outerTotal = outerRows * outerLoops;
  final innerKind = inner.kind;
  final innerIndexed = innerKind.contains('Index');
  if (outerTotal < 1000 || innerIndexed) return null;
  return Advice(
    severity: AdviceSeverity.warn,
    title: 'Nested Loop without an index on the inner side',
    body:
        'Outer side feeds ${formatInt(outerTotal)} rows into a '
        '$innerKind inner side. A Hash/Merge join — or an index on '
        'the join key — would scale much better.',
  );
}

/// 8. Full Sort under a Limit. Postgres can do a Top-N heap sort when
/// it sees the Limit early, so the lack of `top-N heapsort` in the
/// Sort Method means an index matching the ORDER BY would let it stop
/// after producing the first N rows.
Advice? ruleFullSortUnderLimit(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
) {
  if (node.kind != 'Sort' || parent == null) return null;
  if (parent.kind != 'Limit') return null;
  final method = node.raw['Sort Method'] as String? ?? '';
  if (method.contains('top-N')) return null;
  return Advice(
    severity: AdviceSeverity.info,
    title: 'Full sort feeding a LIMIT',
    body:
        'Sort processed all input rows before LIMIT trimmed it. An '
        'index matching the ORDER BY would let Postgres stop early.',
  );
}

/// 9. LIKE/ILIKE filter evaluated row-by-row on a heap scan large
/// enough to matter. A `pg_trgm` GIN/GIST index supports pattern match.
Advice? ruleLikeFilterNoIndex(
  PlanNode node,
  PlanNode? parent,
  bool analyzed,
) {
  if (node.kind != 'Seq Scan' && node.kind != 'Bitmap Heap Scan') return null;
  final filter = node.raw['Filter'] as String?;
  if (filter == null) return null;
  final hasLike = filter.contains('~~') ||
      filter.toLowerCase().contains(' like ') ||
      filter.toLowerCase().contains(' ilike ');
  if (!hasLike) return null;
  final scanned = (node.actualRows ?? 0) +
      ((node.raw['Rows Removed by Filter'] as num?)?.toInt() ?? 0);
  if (scanned < 1000) return null;
  return Advice(
    severity: AdviceSeverity.info,
    title: 'Pattern match runs without an index',
    body:
        'A LIKE/ILIKE filter is being evaluated row-by-row. A '
        '`pg_trgm` GIN or GIST index on the column would let Postgres '
        'narrow the rows first.',
  );
}

/// 10. Postgres planned more parallel workers than it could start. The
/// shortfall almost always means `max_parallel_workers` or
/// `max_parallel_workers_per_gather` is capping concurrency.
Advice? ruleWorkersCapped(PlanNode node, PlanNode? parent, bool analyzed) {
  final planned = (node.raw['Workers Planned'] as num?)?.toInt();
  final launched = (node.raw['Workers Launched'] as num?)?.toInt();
  if (planned == null || launched == null) return null;
  if (launched >= planned) return null;
  return Advice(
    severity: AdviceSeverity.info,
    title: 'Parallel workers capped',
    body:
        'Postgres planned $planned workers but only launched '
        '$launched. `max_parallel_workers` (or '
        '`max_parallel_workers_per_gather`) is the ceiling.',
  );
}
