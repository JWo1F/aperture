import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_message.dart';
import '../models/saved_query.dart';
import '../services/password_command.dart';
import '../services/store_database.dart';
import '../services/window_frame.dart';
import '../theme/app_theme.dart';

/// Outcome of resolving a connection's password.
sealed class CredentialResult {
  const CredentialResult();
}

class CredentialOk extends CredentialResult {
  const CredentialOk(this.password);
  final String password;
}

class CredentialError extends CredentialResult {
  const CredentialError(this.message);
  final String message;
}

/// Single source of truth for everything the app persists across launches.
///
/// One [ChangeNotifier] holding preferences and the saved-connection list
/// (with every per-connection bag nested inside it). Nothing is readable
/// until [open] hands it the unlocked [StoreDatabase]; from then on every
/// mutator updates the in-memory state, notifies listeners, and schedules a
/// single coalesced 500 ms snapshot write.
///
/// Widgets that care about a narrow slice should use `context.select` to
/// avoid rebuilding on unrelated changes — every mutation fires the same
/// notifier.
class AppStore extends ChangeNotifier {
  AppStore({
    PasswordCommand? passwordCommand,
    WindowFrame? window,
    this.onSaveFailed,
    this.saveDebounce = const Duration(milliseconds: 500),
  }) : _command = passwordCommand ?? PasswordCommand(),
       _window = window ?? WindowFrame();

  /// Called when a write to the store fails.
  ///
  /// Everything the app remembers between launches goes through this one
  /// file. A full disk or a read-only support directory makes every save
  /// and the quit-time flush fail, and without a sink the user adds
  /// connections and saved queries all evening, sees no complaint, and
  /// finds them gone on the next launch. `AppState` wires this to the
  /// event log and a toast.
  void Function(Object error)? onSaveFailed;

  StoreDatabase? _db;
  final PasswordCommand _command;
  final WindowFrame _window;
  final Duration saveDebounce;

  // ---- preferences ---------------------------------------------------

  static const double sidebarWidthMin = 180;
  static const double sidebarWidthMax = 520;
  static const double sidebarWidthDefault = 248;

  static const double logPanelWidthMin = 240;
  static const double logPanelWidthMax = 720;
  static const double logPanelWidthDefault = 380;

  static const double queryResultsFractionMin = 0.15;
  static const double queryResultsFractionMax = 0.85;
  static const double queryResultsFractionDefault = 0.6;

  AppThemeMode _themeMode = AppThemeMode.auto;

  /// The OS appearance, pushed in from the root widget. Only read when the
  /// mode is [AppThemeMode.auto], and never persisted — it belongs to
  /// macOS, not to us.
  AppBrightness _systemBrightness = AppBrightness.dark;
  bool _sidebarVisible = true;
  double _sidebarWidth = sidebarWidthDefault;
  double _logPanelWidth = logPanelWidthDefault;
  double _queryResultsFraction = queryResultsFractionDefault;
  /// The last frame the window had outside full screen, and whether it was
  /// in full screen. Kept apart so leaving full screen after a relaunch
  /// returns to the frame the user actually chose.
  Map<String, double>? _windowFramePersisted;
  bool _windowFullScreen = false;

  AppThemeMode get themeMode => _themeMode;

  /// The palette that is actually painted, with [AppThemeMode.auto]
  /// resolved. Everything downstream of the theme — `AppTheme.build`, the
  /// root shell's re-key — reads this, not the mode.
  AppBrightness get brightness => switch (_themeMode) {
    AppThemeMode.dark => AppBrightness.dark,
    AppThemeMode.light => AppBrightness.light,
    AppThemeMode.auto => _systemBrightness,
  };
  bool get sidebarVisible => _sidebarVisible;
  double get sidebarWidth => _sidebarWidth;
  double get logPanelWidth => _logPanelWidth;
  double get queryResultsFraction => _queryResultsFraction;

  // ---- connections ---------------------------------------------------

  final List<ConnectionConfig> _connections = [];

  List<ConnectionConfig> get connections => List.unmodifiable(_connections);

  ConnectionConfig? connectionById(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---- load / save lifecycle ----------------------------------------

  /// False until [open]: the settings are sealed in the store, so before
  /// unlock there is nothing to show but the defaults.
  bool get isOpen => _db != null;

  /// Hydrates from the unlocked [db], which the store keeps and writes to
  /// from then on.
  void open(StoreDatabase db) {
    final snapshot = db.load();
    _db = db;
    _readPreferences(snapshot.preferences);
    _connections
      ..clear()
      ..addAll(snapshot.connections);
    _applyPalette();
    unawaited(_restoreWindow());
    notifyListeners();
  }

  /// Re-encrypts the open store under [passphrase].
  void changePassphrase(String passphrase) => _db!.rekey(passphrase);

  /// Drains the pending debounced write so the app can quit without
  /// losing a mutation buffered in the last 500 ms.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) {
      _dirty = false;
      _writeNow();
    }
  }

  // ---- preference setters --------------------------------------------

  void setThemeMode(AppThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;
    _applyPalette();
    _changed();
  }

  void cycleThemeMode() => setThemeMode(_themeMode.next);

  /// The OS flipped appearance (sunset, or the user toggling it in System
  /// Settings). Nothing is persisted — the mode already says whether we
  /// care — but under [AppThemeMode.auto] the whole tree has to repaint.
  void setSystemBrightness(AppBrightness value) {
    if (_systemBrightness == value) return;
    _systemBrightness = value;
    if (_themeMode != AppThemeMode.auto) return;
    _applyPalette();
    notifyListeners();
  }

  void _applyPalette() {
    AppColors.setPalette(
      brightness == AppBrightness.dark ? darkPalette : lightPalette,
    );
  }

  void toggleSidebar() {
    _sidebarVisible = !_sidebarVisible;
    _changed();
  }

  void setSidebarVisible(bool value) {
    if (_sidebarVisible == value) return;
    _sidebarVisible = value;
    _changed();
  }

  void setSidebarWidth(double width) {
    final clamped = width.clamp(sidebarWidthMin, sidebarWidthMax);
    if (clamped == _sidebarWidth) return;
    _sidebarWidth = clamped;
    _changed();
  }

  void setLogPanelWidth(double width) {
    final clamped = width.clamp(logPanelWidthMin, logPanelWidthMax);
    if (clamped == _logPanelWidth) return;
    _logPanelWidth = clamped;
    _changed();
  }

  void setQueryResultsFraction(double fraction) {
    final clamped = fraction.clamp(
      queryResultsFractionMin,
      queryResultsFractionMax,
    );
    if (clamped == _queryResultsFraction) return;
    _queryResultsFraction = clamped;
    _changed();
  }

  /// Read the current native window frame and stash it for persistence on
  /// the next save tick. In full screen only the flag is recorded: the
  /// frame then is the screen's.
  Future<void> captureWindowFrame() async {
    final state = await _window.read();
    if (state == null) return;
    _windowFullScreen = state.fullScreen;
    if (!state.fullScreen) _windowFramePersisted = state.frame;
    _changed(notify: false);
  }

  /// Frame first, then full screen, so AppKit remembers the restored frame
  /// as the one to return to when full screen is left.
  Future<void> _restoreWindow() async {
    final frame = _windowFramePersisted;
    if (frame != null) await _window.write(frame);
    if (_windowFullScreen) await _window.setFullScreen(true);
  }

  // ---- connection CRUD ----------------------------------------------

  void addConnection(ConnectionConfig config) {
    _connections.add(_stripRuntimePassword(config));
    _changed();
  }

  /// Replace the config with id == [config.id]. Returns the previous
  /// snapshot or null when no such connection exists.
  ConnectionConfig? updateConnection(ConnectionConfig config) {
    final i = _connections.indexWhere((c) => c.id == config.id);
    if (i == -1) return null;
    final prev = _connections[i];
    _connections[i] = _stripRuntimePassword(config);
    _changed();
    return prev;
  }

  void removeConnection(String id) {
    final i = _connections.indexWhere((c) => c.id == id);
    if (i == -1) return;
    _connections.removeAt(i);
    _changed();
  }

  /// Stamp the `lastConnectedAt` field on a successful connect. Other
  /// connection-edit metadata stays untouched.
  void touchLastConnected(String id, DateTime when) {
    _mutateConnection(id, (c) => c.copyWith(lastConnectedAt: when));
  }

  // ---- per-connection bag mutators ----------------------------------

  void toggleFavorite(String connectionId, DbTable table) {
    _mutateConnection(connectionId, (c) {
      final key = table.qualifiedKey;
      final next = Set<String>.of(c.favoriteTables);
      if (!next.add(key)) next.remove(key);
      return c.copyWith(favoriteTables: next);
    });
  }

  /// Persisted recent-tables list for the connection, oldest entries
  /// dropped past [limit].
  void trackRecentTable(String connectionId, DbTable table, {int limit = 12}) {
    _mutateConnection(connectionId, (c) {
      final key = table.qualifiedKey;
      final keys = List<String>.of(c.recentTables)..remove(key);
      keys.insert(0, key);
      if (keys.length > limit) keys.removeRange(limit, keys.length);
      final counts = Map<String, int>.of(c.tableUseCounts);
      counts[key] = (counts[key] ?? 0) + 1;
      return c.copyWith(recentTables: keys, tableUseCounts: counts);
    });
  }

  void setColumnWidth(
    String connectionId,
    DbTable table,
    String column,
    double width,
  ) {
    _mutateConnection(connectionId, (c) {
      final next = <String, Map<String, double>>{
        for (final e in c.columnWidths.entries)
          e.key: Map<String, double>.of(e.value),
      };
      next.putIfAbsent(table.qualifiedKey, () => <String, double>{})[column] =
          width;
      return c.copyWith(columnWidths: next);
    });
  }

  void upsertSavedQuery(
    String connectionId,
    String id,
    String name,
    String sql,
  ) {
    _mutateConnection(connectionId, (c) {
      final entry = SavedQuery(
        id: id,
        name: name,
        sql: sql,
        updatedAt: DateTime.now(),
      );
      final next = List<SavedQuery>.of(c.savedQueries);
      final i = next.indexWhere((q) => q.id == id);
      if (i == -1) {
        next.add(entry);
      } else {
        next[i] = entry;
      }
      return c.copyWith(savedQueries: next);
    });
  }

  void renameSavedQuery(String connectionId, String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _mutateConnection(connectionId, (c) {
      final list = [
        for (final q in c.savedQueries)
          if (q.id == id) q.copyWith(name: trimmed) else q,
      ];
      return c.copyWith(savedQueries: list);
    });
  }

  void deleteSavedQuery(String connectionId, String id) {
    _mutateConnection(connectionId, (c) {
      return c.copyWith(
        savedQueries: c.savedQueries.where((q) => q.id != id).toList(),
      );
    });
  }

  /// Duplicates [id] under [newId]/[newName] and returns the copy so the
  /// caller can open it as a new tab. Null if the source no longer exists
  /// or no connection has that id.
  SavedQuery? duplicateSavedQuery(
    String connectionId,
    String id,
    String newId,
    String newName,
  ) {
    final c = connectionById(connectionId);
    if (c == null) return null;
    final src = c.savedQueries.firstWhere(
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
    _mutateConnection(
      connectionId,
      (c) => c.copyWith(savedQueries: [...c.savedQueries, copy]),
    );
    return copy;
  }

  /// Trim each per-query message list to this length on append.
  static const int maxMessagesPerQuery = 100;

  void appendQueryMessage(
    String connectionId,
    String tabId,
    QueryMessage message,
  ) {
    _mutateConnection(connectionId, (c) {
      final next = Map<String, List<QueryMessage>>.of(c.queryMessages);
      final list = List<QueryMessage>.of(next[tabId] ?? const []);
      list.add(message);
      if (list.length > maxMessagesPerQuery) {
        list.removeRange(0, list.length - maxMessagesPerQuery);
      }
      next[tabId] = list;
      return c.copyWith(queryMessages: next);
    });
  }

  void clearQueryMessages(String connectionId, String tabId) {
    _mutateConnection(connectionId, (c) {
      if (!c.queryMessages.containsKey(tabId)) return c;
      final next = Map<String, List<QueryMessage>>.of(c.queryMessages)
        ..remove(tabId);
      return c.copyWith(queryMessages: next);
    });
  }

  List<QueryMessage> queryMessagesFor(String connectionId, String tabId) {
    return connectionById(connectionId)?.queryMessages[tabId] ?? const [];
  }

  // ---- credential resolution ----------------------------------------

  /// Resolves the password for [config]: inline for a stored password,
  /// by running the command for a command credential.
  Future<CredentialResult> readCredential(ConnectionConfig config) async {
    final credential = config.credential;
    switch (credential) {
      case PasswordCredential():
        return CredentialOk(credential.password);
      case CommandCredential():
        if (credential.command.trim().isEmpty) {
          return const CredentialError(
            'No password command set for this connection — edit it to add '
            'one.',
          );
        }
        return switch (await _command.run(credential.command)) {
          CommandOk(password: final p) => CredentialOk(p),
          CommandFailure(message: final m) => CredentialError(
            'Password command failed: $m',
          ),
        };
    }
  }

  // ---- internals ----------------------------------------------------

  Timer? _saveTimer;
  bool _dirty = false;

  /// Wipe the transient [ConnectionConfig.runtimePassword] before the
  /// config lands in `_connections`. A stored password lives inside its
  /// [PasswordCredential] — that's the only password field that ever
  /// reaches disk.
  ConnectionConfig _stripRuntimePassword(ConnectionConfig config) {
    if (config.runtimePassword.isEmpty) return config;
    return config.copyWith(runtimePassword: '');
  }

  void _mutateConnection(
    String id,
    ConnectionConfig Function(ConnectionConfig) f,
  ) {
    final i = _connections.indexWhere((c) => c.id == id);
    if (i == -1) return;
    _connections[i] = _stripRuntimePassword(f(_connections[i]));
    _changed();
  }

  void _changed({bool notify = true}) {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDebounce, _flush);
    if (notify) notifyListeners();
  }

  void _flush() {
    _saveTimer = null;
    if (!_dirty) return;
    _dirty = false;
    _writeNow();
  }

  /// A no-op until [open]: a preference nudged before unlock (the window
  /// frame captured at launch) has nowhere to go, and [open] replaces it
  /// with the stored value anyway.
  void _writeNow() {
    final db = _db;
    if (db == null) return;
    try {
      db.save(_snapshot());
    } catch (e, st) {
      developer.log(
        'failed to save the store',
        name: 'aperture.store',
        error: e,
        stackTrace: st,
      );
      onSaveFailed?.call(e);
    }
  }

  static const _themeKey = 'themeMode';
  static const _sidebarVisibleKey = 'sidebarVisible';
  static const _sidebarWidthKey = 'sidebarWidth';
  static const _logPanelWidthKey = 'logPanelWidth';
  static const _queryResultsFractionKey = 'queryResultsFraction';
  static const _windowKeys = ['x', 'y', 'w', 'h'];
  static const _windowFullScreenKey = 'window.fullScreen';

  StoreSnapshot _snapshot() => StoreSnapshot(
    preferences: {
      _themeKey: _themeMode.name,
      _sidebarVisibleKey: _sidebarVisible ? 1 : 0,
      _sidebarWidthKey: _sidebarWidth,
      _logPanelWidthKey: _logPanelWidth,
      _queryResultsFractionKey: _queryResultsFraction,
      if (_windowFramePersisted case final frame?)
        for (final k in _windowKeys) 'window.$k': frame[k]!,
      _windowFullScreenKey: _windowFullScreen ? 1 : 0,
    },
    connections: List.of(_connections),
  );

  void _readPreferences(Map<String, Object> raw) {
    double? number(String key) => switch (raw[key]) {
      final num n => n.toDouble(),
      _ => null,
    };
    final modeName = raw[_themeKey];
    for (final m in AppThemeMode.values) {
      if (m.name == modeName) _themeMode = m;
    }
    final sidebar = raw[_sidebarVisibleKey];
    if (sidebar is int) _sidebarVisible = sidebar != 0;
    if (number(_sidebarWidthKey) case final w?) {
      _sidebarWidth = w.clamp(sidebarWidthMin, sidebarWidthMax);
    }
    if (number(_logPanelWidthKey) case final w?) {
      _logPanelWidth = w.clamp(logPanelWidthMin, logPanelWidthMax);
    }
    if (number(_queryResultsFractionKey) case final f?) {
      _queryResultsFraction = f.clamp(
        queryResultsFractionMin,
        queryResultsFractionMax,
      );
    }
    final frame = {for (final k in _windowKeys) k: ?number('window.$k')};
    if (frame.length == _windowKeys.length) _windowFramePersisted = frame;
    _windowFullScreen = raw[_windowFullScreenKey] == 1;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _db?.close();
    super.dispose();
  }
}
