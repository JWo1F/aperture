import 'dart:async';
import 'dart:developer' as developer;

import '../models/connection_config.dart';
import 'atomic_json.dart';

/// Persists saved connections to a JSON file in the application support
/// directory. Personal use only — passwords live in the macOS Keychain
/// (see [PasswordVault]); this file holds the rest of the config.
class ConnectionStore {
  ConnectionStore({AtomicJsonFile? file})
      : _file = file ?? AtomicJsonFile('connections.json');

  final AtomicJsonFile _file;

  Future<List<ConnectionConfig>> load() async {
    final decoded = await _file.load();
    if (decoded is! List) return [];
    try {
      return [
        for (final item in decoded)
          ConnectionConfig.fromJson(item as Map<String, dynamic>),
      ];
    } catch (e, st) {
      developer.log(
        'failed to parse connections list',
        name: 'dbv.store',
        error: e,
        stackTrace: st,
      );
      return [];
    }
  }

  Future<void> save(List<ConnectionConfig> connections) async {
    try {
      await _file.save([for (final c in connections) c.toJson()]);
    } catch (e, st) {
      developer.log(
        'failed to save connections',
        name: 'dbv.store',
        error: e,
        stackTrace: st,
      );
    }
  }
}
