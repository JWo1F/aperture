import 'dart:async';
import 'dart:developer' as developer;

import 'atomic_json.dart';

/// Tiny JSON-backed bag for global app preferences (theme, window size, etc.).
/// Kept separate from [ConnectionStore] so a corrupt write here can't take
/// down the saved-connection list.
class PreferencesStore {
  PreferencesStore({AtomicJsonFile? file})
      : _file = file ?? AtomicJsonFile('preferences.json');

  final AtomicJsonFile _file;

  Future<Map<String, dynamic>> load() async {
    final decoded = await _file.load();
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  Future<void> save(Map<String, dynamic> prefs) async {
    try {
      await _file.save(prefs);
    } catch (e, st) {
      developer.log(
        'failed to save preferences',
        name: 'dbv.store',
        error: e,
        stackTrace: st,
      );
    }
  }
}
