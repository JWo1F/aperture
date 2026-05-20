import 'dart:async';
import 'dart:developer' as developer;

import '../models/connection_config.dart';
import 'atomic_json.dart';
import 'password_vault.dart';

/// Persists saved connections to a JSON file in the application support
/// directory. Passwords live in [PasswordVault] (macOS Keychain) and never
/// touch the JSON file.
///
/// The first launch after upgrading from a plaintext-passwords version
/// detects any embedded `password` field, migrates it into the vault, and
/// rewrites the file without it.
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
    var didMigrate = false;
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final id = item['id'] as String?;
        if (id == null) continue;
        final plaintext = item['password'] as String?;
        if (plaintext != null) {
          await _vault.write(id, plaintext);
          item.remove('password');
          didMigrate = true;
        }
        final fromVault = await _vault.read(id) ?? '';
        configs.add(
          ConnectionConfig.fromJson({...item, 'password': fromVault}),
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
    if (didMigrate) {
      await save(configs);
    }
    return configs;
  }

  Future<void> save(List<ConnectionConfig> connections) async {
    try {
      for (final c in connections) {
        await _vault.write(c.id, c.password);
      }
      await _file.save([
        for (final c in connections)
          c.toJson()..remove('password'),
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
