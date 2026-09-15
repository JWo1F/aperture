import 'package:dbv/models/db_object.dart';
import 'package:dbv/models/query_result.dart';
import 'package:dbv/state/workspace_tab.dart';
import 'package:flutter_test/flutter_test.dart';

DbTable _table() => DbTable(
  oid: DbTable.unknownOid,
  schema: 'public',
  name: 't',
  kind: DbRelationKind.table,
);

QueryResult _page(List<String> rowIds) => QueryResult.rows(
  columns: const ['id'],
  rows: [for (var i = 0; i < rowIds.length; i++) <Object?>[i]],
  rowIds: rowIds,
  elapsed: Duration.zero,
);

void main() {
  group('TableTab pending state across a page load', () {
    test('a fresh page drops every row-indexed pending mutation', () {
      final tab = TableTab('t1', _table());
      tab.completePageLoad(
        tab.beginPageLoad(page: 0),
        result: _page(['(0,1)', '(0,2)', '(0,3)', '(0,4)']),
      );

      tab.setCellEdit(1, 0, const CellLiteral('9'));
      tab.deletePersistentRow(3);
      expect(tab.edits, hasLength(1));
      expect(tab.deletedRows, {3});

      // Paging, sorting, re-filtering and refresh all land here. Row indexes
      // address the *previous* result, so carrying them over would re-target
      // whatever row now sits at that index.
      tab.beginPageLoad(page: 1);

      expect(tab.edits, isEmpty);
      expect(
        tab.deletedRows,
        isEmpty,
        reason: 'a stale delete index would delete the wrong row on Apply',
      );
      expect(tab.hasEdits, isFalse);
    });

    test('a superseded load cannot resurrect its pending state', () {
      final tab = TableTab('t2', _table());
      tab.completePageLoad(
        tab.beginPageLoad(page: 0),
        result: _page(['(0,1)', '(0,2)']),
      );
      tab.deletePersistentRow(0);

      final stale = tab.beginPageLoad(page: 1);
      tab.beginPageLoad(page: 2);

      expect(
        tab.completePageLoad(stale, result: _page(['(0,9)'])),
        isFalse,
      );
      expect(tab.deletedRows, isEmpty);
    });
  });
}
