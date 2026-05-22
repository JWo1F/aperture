import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/connection_config.dart';
import '../services/connection_store.dart';
import '../services/one_password_client.dart';
import 'master_passphrase.dart';

/// Outcome of resolving a connection's password.
sealed class CredentialResult {
  const CredentialResult();
}

/// Password resolved successfully — ready to hand to the postgres driver.
class CredentialOk extends CredentialResult {
  const CredentialOk(this.password);
  final String password;
}

/// The connection is encrypted and the master passphrase is locked.
/// AppState handles this by showing the unlock modal, then re-dispatching.
class CredentialNeedsPassphrase extends CredentialResult {
  const CredentialNeedsPassphrase();
}

/// Terminal failure (bad cipher, missing op CLI, op invocation error).
class CredentialError extends CredentialResult {
  const CredentialError(this.message);
  final String message;
}

/// Owns the persisted list of saved connections.
///
/// CRUD + persistence only — knowing which one is currently *active* lives
/// in [SessionController]. Per-connection bags (favorites, recents, saved
/// queries, column widths) are mutated through [PerConnectionStore], which
/// goes through `update()` here to land in the same JSON file.
class ConnectionRegistry extends ChangeNotifier {
  ConnectionRegistry({
    ConnectionStore? store,
    OnePasswordClient? onePassword,
    required MasterPassphrase masterPassphrase,
  }) : _store = store ?? ConnectionStore(),
       _op = onePassword ?? OnePasswordClient(),
       _passphrase = masterPassphrase;

  final ConnectionStore _store;
  final OnePasswordClient _op;
  final MasterPassphrase _passphrase;
  final List<ConnectionConfig> _connections = [];

  List<ConnectionConfig> get all => List.unmodifiable(_connections);

  /// Top-3 most recently used, freshest first. Drives the welcome cards.
  List<ConnectionConfig> get recent {
    final stamped =
        _connections.where((c) => c.lastConnectedAt != null).toList()
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

  /// Resolves the password for [config] based on its [CredentialSource]:
  /// inline for plain, AES-GCM decrypt for encrypted, `op read` for
  /// 1Password.
  Future<CredentialResult> readCredential(ConnectionConfig config) async {
    switch (config.credentialSource) {
      case CredentialSource.plain:
        return CredentialOk(config.password);
      case CredentialSource.encrypted:
        final cipher = config.passwordCipher;
        if (cipher == null || cipher.isEmpty) {
          return const CredentialError(
            'No stored password for this connection — edit it to set one.',
          );
        }
        if (!_passphrase.isUnlocked) {
          return const CredentialNeedsPassphrase();
        }
        final plain = _passphrase.decrypt(cipher);
        if (plain == null) {
          return const CredentialError(
            'Could not decrypt the saved password. The master passphrase '
            'may be wrong, or the stored ciphertext was tampered with.',
          );
        }
        return CredentialOk(plain);
      case CredentialSource.onePassword:
        final ref = config.opSecretRef ?? '';
        if (ref.isEmpty) {
          return const CredentialError(
            'No 1Password secret reference set for this connection.',
          );
        }
        final r = await _op.read(ref);
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

  void add(ConnectionConfig config) {
    _connections.add(_strip(config));
    _persist();
    notifyListeners();
  }

  /// Replace the config with id == [config.id]. Metadata only — the
  /// runtime password in [config] is blanked for non-plain sources so
  /// frequent metadata pings (column widths, favorites, recents) never
  /// rewrite credentials.
  ConnectionConfig? update(ConnectionConfig config) {
    final i = _connections.indexWhere((c) => c.id == config.id);
    if (i == -1) return null;
    final prev = _connections[i];
    _connections[i] = _strip(config);
    _persist();
    notifyListeners();
    return prev;
  }

  void remove(String id) {
    _connections.removeWhere((c) => c.id == id);
    _persist();
    notifyListeners();
  }

  /// Plain configs keep the runtime password (it lives in the JSON
  /// file). Encrypted and 1Password configs blank it so unrelated
  /// updates can't leak plaintext back into the store.
  ConnectionConfig _strip(ConnectionConfig config) {
    if (config.credentialSource == CredentialSource.plain) return config;
    if (config.password.isEmpty) return config;
    return config.copyWith(password: '');
  }

  /// Funnel every mutation through the store's debounce. A burst of
  /// per-connection bag updates (favourite toggle, recent track, use-count
  /// bump, query autosave) coalesces into one write; the underlying
  /// [AtomicJsonFile] also serializes any writes that do overlap, so
  /// concurrent mutations can't race on rename(2).
  void _persist() => _store.saveDebounced(_connections);

  /// Forces any pending debounced write to land and awaits the in-flight
  /// chain. Called from [AppState.dispose] via [AppState.flush] so the app
  /// can't quit mid-debounce and silently lose a recently-toggled
  /// favourite or a freshly-autosaved query.
  Future<void> flush() => _store.flush();
}
