import 'package:flutter/foundation.dart';

import 'workspace_tab.dart';

/// One entry in the navigation history. A snapshot records either a plain
/// tab focus or, for [TableTab]s, the full triple (filter, selectList,
/// orderBy, page) so ⌘[ undoes filter / sort / pagination changes as
/// well as tab switches.
class NavSnapshot {
  const NavSnapshot.focus(this.tabId)
    : filter = null,
      selectList = null,
      orderBy = null,
      page = null;

  const NavSnapshot.table(
    this.tabId, {
    required this.filter,
    required this.selectList,
    required this.orderBy,
    required this.page,
  });

  final String tabId;
  final String? filter;
  final String? selectList;
  final String? orderBy;
  final int? page;

  bool get hasTableState =>
      filter != null && selectList != null && orderBy != null;

  @override
  bool operator ==(Object other) =>
      other is NavSnapshot &&
      other.tabId == tabId &&
      other.filter == filter &&
      other.selectList == selectList &&
      other.orderBy == orderBy &&
      other.page == page;

  @override
  int get hashCode => Object.hash(tabId, filter, selectList, orderBy, page);
}

/// Browser-style back/forward history over workspace tabs and per-table
/// filter / sort / pagination state.
///
/// Keeping this as its own notifier means the toolbar's back/forward
/// buttons can listen to history changes alone, without rebuilding on
/// every unrelated state mutation.
class NavigationHistory extends ChangeNotifier {
  NavigationHistory({this.maxEntries = 80});

  final int maxEntries;
  final List<NavSnapshot> _entries = [];
  int _index = -1;
  int _suppressDepth = 0;

  bool get canGoBack => _index > 0;

  bool get canGoForward => _index < _entries.length - 1;

  /// Suppresses snapshot pushes for the duration of [body]. Useful when an
  /// `apply()` triggers state changes that would otherwise push their own
  /// snapshots and corrupt the stack.
  T withSuppression<T>(T Function() body) {
    _suppressDepth++;
    try {
      return body();
    } finally {
      _suppressDepth--;
    }
  }

  void pushFocus(WorkspaceTab tab) {
    _push(NavSnapshot.focus(tab.id));
  }

  void pushTab(WorkspaceTab tab) {
    if (tab is TableTab) {
      _push(
        NavSnapshot.table(
          tab.id,
          filter: tab.filter,
          selectList: tab.selectList,
          orderBy: tab.orderBy,
          page: tab.page,
        ),
      );
    } else {
      _push(NavSnapshot.focus(tab.id));
    }
  }

  void _push(NavSnapshot snap) {
    if (_suppressDepth > 0) return;
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    if (_entries.isEmpty || _entries.last != snap) {
      _entries.add(snap);
      if (_entries.length > maxEntries) _entries.removeAt(0);
      _index = _entries.length - 1;
      notifyListeners();
    }
  }

  /// Walk backward through snapshots until [apply] accepts one (tab still
  /// exists). Snapshots that target a removed tab are skipped silently.
  void back(bool Function(NavSnapshot) apply) => _walk(apply, forward: false);

  void forward(bool Function(NavSnapshot) apply) => _walk(apply, forward: true);

  void _walk(bool Function(NavSnapshot) apply, {required bool forward}) {
    while ((forward && _index < _entries.length - 1) ||
        (!forward && _index > 0)) {
      _index += forward ? 1 : -1;
      final accepted = withSuppression(() => apply(_entries[_index]));
      if (accepted) {
        notifyListeners();
        return;
      }
    }
  }

  /// Drop every snapshot whose tab is no longer in [_tabs]. Called whenever
  /// a tab is closed so back/forward never lands on a dead id.
  void pruneTabs(Iterable<String> liveTabIds) {
    final live = liveTabIds.toSet();
    final filtered = [
      for (final e in _entries)
        if (live.contains(e.tabId)) e,
    ];
    if (filtered.length == _entries.length) return;
    _entries
      ..clear()
      ..addAll(filtered);
    if (_index >= _entries.length) _index = _entries.length - 1;
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty && _index == -1) return;
    _entries.clear();
    _index = -1;
    notifyListeners();
  }
}
