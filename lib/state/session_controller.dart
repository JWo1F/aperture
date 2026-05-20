import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/log_event.dart';
import '../services/connect_errors.dart';
import '../services/postgres_service.dart';
import 'event_log.dart';

/// Lifecycle of the active connection from the UI's perspective.
///
/// `lost` is a non-terminal disconnect — the socket was killed (NAT/VPN
/// dropout, idle timeout, server-side reboot) but the active connection
/// config and the workspace are still in scope. The status bar surfaces
/// a reconnect affordance; tabs stay mounted so the user doesn't lose
/// their place.
enum ConnectionStatus { disconnected, connecting, connected, lost, error }

/// The currently-open Postgres connection. Owns the [PostgresService]
/// lifecycle and the user-facing status / error message.
class SessionController extends ChangeNotifier {
  SessionController({
    this.keepaliveInterval = const Duration(seconds: 30),
    this.log,
  });

  final Duration keepaliveInterval;
  final EventLog? log;

  PostgresService? _service;
  ConnectionConfig? _activeConnection;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _error;
  Timer? _keepaliveTimer;
  bool _keepalivePending = false;

  PostgresService? get service => _service;
  ConnectionConfig? get activeConnection => _activeConnection;
  ConnectionStatus get status => _status;
  String? get error => _error;

  bool get isConnected => _status == ConnectionStatus.connected;

  /// Opens [config] and transitions through connecting → connected | error.
  /// Returns true on success.
  Future<bool> connect(ConnectionConfig config) async {
    _cancelKeepalive();
    await _service?.close();
    _service = PostgresService(
      config,
      onQueryRun: ({
        required sql,
        required elapsed,
        required affectedRows,
        required error,
        required truncated,
      }) {
        log?.add(LogEvent(
          timestamp: DateTime.now(),
          kind: error == null ? LogEventKind.query : LogEventKind.error,
          connectionName: config.name,
          sql: sql,
          elapsed: elapsed,
          affectedRows: affectedRows,
          error: error,
        ));
      },
      onEditApplied: ({
        required statementCount,
        required elapsed,
        required error,
      }) {
        log?.add(LogEvent(
          timestamp: DateTime.now(),
          kind: error == null ? LogEventKind.edit : LogEventKind.error,
          connectionName: config.name,
          sql: '$statementCount UPDATE statement(s)',
          elapsed: elapsed,
          error: error,
        ));
      },
    );
    _activeConnection = config;
    _status = ConnectionStatus.connecting;
    _error = null;
    notifyListeners();

    try {
      await _service!.connect();
      _status = ConnectionStatus.connected;
      _startKeepalive();
      log?.add(LogEvent(
        timestamp: DateTime.now(),
        kind: LogEventKind.connect,
        connectionName: config.name,
      ));
      notifyListeners();
      return true;
    } catch (e) {
      final friendly = friendlyConnectError(e, config);
      _status = ConnectionStatus.error;
      _error = friendly.message;
      _service = null;
      log?.add(LogEvent(
        timestamp: DateTime.now(),
        kind: LogEventKind.error,
        connectionName: config.name,
        error: friendly.detail,
      ));
      notifyListeners();
      return false;
    }
  }

  /// Re-open the dropped connection without disturbing the workspace.
  ///
  /// Returns true on success. Differs from [connect] in that we don't
  /// re-emit a 'connecting' status until we're sure we still want to
  /// reach the old server — i.e. there's still an active connection
  /// config to reconnect to.
  Future<bool> reconnect() async {
    final conn = _activeConnection;
    if (conn == null) return false;
    return connect(conn);
  }

  /// Replace the active-connection snapshot in place (e.g. after a
  /// successful connect stamps lastConnectedAt). Does not change status.
  void setActiveConnection(ConnectionConfig updated) {
    if (_activeConnection?.id != updated.id) return;
    _activeConnection = updated;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _cancelKeepalive();
    await _service?.close();
    final name = _activeConnection?.name;
    _service = null;
    _activeConnection = null;
    _status = ConnectionStatus.disconnected;
    _error = null;
    log?.add(LogEvent(
      timestamp: DateTime.now(),
      kind: LogEventKind.disconnect,
      connectionName: name,
    ));
    notifyListeners();
  }

  /// Mark the session as having lost its socket. Closes the underlying
  /// service but preserves the active-connection config so the user can
  /// click "Reconnect" without losing their workspace.
  Future<void> markLost(Object cause) async {
    if (_status == ConnectionStatus.lost ||
        _status == ConnectionStatus.disconnected) {
      return;
    }
    _cancelKeepalive();
    await _service?.close();
    _service = null;
    _status = ConnectionStatus.lost;
    _error = cause.toString();
    log?.add(LogEvent(
      timestamp: DateTime.now(),
      kind: LogEventKind.lost,
      connectionName: _activeConnection?.name,
      error: cause.toString(),
    ));
    notifyListeners();
  }

  void _startKeepalive() {
    _cancelKeepalive();
    _keepaliveTimer = Timer.periodic(keepaliveInterval, (_) {
      unawaited(_runKeepalivePing());
    });
  }

  void _cancelKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _keepalivePending = false;
  }

  Future<void> _runKeepalivePing() async {
    if (_keepalivePending) return;
    final svc = _service;
    if (svc == null || _status != ConnectionStatus.connected) return;
    _keepalivePending = true;
    try {
      final result = await svc.runQuery('SELECT 1');
      if (result.isError) {
        await markLost(result.error ?? 'Connection lost');
      }
    } catch (e) {
      await markLost(e);
    } finally {
      _keepalivePending = false;
    }
  }

  @override
  void dispose() {
    _cancelKeepalive();
    _service?.close();
    super.dispose();
  }
}
