import 'package:aperture/ui/workspace/query_plan/analysis/advice_engine.dart';
import 'package:aperture/ui/workspace/query_plan/analysis/advice_rules.dart';
import 'package:aperture/ui/workspace/query_plan/model/advice.dart';
import 'package:aperture/ui/workspace/query_plan/model/plan_node.dart';
import 'package:aperture/ui/workspace/query_plan/parsing/plan_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiny builder for synthetic plan-node maps. Keeps tests focused on the
/// few EXPLAIN fields each rule actually reads.
Map<String, dynamic> plan({
  required String kind,
  Map<String, dynamic>? extra,
  List<Map<String, dynamic>>? children,
}) {
  return {
    'Node Type': kind,
    'Plans': ?children,
    ...?extra,
  };
}

/// Parses a single-node plan map to a PlanNode for rule unit tests.
PlanNode parseOne(Map<String, dynamic> root) {
  return parsePlan({'Plan': root})!;
}

void main() {
  group('seq scan with selective filter', () {
    test('fires when most rows are filtered on a large table', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Relation Name': 'orders',
          'Schema': 'public',
          'Actual Rows': 100,
          'Rows Removed by Filter': 9_900_000,
        },
      ));
      final advice = ruleSeqScanSelectiveFilter(node, null, true);
      expect(advice, isNotNull);
      expect(advice!.severity, AdviceSeverity.warn);
      expect(advice.title, contains('orders'));
    });

    test('stays silent on a tiny table', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Relation Name': 'tiny',
          'Actual Rows': 1,
          'Rows Removed by Filter': 99,
        },
      ));
      expect(ruleSeqScanSelectiveFilter(node, null, true), isNull);
    });
  });

  group('sort spilled to disk', () {
    test('fires when Sort Space Type is Disk', () {
      final node = parseOne(plan(
        kind: 'Sort',
        extra: {
          'Sort Space Type': 'Disk',
          'Sort Space Used': 2048,
        },
      ));
      final advice = ruleSortSpilledToDisk(node, null, true);
      expect(advice, isNotNull);
      expect(advice!.severity, AdviceSeverity.critical);
    });

    test('stays silent when sort fits in memory', () {
      final node = parseOne(plan(
        kind: 'Sort',
        extra: {'Sort Space Type': 'Memory', 'Sort Space Used': 32},
      ));
      expect(ruleSortSpilledToDisk(node, null, true), isNull);
    });
  });

  group('hash table batched', () {
    test('fires when Hash Batches > 1', () {
      final node = parseOne(plan(
        kind: 'Hash',
        extra: {'Hash Batches': 8},
      ));
      expect(ruleHashBatched(node, null, true), isNotNull);
    });

    test('stays silent at one batch', () {
      final node = parseOne(plan(kind: 'Hash', extra: {'Hash Batches': 1}));
      expect(ruleHashBatched(node, null, true), isNull);
    });
  });

  group('temp spill catch-all', () {
    test('fires on a non-Sort/Hash node with temp blocks', () {
      final node = parseOne(plan(
        kind: 'Aggregate',
        extra: {'Temp Read Blocks': 100, 'Temp Written Blocks': 100},
      ));
      final advice = ruleTempSpill(node, null, true);
      expect(advice, isNotNull);
    });

    test('skips Sort and Hash (they have their own rules)', () {
      final node = parseOne(plan(
        kind: 'Sort',
        extra: {'Temp Written Blocks': 100},
      ));
      expect(ruleTempSpill(node, null, true), isNull);
    });
  });

  group('index-only scan heap fetches', () {
    test('fires when heap fetches exceed 5% of actual rows', () {
      final node = parseOne(plan(
        kind: 'Index Only Scan',
        extra: {
          'Relation Name': 't',
          'Actual Rows': 1000,
          'Heap Fetches': 500,
        },
      ));
      expect(ruleIndexOnlyHeapFetches(node, null, true), isNotNull);
    });

    test('stays silent when the visibility map is fresh', () {
      final node = parseOne(plan(
        kind: 'Index Only Scan',
        extra: {'Actual Rows': 1000, 'Heap Fetches': 0},
      ));
      expect(ruleIndexOnlyHeapFetches(node, null, true), isNull);
    });
  });

  group('mismatch detector', () {
    test('fires when actual >> estimated by 10×', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Relation Name': 't',
          'Actual Rows': 100_000,
          'Plan Rows': 100,
        },
      ));
      final cand = mismatchCandidateOf(node, true);
      expect(cand, isNotNull);
      expect(cand!.fold, greaterThanOrEqualTo(10));
    });

    test('stays silent when ratio is within 10×', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Relation Name': 't',
          'Actual Rows': 500,
          'Plan Rows': 100,
        },
      ));
      expect(mismatchCandidateOf(node, true), isNull);
    });

    test('stays silent without ANALYZE', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Relation Name': 't',
          'Actual Rows': 100_000,
          'Plan Rows': 100,
        },
      ));
      expect(mismatchCandidateOf(node, false), isNull);
    });
  });

  group('nested loop unindexed inner', () {
    test('fires on big outer with non-indexed inner', () {
      final node = parseOne(plan(
        kind: 'Nested Loop',
        children: [
          plan(kind: 'Seq Scan', extra: {'Actual Rows': 5000, 'Actual Loops': 1}),
          plan(kind: 'Seq Scan', extra: {'Actual Rows': 1}),
        ],
      ));
      expect(ruleNestedLoopUnindexedInner(node, null, true), isNotNull);
    });

    test('stays silent when inner side uses an index', () {
      final node = parseOne(plan(
        kind: 'Nested Loop',
        children: [
          plan(kind: 'Seq Scan', extra: {'Actual Rows': 5000, 'Actual Loops': 1}),
          plan(kind: 'Index Scan', extra: {'Actual Rows': 1}),
        ],
      ));
      expect(ruleNestedLoopUnindexedInner(node, null, true), isNull);
    });
  });

  group('full sort under limit', () {
    test('fires when Sort under Limit is not Top-N', () {
      final root = parsePlan({
        'Plan': plan(
          kind: 'Limit',
          children: [
            plan(kind: 'Sort', extra: {'Sort Method': 'quicksort'}),
          ],
        ),
      })!;
      final sort = root.children.first;
      final advice = ruleFullSortUnderLimit(sort, root, true);
      expect(advice, isNotNull);
    });

    test('stays silent when Postgres already does Top-N', () {
      final root = parsePlan({
        'Plan': plan(
          kind: 'Limit',
          children: [
            plan(kind: 'Sort', extra: {'Sort Method': 'top-N heapsort'}),
          ],
        ),
      })!;
      final sort = root.children.first;
      expect(ruleFullSortUnderLimit(sort, root, true), isNull);
    });
  });

  group('LIKE/ILIKE without an index', () {
    test('fires on a Seq Scan with an ILIKE filter on enough rows', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Filter': "(name ~~* 'foo%'::text)",
          'Actual Rows': 100,
          'Rows Removed by Filter': 10_000,
        },
      ));
      expect(ruleLikeFilterNoIndex(node, null, true), isNotNull);
    });

    test('stays silent on equality filters', () {
      final node = parseOne(plan(
        kind: 'Seq Scan',
        extra: {
          'Filter': '(id = 42)',
          'Actual Rows': 100,
          'Rows Removed by Filter': 10_000,
        },
      ));
      expect(ruleLikeFilterNoIndex(node, null, true), isNull);
    });
  });

  group('workers capped', () {
    test('fires when launched < planned', () {
      final node = parseOne(plan(
        kind: 'Gather',
        extra: {'Workers Planned': 4, 'Workers Launched': 2},
      ));
      expect(ruleWorkersCapped(node, null, true), isNotNull);
    });

    test('stays silent when all planned workers launched', () {
      final node = parseOne(plan(
        kind: 'Gather',
        extra: {'Workers Planned': 4, 'Workers Launched': 4},
      ));
      expect(ruleWorkersCapped(node, null, true), isNull);
    });
  });

  group('runAdvice integration', () {
    test('healthy plan yields a single "looks healthy" advice', () {
      final root = parseOne(plan(
        kind: 'Index Scan',
        extra: {
          'Relation Name': 't',
          'Actual Rows': 5,
          'Plan Rows': 5,
          'Actual Total Time': 0.1,
          'Actual Loops': 1,
        },
      ));
      final out = runAdvice(
        root: root,
        analyzed: true,
        totalExecutionMs: 1.5,
      );
      expect(out, hasLength(1));
      expect(out.first.severity, AdviceSeverity.good);
    });

    test('non-analyzed plan returns empty list (caller renders banner)', () {
      final root = parseOne(plan(
        kind: 'Seq Scan',
        extra: {'Relation Name': 't', 'Plan Rows': 100},
      ));
      final out = runAdvice(
        root: root,
        analyzed: false,
        totalExecutionMs: null,
      );
      expect(out, isEmpty);
    });

    test('keeps only the worst mismatch across the tree', () {
      final root = parsePlan({
        'Plan': plan(
          kind: 'Nested Loop',
          extra: {
            'Actual Rows': 10_000,
            'Plan Rows': 1000,
            'Actual Loops': 1,
            'Actual Total Time': 5.0,
          },
          children: [
            plan(kind: 'Seq Scan', extra: {
              'Relation Name': 'left',
              'Actual Rows': 100_000,
              'Plan Rows': 10,
              'Actual Loops': 1,
              'Actual Total Time': 4.0,
            }),
            plan(kind: 'Index Scan', extra: {
              'Relation Name': 'right',
              'Actual Rows': 500,
              'Plan Rows': 100,
              'Actual Loops': 1,
              'Actual Total Time': 1.0,
            }),
          ],
        ),
      })!;
      final out = runAdvice(
        root: root,
        analyzed: true,
        totalExecutionMs: 10.0,
      );
      final mismatches =
          out.where((a) => a.title.contains('estimate off')).toList();
      expect(mismatches, hasLength(1));
      expect(mismatches.first.title, contains('Seq Scan'));
    });
  });
}
