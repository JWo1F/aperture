import 'dart:async';
import 'dart:developer' as developer;

import 'atomic_json.dart';

/// Persists the master-passphrase verifier and KDF parameters in
/// `security.json` alongside `connections.json`.
///
/// The file is small and tolerant of corruption — losing it just means
/// the user has to set up a passphrase again (and re-enter encrypted
/// connection passwords, since the derived key is gone).
class SecurityStore {
  SecurityStore({AtomicJsonFile? file})
    : _file = file ?? AtomicJsonFile('security.json');

  final AtomicJsonFile _file;

  Future<Map<String, dynamic>?> load() async {
    try {
      final decoded = await _file.load();
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e, st) {
      developer.log(
        'failed to load security.json',
        name: 'dbv.security',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> data) => _file.save(data);
}
