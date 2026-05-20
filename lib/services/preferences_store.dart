import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny JSON-backed bag for global app preferences (theme, etc.). Kept
/// separate from [ConnectionStore] so a corrupt write here can't take down
/// the saved-connection list.
class PreferencesStore {
  static const _filename = 'preferences.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_filename');
  }

  Future<Map<String, dynamic>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, dynamic> prefs) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(prefs));
    } catch (_) {
      // Best-effort.
    }
  }
}
