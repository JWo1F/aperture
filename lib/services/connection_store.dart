import 'dart:async';
import 'dart:developer' as developer;

import '../models/connection_config.dart';
import 'atomic_json.dart';

/// Persists saved connections to a JSON file in the application support
/// directory.
///
/// Plain-source connections carry their password verbatim in the JSON.
/// Encrypted-source connections carry only the AES-GCM ciphertext.
/// 1Password-source connections carry only the `op://` reference. The
/// store doesn't know about credentials beyond that — encryption +
/// decryption are owned by [MasterPassphrase].
class ConnectionStore {
  ConnectionStore({AtomicJsonFile? file})
    : _file = file ?? AtomicJsonFile('connections.json');

  final AtomicJsonFile _file;

  Future<List<ConnectionConfig>> load() async {
    final decoded = await _file.load();
    if (decoded is! List) return [];
    final configs = <ConnectionConfig>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      try {
        final id = item['id'] as String?;
        if (id == null) continue;
        configs.add(ConnectionConfig.fromJson(item));
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
