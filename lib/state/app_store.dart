import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../models/db_object.dart';
import '../models/query_message.dart';
import '../models/saved_query.dart';
import '../services/atomic_json.dart';
import '../services/crypto.dart';
import '../services/one_password_client.dart';
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

class CredentialNeedsPassphrase extends CredentialResult {
  const CredentialNeedsPassphrase();
}

class CredentialError extends CredentialResult {
  const CredentialError(this.message);
  final String message;
}

/// Single source of truth for everything the app persists across launches.
///
/// One [ChangeNotifier] holding preferences, the saved-connection list (with
/// every per-connection bag nested inside it), and the master-passphrase
/// metadata. Every mutator updates the in-memory state, notifies listeners,
/// and schedules a single coalesced 500 ms write to `store.json`.
///
/// Widgets that care about a narrow slice should use `context.select` to
/// avoid rebuilding on unrelated changes — every mutation fires the same
/// notifier.
class AppStore extends ChangeNotifier {
  AppStore({
    AtomicJsonFile? file,
    OnePasswordClient? onePassword,
    WindowFrame? window,
    this.onSaveFailed,
    this.saveDebounce = const Duration(milliseconds: 500),
  }) : _file = file ?? AtomicJsonFile('store.json'),
       _op = onePassword ?? OnePasswordClient(),
       _window = window ?? WindowFrame();

  /// Called when a write to `store.json` fails.
  ///
  /// Everything the app remembers between launches goes through this one
  /// file. A full disk or a read-only support directory makes every save
  /// and the quit-time flush fail, and without a sink the user adds
  /// connections and saved queries all evening, sees no complaint, and
  /// finds them gone on the next launch. `AppState` wires this to the
  /// event log and a toast.
  void Function(Object error)? onSaveFailed;

  final AtomicJsonFile _file;
  final OnePasswordClient _op;
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
  Map<String, double>? _windowFramePersisted;

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

  /// Top-3 most recently used, freshest first. Drives the welcome cards.
  List<ConnectionConfig> get recentConnections {
    final stamped =
        _connections.where((c) => c.lastConnectedAt != null).toList()
          ..sort((a, b) => b.lastConnectedAt!.compareTo(a.lastConnectedAt!));
    return stamped.take(3).toList();
  }

  ConnectionConfig? connectionById(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---- master passphrase --------------------------------------------

  /// The plaintext [setupPassphrase] seals into the stored `verifier` and
  /// [unlockPassphrase] compares the decrypted bytes against. Changing it
  /// invalidates every vault sealed under the old value — they fail with
  /// the wrong-passphrase message and cannot be recovered.
  static const String _passphraseSentinel = 'aperture-vault-ok';

  Map<String, dynamic>? _security;
  Uint8List? _passphraseKey;

  /// True once [load] has finished — the security file may or may not
  /// have contained a passphrase setup.
  bool get isPassphraseLoaded => _loaded;

  /// True if the user has already set up a master passphrase.
  bool get isPassphraseConfigured => _security != null;

  /// True if the derived key is in memory and ready to encrypt/decrypt.
  bool get isPassphraseUnlocked => _passphraseKey != null;

  bool _loaded = false;

  // ---- load / save lifecycle ----------------------------------------

  /// One-time hydration from `store.json`. Failures fall back to defaults
  /// so a corrupt file never blocks launch.
  ///
  /// `main()` awaits this before `runApp`, so a throw here is not a degraded
  /// session — it is a window that never opens, with no UI to explain why.
  /// A section that won't parse is dropped and the rest still loads.
  Future<void> load() async {
    final decoded = await _file.load();
    if (decoded is Map<String, dynamic>) {
      _readSection(
        'preferences',
        () => _readPreferences(decoded['preferences']),
      );
      _readSection(
        'connections',
        () => _readConnections(decoded['connections']),
      );
      _readSection('security', () => _readSecurity(decoded['security']));
    }
    _applyPalette();
    if (_windowFramePersisted != null) {
      // Restoring the native window frame is async but doesn't gate UI
      // hydration — kick it off after the listeners run.
      unawaited(_window.write(_windowFramePersisted!));
    }
    _loaded = true;
    notifyListeners();
  }

  /// Drains the pending debounced write so the app can quit without
  /// losing a mutation buffered in the last 500 ms.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) {
      _dirty = false;
      await _writeNow();
    }
    await _file.drain();
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
  /// the next save tick.
  Future<void> captureWindowFrame() async {
    final frame = await _window.read();
    if (frame == null) return;
    _windowFramePersisted = frame;
    _changed(notify: false);
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

  // ---- master passphrase --------------------------------------------

  /// First-time setup. Generates a salt, derives the key, encrypts the
  /// sentinel, persists the verifier, and leaves the session unlocked.
  /// Returns false if a passphrase is already configured.
  Future<bool> setupPassphrase(String passphrase) async {
    if (passphrase.isEmpty) return false;
    if (_security != null) return false;
    final salt = randomBytes(passphraseSaltBytes);
    final key = derivePassphraseKey(passphrase, salt);
    final verifier = aesGcmEncrypt(key, utf8.encode(_passphraseSentinel));
    _security = <String, dynamic>{
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': passphraseIterations,
      'salt': base64Encode(salt),
      'verifier': base64Encode(verifier),
    };
    _passphraseKey = key;
    _changed();
    return true;
  }

  /// Tries to unlock the session with [passphrase]. Returns true on
  /// success and leaves the key in memory.
  Future<bool> unlockPassphrase(String passphrase) async {
    final meta = _security;
    if (meta == null) return false;
    final Uint8List salt;
    final Uint8List verifier;
    final int iterations;
    try {
      salt = base64Decode(meta['salt'] as String);
      verifier = base64Decode(meta['verifier'] as String);
      // Derive with the cost this vault was WRITTEN at, not the current
      // constant. The value has always been persisted; reading it back is
      // what makes raising `passphraseIterations` a safe change instead of
      // one that silently locks the user out of their own passwords.
      iterations = switch (meta['iterations']) {
        final int n when n > 0 => n,
        _ => passphraseIterations,
      };
    } catch (_) {
      // A security block that won't parse can't be unlocked; saying so is
      // better than throwing out of the unlock modal.
      return false;
    }
    final key = derivePassphraseKey(passphrase, salt, iterations: iterations);
    try {
      final plain = aesGcmDecrypt(key, verifier);
      if (utf8.decode(plain) != _passphraseSentinel) return false;
    } catch (_) {
      return false;
    }
    _passphraseKey = key;
    notifyListeners();
    return true;
  }

  void lockPassphrase() {
    if (_passphraseKey == null) return;
    _passphraseKey = null;
    notifyListeners();
  }

  /// Returns base64-encoded `nonce || ciphertext || tag`. Throws
  /// [StateError] if the session is locked.
  String encryptWithPassphrase(String plaintext) {
    final key = _passphraseKey;
    if (key == null) throw StateError('master passphrase is locked');
    return base64Encode(aesGcmEncrypt(key, utf8.encode(plaintext)));
  }

  /// Decrypts a base64 blob produced by [encryptWithPassphrase]. Returns
  /// null on any decryption failure (wrong key, tampered ciphertext).
  String? decryptWithPassphrase(String cipher) {
    final key = _passphraseKey;
    if (key == null) throw StateError('master passphrase is locked');
    try {
      return utf8.decode(aesGcmDecrypt(key, base64Decode(cipher)));
    } catch (_) {
      return null;
    }
  }

  // ---- credential resolution ----------------------------------------

  /// Resolves the password for [config] by dispatching on its
  /// [Credential] variant: inline for plain, AES-GCM decrypt for
  /// encrypted, `op read` for 1Password.
  Future<CredentialResult> readCredential(ConnectionConfig config) async {
    final credential = config.credential;
    switch (credential) {
      case PlainCredential():
        return CredentialOk(credential.password);
      case EncryptedCredential():
        if (credential.cipher.isEmpty) {
          return const CredentialError(
            'No stored password for this connection — edit it to set one.',
          );
        }
        if (!isPassphraseUnlocked) return const CredentialNeedsPassphrase();
        final plain = decryptWithPassphrase(credential.cipher);
        if (plain == null) {
          return const CredentialError(
            'Could not decrypt the saved password. The master passphrase '
            'may be wrong, or the stored ciphertext was tampered with.',
          );
        }
        return CredentialOk(plain);
      case OnePasswordCredential():
        if (credential.secretRef.isEmpty) {
          return const CredentialError(
            'No 1Password secret reference set for this connection.',
          );
        }
        final r = await _op.read(credential.secretRef);
        return switch (r) {
          OpSuccess(value: final v) => CredentialOk(v),
          OpMissing() => const CredentialError(
            'The 1Password CLI (`op`) is not installed. '
            'Install it with `brew install 1password-cli` and enable '
            'the desktop app integration.',
          ),
          OpFailure(message: final m) => CredentialError(
            '1Password lookup failed: $m',
          ),
        };
    }
  }

  // ---- internals ----------------------------------------------------

  Timer? _saveTimer;
  bool _dirty = false;

  /// Wipe the transient [ConnectionConfig.runtimePassword] before the
  /// config lands in `_connections`. Plain credentials keep their stored
  /// password inside the [PlainCredential] itself — that's the only
  /// password field that ever reaches disk.
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
    unawaited(_writeNow());
  }

  Future<void> _writeNow() async {
    try {
      await _file.save(_toJson());
    } catch (e, st) {
      developer.log(
        'failed to save store.json',
        name: 'aperture.store',
        error: e,
        stackTrace: st,
      );
      onSaveFailed?.call(e);
    }
  }

  Map<String, dynamic> _toJson() => {
    'version': 1,
    'preferences': {
      'brightness': _themeMode.name,
      'sidebarVisible': _sidebarVisible,
      'sidebarWidth': _sidebarWidth,
      'logPanelWidth': _logPanelWidth,
      'queryResultsFraction': _queryResultsFraction,
      if (_windowFramePersisted != null) 'windowFrame': _windowFramePersisted,
    },
    if (_security != null) 'security': _security,
    'connections': [for (final c in _connections) c.toJson()],
  };

  void _readSection(String name, void Function() read) {
    try {
      read();
    } catch (e, st) {
      developer.log(
        'failed to read $name from store.json',
        name: 'aperture.store',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _readPreferences(Object? raw) {
    if (raw is! Map) return;
    final modeName = raw['brightness'];
    if (modeName is String) {
      for (final m in AppThemeMode.values) {
        if (m.name == modeName) {
          _themeMode = m;
          break;
        }
      }
    }
    final sidebar = raw['sidebarVisible'];
    if (sidebar is bool) _sidebarVisible = sidebar;
    final sw = raw['sidebarWidth'];
    if (sw is num) {
      _sidebarWidth = sw.toDouble().clamp(sidebarWidthMin, sidebarWidthMax);
    }
    final lw = raw['logPanelWidth'];
    if (lw is num) {
      _logPanelWidth = lw.toDouble().clamp(logPanelWidthMin, logPanelWidthMax);
    }
    final qf = raw['queryResultsFraction'];
    if (qf is num) {
      _queryResultsFraction = qf.toDouble().clamp(
        queryResultsFractionMin,
        queryResultsFractionMax,
      );
    }
    final frame = raw['windowFrame'];
    if (frame is Map) {
      _windowFramePersisted = {
        'x': (frame['x'] as num).toDouble(),
        'y': (frame['y'] as num).toDouble(),
        'w': (frame['w'] as num).toDouble(),
        'h': (frame['h'] as num).toDouble(),
      };
    }
  }

  void _readConnections(Object? raw) {
    _connections.clear();
    if (raw is! List) return;
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        if (item['id'] is! String) continue;
        _connections.add(ConnectionConfig.fromJson(item));
      } catch (e, st) {
        developer.log(
          'failed to parse connection entry',
          name: 'aperture.store',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  void _readSecurity(Object? raw) {
    if (raw is Map<String, dynamic>) {
      _security = Map<String, dynamic>.of(raw);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
