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

  /// Fetches the stored password for [connectionId] from the keychain.
  /// Triggers the Touch ID prompt — [reason] customizes the prompt text.
  /// Hydrated configs intentionally carry an empty password so the
  /// biometric sheet only appears when the user actually opens a
  /// connection.
  Future<String> readPassword(String connectionId, {String? reason}) =>
      _store.readPassword(connectionId, reason: reason);

  void add(ConnectionConfig config) {
    _connections.add(_strip(config));
    if (config.password.isNotEmpty) {
      unawaited(_store.writePassword(config.id, config.password));
    }
    _persist();
    notifyListeners();
  }

  /// Replace the config with id == [config.id]. Metadata only — the
  /// password in [config] is dropped on the floor. Callers that need to
  /// rotate the stored password must go through [setPassword] explicitly.
  ///
  /// This separation is load-bearing: every column-resize, favorite
  /// toggle, recent-tables update etc. flows through here, and the
  /// `session.activeConnection.copyWith(...)` shape those callers build
  /// carries the live password. Writing that password back to the vault
  /// on each metadata tick would silently re-issue the biometric
  /// `delete + add` dance and risk wiping the entry.
  ConnectionConfig? update(ConnectionConfig config) {
    final i = _connections.indexWhere((c) => c.id == config.id);
    if (i == -1) return null;
    final prev = _connections[i];
    _connections[i] = _strip(config);
    _persist();
    notifyListeners();
    return prev;
  }

  /// Rotate the keychain entry for [connectionId]. No-op on an empty
  /// password — clearing a stored credential goes through [remove] (full
  /// connection delete), there's no separate "forget password" gesture.
  Future<void> setPassword(String connectionId, String password) async {
    if (password.isEmpty) return;
    await _store.writePassword(connectionId, password);
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

  ConnectionConfig _strip(ConnectionConfig config) =>
      config.password.isEmpty ? config : config.copyWith(password: '');

  void _persist() => unawaited(_store.save(_connections));
}
