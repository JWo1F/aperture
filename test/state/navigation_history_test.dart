import 'package:aperture/models/db_object.dart';
import 'package:aperture/state/navigation_history.dart';
import 'package:aperture/state/workspace_tab.dart';
import 'package:flutter_test/flutter_test.dart';

QueryTab _tab(String id) => QueryTab(id, name: id, sql: '');

TableTab _tableTab(String id) => TableTab(
  id,
  DbTable(
    oid: DbTable.unknownOid,
    schema: 'public',
    name: id,
    kind: DbRelationKind.table,
  ),
);

void main() {
  group('NavigationHistory', () {
    test('pushFocus + back/forward walk', () {
      final h = NavigationHistory();
      h.pushFocus(_tab('a'));
      h.pushFocus(_tab('b'));
      h.pushFocus(_tab('c'));
      expect(h.canGoBack, isTrue);
      expect(h.canGoForward, isFalse);

      final seen = <String>[];
      h.back((snap) {
        seen.add(snap.tabId);
        return true;
      });
      expect(seen, ['b']);
      expect(h.canGoForward, isTrue);

      h.forward((snap) {
        seen.add('fwd:${snap.tabId}');
        return true;
      });
      expect(seen, ['b', 'fwd:c']);
    });

    test('back skips snapshots whose tab is gone', () {
      final h = NavigationHistory();
      h.pushFocus(_tab('a'));
      h.pushFocus(_tab('b'));
      h.pushFocus(_tab('c'));
      h.pruneTabs(['a', 'c']);
      // The 'b' snapshot is gone; back from c should land on a.
      String? landed;
      h.back((snap) {
        landed = snap.tabId;
        return true;
      });
      expect(landed, 'a');
    });

    test('pushFocus dedups an identical consecutive snapshot', () {
      final h = NavigationHistory();
      final tab = _tab('t');
      h.pushFocus(tab);
      h.pushFocus(tab);
      expect(h.canGoBack, isFalse);
    });

    test('pushTab captures filter/select/order/page for a TableTab', () {
      final h = NavigationHistory();
      final tab = _tableTab('t');
      tab.setFilter('id > 10');
      tab.setSelectList('id, name');
      tab.setOrderBy('name DESC');
      tab.beginPageLoad(page: 3);

      h.pushTab(tab);
      // Something to walk back FROM — `back` steps to the entry before
      // the current one.
      h.pushFocus(_tab('other'));

      NavSnapshot? seen;
      h.back((snap) {
        seen = snap;
        return true;
      });
      expect(seen, isNotNull);
      expect(seen!.tabId, 't');
      expect(seen!.filter, 'id > 10');
      expect(seen!.selectList, 'id, name');
      expect(seen!.orderBy, 'name DESC');
      expect(seen!.page, 3);
      expect(seen!.hasTableState, isTrue);
    });

    test('pushTab on a non-table tab records focus only', () {
      final h = NavigationHistory();
      h.pushTab(_tab('q'));
      h.pushFocus(_tab('other'));

      NavSnapshot? seen;
      h.back((snap) {
        seen = snap;
        return true;
      });
      expect(seen!.hasTableState, isFalse);
      expect(seen!.page, isNull);
    });

    test('a page change alone is still a distinct snapshot', () {
      final h = NavigationHistory();
      final tab = _tableTab('t');
      h.pushTab(tab);
      tab.beginPageLoad(page: 1);
      h.pushTab(tab);
      // Paging is navigation: ⌘[ has to be able to walk back through it.
      expect(h.canGoBack, isTrue);
    });

    test('withSuppression blocks push', () {
      final h = NavigationHistory();
      h.pushFocus(_tab('a'));
      h.withSuppression(() {
        h.pushFocus(_tab('b'));
      });
      expect(h.canGoBack, isFalse);
      expect(h.canGoForward, isFalse);
    });

    test('clear removes everything', () {
      final h = NavigationHistory();
      h.pushFocus(_tab('a'));
      h.pushFocus(_tab('b'));
      h.clear();
      expect(h.canGoBack, isFalse);
      expect(h.canGoForward, isFalse);
    });
  });
}
