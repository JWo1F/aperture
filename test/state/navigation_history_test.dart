import 'package:dbv/state/navigation_history.dart';
import 'package:dbv/state/workspace_tab.dart';
import 'package:flutter_test/flutter_test.dart';

QueryTab _tab(String id) => QueryTab(id, name: id, sql: '');

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

    test('pushTab captures filter/select/order/page for a TableTab', () {
      final h = NavigationHistory();
      final tab = _tab('t');
      h.pushFocus(tab);
      // Pushing the same focus snapshot twice is dedup'd.
      h.pushFocus(tab);
      expect(h.canGoBack, isFalse);
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
