import 'package:aperture/models/db_object.dart';
import 'package:aperture/models/query_result.dart';
import 'package:aperture/state/workspace_tab.dart';
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
  group('a closed tab absorbs its in-flight results', () {
    test('a page load landing after close does not throw', () {
      final tab = TableTab('d1', _table());
      final token = tab.beginPageLoad(page: 0);
      tab.dispose();

      // ⌘W on a tab whose 20-second query is still running. Notifying a
      // disposed ChangeNotifier asserts, which used to surface as a
      // sticky "Unexpected error" toast.
      expect(tab.disposed, isTrue);
      expect(
        () => tab.completePageLoad(token, result: _page(['(0,1)'])),
        returnsNormally,
      );
      expect(() => tab.failPageLoad(token, 'boom'), returnsNormally);
    });

    test('a query run landing after close does not throw', () {
      final tab = QueryTab('d2', sql: 'SELECT 1');
      tab.beginRun(sql: 'SELECT 1');
      tab.dispose();

      expect(
        () => tab.completeRun(
          result: QueryResult.command(affectedRows: 0, elapsed: Duration.zero),
          sql: 'SELECT 1',
          message: QueryMessage(
            timestamp: DateTime.now(),
            sql: 'SELECT 1',
            elapsedMs: 1,
          ),
          maxMessages: 10,
        ),
        returnsNormally,
      );
    });

    test('a DDL fetch landing after close does not throw', () {
      final tab = SchemaTab('d3', _table());
      tab.beginDdlLoad();
      tab.dispose();

      expect(() => tab.completeDdlLoad('CREATE TABLE t ()'), returnsNormally);
      expect(() => tab.failDdlLoad('boom'), returnsNormally);
    });
  });

  group('TableTab column widths', () {
    test('the public view refuses writes, so callers must use the mutator', () {
      final tab = TableTab('w1', _table());
      // The grid header once assigned straight into this view on every
      // resize tick; it threw, and the persist callback on the next line
      // never ran, so no width ever reached the store.
      expect(
        () => tab.columnWidths['id'] = 120,
        throwsUnsupportedError,
      );
    });

    test('setColumnWidth records and survives a page load', () {
      final tab = TableTab('w2', _table());
      tab.setColumnWidth('id', 120);
      tab.setColumnWidth('name', 240);
      expect(tab.columnWidths, {'id': 120.0, 'name': 240.0});

      // A new page must not lose the widths — they are keyed by column
      // name, not row position.
      tab.beginPageLoad(page: 1);
      expect(tab.columnWidths, {'id': 120.0, 'name': 240.0});
    });

    test('mergeSavedWidths seeds without clobbering a live resize', () {
      final tab = TableTab('w3', _table());
      tab.setColumnWidth('id', 120);
      tab.mergeSavedWidths({'name': 200});
      expect(tab.columnWidths, {'id': 120.0, 'name': 200.0});
    });
  });

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
