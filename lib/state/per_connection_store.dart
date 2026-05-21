import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_message.dart';
import '../models/saved_query.dart';
import 'catalog_controller.dart';
import 'connection_registry.dart';
import 'session_controller.dart';

/// Per-connection bags: favourite tables, recent tables, saved queries,
/// and per-table column widths.
///
/// Persistence lands through [ConnectionRegistry.update], so every mutation
/// here ends up in the same `connections.json` file. The active connection
/// is read from [SessionController]; materialised lookups (recents/
/// favourites as [DbTable]s rather than `schema.table` strings) come from
/// [CatalogController].
class PerConnectionStore extends ChangeNotifier {
  PerConnectionStore({
    required this.session,
    required this.registry,
    required this.catalog,
    this.columnWidthDebounce = const Duration(milliseconds: 500),
  }) {
    catalog.addListener(_onCatalogChanged);
    session.addListener(_onSessionChanged);
  }

  final SessionController session;
  final ConnectionRegistry registry;
  final CatalogController catalog;
  final Duration columnWidthDebounce;

  final List<DbTable> _recents = [];

  List<DbTable> get recents => List.unmodifiable(_recents);

  List<SavedQuery> get savedQueries =>
      session.activeConnection?.savedQueries ?? const [];

  /// Trim each per-query message list to this length on append. Keeps the
  /// connections.json file small while preserving enough history to be
  /// useful for debugging recent activity per tab.
  static const int maxMessagesPerQuery = 100;

  /// Return the persisted messages for a query tab id, or empty when no
  /// entry exists. Caller may not mutate the result.
  List<QueryMessage> messagesFor(String tabId) {
    return session.activeConnection?.queryMessages[tabId] ?? const [];
  }

  /// Append [message] to the tab's persisted log, trimming to
  /// [maxMessagesPerQuery]. No-op when no connection is active.
  void appendQueryMessage(String tabId, QueryMessage message) {
    _mutate((conn) {
      final next = Map<String, List<QueryMessage>>.of(conn.queryMessages);
      final list = List<QueryMessage>.of(next[tabId] ?? const []);
      list.add(message);
      if (list.length > maxMessagesPerQuery) {
        list.removeRange(0, list.length - maxMessagesPerQuery);
      }
      next[tabId] = list;
      return conn.copyWith(queryMessages: next);
    });
  }

  /// Drop the persisted message log for a tab — called from "Clear
  /// messages" in the message tab footer.
  void clearQueryMessages(String tabId) {
    _mutate((conn) {
      if (!conn.queryMessages.containsKey(tabId)) return conn;
      final next = Map<String, List<QueryMessage>>.of(conn.queryMessages)
        ..remove(tabId);
      return conn.copyWith(queryMessages: next);
    });
  }

  /// Materialise the active connection's favourite keys back into [DbTable]s
  /// that exist in the currently-loaded catalog.
  List<DbTable> get favoriteTables {
    final keys = session.activeConnection?.favoriteTables;
    if (keys == null || keys.isEmpty) return const [];
    final lookup = {
      for (final s in catalog.schemas)
        for (final t in s.tables) t.qualifiedKey: t,
    };
    return [
      for (final key in keys)
        if (lookup[key] != null) lookup[key]!,
    ];
  }

  bool isFavorite(DbTable table) {
    final keys = session.activeConnection?.favoriteTables ?? const <String>{};
    return keys.contains(table.qualifiedKey);
  }

  void toggleFavorite(DbTable table) {
    _mutate((conn) {
      final key = table.qualifiedKey;
      final next = Set<String>.of(conn.favoriteTables);
      if (!next.add(key)) next.remove(key);
      return conn.copyWith(favoriteTables: next);
    });
  }

  void trackRecent(DbTable table) {
    _recents.removeWhere((t) => t.qualifiedName == table.qualifiedName);
    _recents.insert(0, table);
    if (_recents.length > 12) _recents.removeRange(12, _recents.length);
    _persistRecents();
    _bumpUseCount(table);
    notifyListeners();
  }

  void _bumpUseCount(DbTable table) {
    _mutate((conn) {
      final next = Map<String, int>.of(conn.tableUseCounts);
      final key = table.qualifiedKey;
      next[key] = (next[key] ?? 0) + 1;
      return conn.copyWith(tableUseCounts: next);
    });
  }

  /// Top-N most-opened tables for the active connection, descending by
  /// total open count. Tables that no longer exist in the loaded catalog
  /// are silently dropped. Caller is expected to subtract favourites.
  List<DbTable> frequentTables({int limit = 5}) {
    final conn = session.activeConnection;
    if (conn == null || conn.tableUseCounts.isEmpty) return const [];
    final lookup = {
      for (final s in catalog.schemas)
        for (final t in s.tables) t.qualifiedKey: t,
    };
    final ranked = conn.tableUseCounts.entries
        .where((e) => lookup.containsKey(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ranked.take(limit)) lookup[e.key]!];
  }

  void persistQueryEdit(String id, String name, String sql) {
    _mutate((conn) {
      final entry = SavedQuery(
        id: id,
        name: name,
        sql: sql,
        updatedAt: DateTime.now(),
      );
      final next = List<SavedQuery>.of(conn.savedQueries);
      final i = next.indexWhere((q) => q.id == id);
      if (i == -1) {
        next.add(entry);
      } else {
        next[i] = entry;
      }
      return conn.copyWith(savedQueries: next);
    });
  }

  void renameQuery(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _mutate((conn) {
      final list = [
        for (final q in conn.savedQueries)
          if (q.id == id) q.copyWith(name: trimmed) else q,
      ];
      return conn.copyWith(savedQueries: list);
    });
  }

  void deleteSavedQuery(String id) {
    _mutate(
      (conn) => conn.copyWith(
        savedQueries: conn.savedQueries.where((q) => q.id != id).toList(),
      ),
    );
  }

  /// Duplicate the saved query and return the freshly-created copy so the
  /// caller can open it as a new tab. Returns null if the source no longer
  /// exists or there is no active connection.
  SavedQuery? duplicateSavedQuery(String id, String newId, String newName) {
    final conn = session.activeConnection;
    if (conn == null) return null;
    final src = conn.savedQueries.firstWhere(
      (q) => q.id == id,
      orElse: () => SavedQuery(id: '', name: '', sql: ''),
    );
    if (src.id.isEmpty) return null;
    final copy = SavedQuery(
      id: newId,
      name: newName,
      sql: src.sql,
      updatedAt: DateTime.now(),
    );
    _mutate((c) => c.copyWith(savedQueries: [...c.savedQueries, copy]));
    return copy;
  }

  /// Returns the persisted column widths for [table], if any.
  Map<String, double>? columnWidthsFor(DbTable table) {
    return session.activeConnection?.columnWidths[table.qualifiedKey];
  }

  // --- column widths persistence (debounced) ---------------------------

  Timer? _widthSaveTimer;
  Map<String, Map<String, double>>? _pendingWidths;
  String? _pendingConnectionId;

  /// Stores the user's resized [width] for [column] of [table], debounced so a
  /// continuous drag coalesces into one disk write.
  ///
  /// Captures the active connection id at the moment of the call so a
  /// connection switch during the debounce window doesn't write A's widths
  /// into B — the flush silently drops the pending batch on mismatch.
  void persistColumnWidth(DbTable table, String column, double width) {
    final conn = session.activeConnection;
    if (conn == null) return;
    if (_pendingConnectionId != null && _pendingConnectionId != conn.id) {
      _pendingWidths = null;
      _pendingConnectionId = null;
    }
    _pendingWidths ??= {
      for (final entry in conn.columnWidths.entries)
        entry.key: Map<String, double>.from(entry.value),
    };
    _pendingConnectionId = conn.id;
    _pendingWidths!.putIfAbsent(
      table.qualifiedKey,
      () => <String, double>{},
    )[column] = width;

    _widthSaveTimer?.cancel();
    _widthSaveTimer = Timer(columnWidthDebounce, _flushColumnWidths);
  }

  void _flushColumnWidths() {
    final pending = _pendingWidths;
    final pendingId = _pendingConnectionId;
    final conn = session.activeConnection;
    _pendingWidths = null;
    _pendingConnectionId = null;
    if (pending == null || pendingId == null) return;
    if (conn == null || conn.id != pendingId) return;
    final updated = conn.copyWith(columnWidths: pending);
    registry.update(updated);
    session.setActiveConnection(updated);
    notifyListeners();
  }

  // --- internal --------------------------------------------------------

  void _mutate(ConnectionConfig Function(ConnectionConfig) f) {
    final conn = session.activeConnection;
    if (conn == null) return;
    final updated = f(conn);
    registry.update(updated);
    session.setActiveConnection(updated);
    notifyListeners();
  }

  /// Rehydrate the materialised [_recents] list from the active connection's
  /// persisted qualifiedKey list, looking up each entry in the catalog.
  void _hydrateRecents() {
    _recents.clear();
    final conn = session.activeConnection;
    if (conn == null) {
      notifyListeners();
      return;
    }
    final lookup = {
      for (final s in catalog.schemas)
        for (final t in s.tables) t.qualifiedKey: t,
    };
    for (final key in conn.recentTables) {
      final t = lookup[key];
      if (t != null) _recents.add(t);
    }
    notifyListeners();
  }

  void _persistRecents() {
    final conn = session.activeConnection;
    if (conn == null) return;
    final keys = _recents.map((t) => t.qualifiedKey).toList();
    if (listEquals(keys, conn.recentTables)) return;
    final updated = conn.copyWith(recentTables: keys);
    registry.update(updated);
    session.setActiveConnection(updated);
  }

  void _onCatalogChanged() {
    // Phase 0 just landed → rehydrate the materialised lists.
    _hydrateRecents();
  }

  void _onSessionChanged() {
    // A different connection took over (or the existing config was
    // refreshed). Reset the materialised lists.
    _recents.clear();
    _pendingWidths = null;
    _pendingConnectionId = null;
    _widthSaveTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    catalog.removeListener(_onCatalogChanged);
    session.removeListener(_onSessionChanged);
    _widthSaveTimer?.cancel();
    super.dispose();
  }
}
