import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../services/postgres_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// The currently-open Postgres connection. Owns the [PostgresService]
/// lifecycle and the user-facing status / error message.
///
/// Cross-controller flows (clear tabs on connect, bump catalog generation
/// on disconnect, …) are coordinated by [AppState] which listens to this
/// controller's status transitions.
class SessionController extends ChangeNotifier {
  PostgresService? _service;
  ConnectionConfig? _activeConnection;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _error;

  PostgresService? get service => _service;
  ConnectionConfig? get activeConnection => _activeConnection;
  ConnectionStatus get status => _status;
  String? get error => _error;

  bool get isConnected => _status == ConnectionStatus.connected;

  /// Opens [config] and transitions through connecting → connected | error.
  /// Returns true on success.
  Future<bool> connect(ConnectionConfig config) async {
    await _service?.close();
    _service = PostgresService(config);
    _activeConnection = config;
    _status = ConnectionStatus.connecting;
    _error = null;
    notifyListeners();

    try {
      await _service!.connect();
      _status = ConnectionStatus.connected;
      notifyListeners();
      return true;
    } catch (e) {
      _status = ConnectionStatus.error;
      _error = e.toString();
      _service = null;
      notifyListeners();
      return false;
    }
  }

  /// Replace the active-connection snapshot in place (e.g. after a
  /// successful connect stamps lastConnectedAt). Does not change status.
  void setActiveConnection(ConnectionConfig updated) {
    if (_activeConnection?.id != updated.id) return;
    _activeConnection = updated;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _service?.close();
    _service = null;
    _activeConnection = null;
    _status = ConnectionStatus.disconnected;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }
}
