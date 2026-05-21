import 'dart:async';
import 'dart:developer' as developer;

import '../models/connection_config.dart';
import 'atomic_json.dart';
import 'password_vault.dart';

/// Persists saved connections to a JSON file in the application support
/// directory. Passwords live in [PasswordVault] (macOS Keychain) and never
/// touch the JSON file.
///
/// Passwords are read lazily — [load] hydrates configs with an empty
/// password and the caller fetches the real value via [readPassword] only
/// when the user actually opens a connection. Eagerly reading on startup
/// would trigger a macOS keychain access prompt per saved connection, and
/// debug rebuilds re-sign the app so the prompts repeat every launch.
class ConnectionStore {
  ConnectionStore({AtomicJsonFile? file, PasswordVault? vault})
      : _file = file ?? AtomicJsonFile('connections.json'),
        _vault = vault ?? PasswordVault();

  final AtomicJsonFile _file;
  final PasswordVault _vault;

  Future<List<ConnectionConfig>> load() async {
    final decoded = await _file.load();
    if (decoded is! List) return [];
    final configs = <ConnectionConfig>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final id = item['id'] as String?;
        if (id == null) continue;
        configs.add(
          ConnectionConfig.fromJson({...item, 'password': ''}),
        );
      } catch (e, st) {
        developer.log(
          'failed to parse connection entry',
          name: 'dbv.store',
          error: e,
          stackTrace: st,
        );
      }
    }
    return configs;
  }

  /// Reads the password for [connectionId] from the vault on demand.
  /// Returns the empty string when the user cancels Touch ID or no entry
  /// exists. [reason] is shown in the system biometric prompt.
  Future<String> readPassword(String connectionId, {String? reason}) async {
    return await _vault.read(connectionId, reason: reason) ?? '';
  }

  /// Writes [password] to the vault for [connectionId]. Called explicitly
  /// when the user sets or rotates a password, never as a side effect of
  /// metadata saves.
  Future<void> writePassword(String connectionId, String password) =>
      _vault.write(connectionId, password);

  /// Persists connection metadata to the JSON file. Does not touch the
  /// vault — passwords are stored independently through [writePassword]
  /// so unrelated saves (column widths, favorites, recents) never trigger
  /// a keychain access prompt.
  Future<void> save(List<ConnectionConfig> connections) async {
    try {
      await _file.save([
        for (final c in connections) c.toJson()..remove('password'),
      ]);
    } catch (e, st) {
      developer.log(
        'failed to save connections',
        name: 'dbv.store',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> deletePassword(String connectionId) =>
      _vault.delete(connectionId);
}
