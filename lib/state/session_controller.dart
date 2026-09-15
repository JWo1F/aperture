import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/log_event.dart';
import '../services/connect_errors.dart';
import '../services/db_service.dart';
import 'event_log.dart';

/// Lifecycle of the active connection from the UI's perspective.
///
/// `lost` is a non-terminal disconnect — the socket was killed (NAT/VPN
/// dropout, idle timeout, server-side reboot) but the active connection
/// config and the workspace are still in scope. The status bar surfaces
/// a reconnect affordance; tabs stay mounted so the user doesn't lose
/// their place.
enum ConnectionStatus { disconnected, connecting, connected, lost, error }

/// The currently-open database connection. Owns the [DbService]
/// lifecycle and the user-facing status / error message.
class SessionController extends ChangeNotifier {
  SessionController({
    this.keepaliveInterval = const Duration(seconds: 30),
    this.log,
  });

  final Duration keepaliveInterval;
  final EventLog? log;

  DbService? _service;
  ConnectionConfig? _activeConnection;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _error;
  String? _serverVersion;
  Timer? _keepaliveTimer;
  bool _keepalivePending = false;

  /// A keepalive ping or a version probe can resolve after the app has torn
  /// the controller down, and `notifyListeners()` on a disposed
  /// `ChangeNotifier` throws.
  bool _disposed = false;

  /// Bumped by every [connect] / [reconnect]. An attempt whose token is
  /// stale has been superseded and must not touch the session.
  int _attempt = 0;

  DbService? get service => _service;

  ConnectionConfig? get activeConnection => _activeConnection;

  ConnectionStatus get status => _status;

  String? get error => _error;

  /// Server version short-tag — e.g. `v16.4`. Populated right after a
  /// successful connect via `SHOW server_version`. Null until the version
  /// query lands or if it failed silently.
  String? get serverVersion => _serverVersion;

  bool get isConnected => _status == ConnectionStatus.connected;

  /// Surface a pre-connect failure (e.g. credential resolution) without
  /// going through the postgres driver. Leaves the session disconnected
  /// with the error message visible in the status bar.
  void setError(String message) {
    _status = ConnectionStatus.error;
    _error = message;
    _service = null;
    notifyListeners();
  }

  /// Refresh the lost-state error message in place. Used by the reconnect
  /// orchestrator when a pre-flight step (credential resolution, master
  /// passphrase unlock) fails: the banner re-renders with the new reason
  /// and the workspace stays mounted, instead of flipping to `error` and
  /// dumping the user on the welcome panel.
  void updateLostError(String message) {
    if (_status != ConnectionStatus.lost) return;
    _error = message;
    notifyListeners();
  }

  /// Opens [config] and transitions through connecting → connected | error.
  /// Returns true on success.
  ///
  /// Guarded by an attempt token. Resolving a credential can take seconds
  /// — a 1Password lookup spawns `op` and may wait on Touch ID — and
  /// nothing stops the user clicking a second connection meanwhile. Two
  /// overlapping attempts used to interleave: the slower one's failure
  /// overwrote the faster one's success, nulling `_service` while its
  /// socket stayed open and unreachable, and the catalog load for the
  /// winner then found no service and dumped the user on the welcome
  /// panel with the loser's error. A superseded attempt now closes
  /// whatever it opened and reports nothing.
  Future<bool> connect(ConnectionConfig config) async {
    final attempt = ++_attempt;
    _cancelKeepalive();
    await _service?.close();
    if (attempt != _attempt) return false;
    final service = _buildService(config);
    _service = service;
    _activeConnection = config;
    _status = ConnectionStatus.connecting;
    _error = null;
    notifyListeners();

    try {
      await service.connect();
      if (attempt != _attempt) {
        // A later attempt owns the session now; don't strand this socket.
        await service.close();
        return false;
      }
      _status = ConnectionStatus.connected;
      _serverVersion = null;
      _startKeepalive();
      log?.add(
        LogEvent(
          timestamp: DateTime.now(),
          kind: LogEventKind.connect,
          connectionName: config.name,
        ),
      );
      notifyListeners();
      // Fetch the server version out of band — failures are non-fatal,
      // they just leave the header without a "v…" tag.
      unawaited(_fetchServerVersion());
      return true;
    } catch (e) {
      if (attempt != _attempt) return false;
      final friendly = friendlyConnectError(e, config);
      _status = ConnectionStatus.error;
      _error = friendly.message;
      _service = null;
      log?.add(
        LogEvent(
          timestamp: DateTime.now(),
          kind: LogEventKind.error,
          connectionName: config.name,
          error: friendly.detail,
        ),
      );
      notifyListeners();
      return false;
    }
  }

  /// Re-open the dropped connection without disturbing the workspace.
  ///
  /// Returns true on success. From a `lost` state we deliberately hold
  /// status at `lost` for the entire attempt — transitioning through
  /// `connecting` would tear down the workspace (the shell only mounts
  /// it for `connected || lost`) and a failure transition to `error`
  /// would dump the user on the welcome panel. Keeping `lost` mounted
  /// means the banner stays, the workspace stays, and a failure just
  /// refreshes the banner's error text so the user can retry in place.
  Future<bool> reconnect() async {
    final conn = _activeConnection;
    if (conn == null) return false;
    if (_status != ConnectionStatus.lost) return connect(conn);

    final attempt = ++_attempt;
    _cancelKeepalive();
    await _service?.close();
    if (attempt != _attempt) return false;
    final service = _buildService(conn);
    _service = service;

    try {
      await service.connect();
      if (attempt != _attempt) {
        await service.close();
        return false;
      }
      _status = ConnectionStatus.connected;
      _error = null;
      _serverVersion = null;
      _startKeepalive();
      log?.add(
        LogEvent(
          timestamp: DateTime.now(),
          kind: LogEventKind.connect,
          connectionName: conn.name,
        ),
      );
      notifyListeners();
      unawaited(_fetchServerVersion());
      return true;
    } catch (e) {
      if (attempt != _attempt) return false;
      final friendly = friendlyConnectError(e, conn);
      _service = null;
      _error = friendly.message;
      log?.add(
        LogEvent(
          timestamp: DateTime.now(),
          kind: LogEventKind.error,
          connectionName: conn.name,
          error: friendly.detail,
        ),
      );
      notifyListeners();
      return false;
    }
  }

  DbService _buildService(ConnectionConfig config) {
    return createDbService(
      config,
      onQueryRun:
          ({
            required sql,
            required elapsed,
            required affectedRows,
            required error,
          }) {
            log?.add(
              LogEvent(
                timestamp: DateTime.now(),
                kind: error == null ? LogEventKind.query : LogEventKind.error,
                connectionName: config.name,
                sql: sql,
                elapsed: elapsed,
                affectedRows: affectedRows,
                error: error,
              ),
            );
          },
      onEditApplied:
          ({required statementCount, required elapsed, required error}) {
            log?.add(
              LogEvent(
                timestamp: DateTime.now(),
                kind: error == null ? LogEventKind.edit : LogEventKind.error,
                connectionName: config.name,
                sql: '$statementCount UPDATE statement(s)',
                elapsed: elapsed,
                error: error,
              ),
            );
          },
    );
  }

  /// Replace the active-connection snapshot in place (e.g. after a
  /// successful connect stamps lastConnectedAt). Does not change status.
  void setActiveConnection(ConnectionConfig updated) {
    if (_activeConnection?.id != updated.id) return;
    _activeConnection = updated;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _attempt++;
    _cancelKeepalive();
    final name = _activeConnection?.name;
    // Flip the status BEFORE closing the socket. Any request still in
    // flight fails the moment the socket goes, and `markLost` gates on the
    // status — closing first left a window where a deliberate disconnect
    // reported itself as a lost connection, complete with a "Failed to
    // load page" toast and a `lost` entry in the activity log.
    final closing = _service;
    _service = null;
    _activeConnection = null;
    _status = ConnectionStatus.disconnected;
    _error = null;
    _serverVersion = null;
    await closing?.close();
    log?.add(
      LogEvent(
        timestamp: DateTime.now(),
        kind: LogEventKind.disconnect,
        connectionName: name,
      ),
    );
    notifyListeners();
  }

  /// Mark the session as having lost its socket. Closes the underlying
  /// service but preserves the active-connection config so the user can
  /// click "Reconnect" without losing their workspace.
  Future<void> markLost(Object cause) async {
    if (_disposed) return;
    if (_status == ConnectionStatus.lost ||
        _status == ConnectionStatus.disconnected) {
      return;
    }
    _cancelKeepalive();
    await _service?.close();
    _service = null;
    _status = ConnectionStatus.lost;
    _error = cause.toString();
    log?.add(
      LogEvent(
        timestamp: DateTime.now(),
        kind: LogEventKind.lost,
        connectionName: _activeConnection?.name,
        error: cause.toString(),
      ),
    );
    notifyListeners();
  }

  /// Asks the service for its short version tag (the sidebar header's
  /// `v16.4` / `v3.45`) out of band. Failures are non-fatal — they just
  /// leave the header without a tag.
  Future<void> _fetchServerVersion() async {
    final svc = _service;
    if (svc == null || !svc.isConnected) return;
    final tag = await svc.fetchVersionTag();
    // The probe outlives the connection that asked for it: a disconnect or
    // a switch to another database mid-flight would otherwise stamp the old
    // server's version on the new session's header.
    if (_disposed || !identical(_service, svc)) return;
    if (tag == null || tag.isEmpty) return;
    _serverVersion = tag;
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
      await svc.ping();
    } catch (e) {
      await markLost(e);
    } finally {
      _keepalivePending = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelKeepalive();
    _service?.close();
    super.dispose();
  }
}
