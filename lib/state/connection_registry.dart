import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../services/connection_store.dart';

/// Owns the persisted list of saved connections.
///
/// CRUD + persistence only — knowing which one is currently *active* lives
/// in [SessionController]. Per-connection bags (favorites, recents, saved
/// queries, column widths) are mutated through [PerConnectionStore], which
/// goes through `update()` here to land in the same JSON file.
class ConnectionRegistry extends ChangeNotifier {
  ConnectionRegistry({ConnectionStore? store})
      : _store = store ?? ConnectionStore();

  final ConnectionStore _store;
  final List<ConnectionConfig> _connections = [];

  List<ConnectionConfig> get all => List.unmodifiable(_connections);

  /// Top-3 most recently used, freshest first. Drives the welcome cards.
  List<ConnectionConfig> get recent {
    final stamped = _connections
        .where((c) => c.lastConnectedAt != null)
        .toList()
      ..sort((a, b) => b.lastConnectedAt!.compareTo(a.lastConnectedAt!));
    return stamped.take(3).toList();
  }

  ConnectionConfig? findById(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> hydrate() async {
    final saved = await _store.load();
    _connections
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  void add(ConnectionConfig config) {
    _connections.add(config);
    _persist();
    notifyListeners();
  }

  /// Replace the config with id == [config.id]. Returns the replaced entry
  /// so callers can pivot off it if needed (e.g. password rotation).
  ConnectionConfig? update(ConnectionConfig config) {
    final i = _connections.indexWhere((c) => c.id == config.id);
    if (i == -1) return null;
    final prev = _connections[i];
    _connections[i] = config;
    _persist();
    notifyListeners();
    return prev;
  }

  void remove(String id) {
    final removed = _connections.where((c) => c.id == id).toList();
    _connections.removeWhere((c) => c.id == id);
    for (final c in removed) {
      unawaited(_store.deletePassword(c.id));
    }
    _persist();
    notifyListeners();
  }

  void _persist() => unawaited(_store.save(_connections));
}
