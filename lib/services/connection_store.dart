import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/connection_config.dart';

/// Persists saved connections to a JSON file in the application support
/// directory. Personal use only — passwords are stored in plain text, behind
/// the macOS app-sandbox container which is per-user-account.
class ConnectionStore {
  static const _filename = 'connections.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_filename');
  }

  Future<List<ConnectionConfig>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return [
        for (final item in list)
          ConnectionConfig.fromJson(item as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ConnectionConfig> connections) async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode([for (final c in connections) c.toJson()]),
      );
    } catch (_) {
      // Best-effort: a write failure here only loses the index, not data.
    }
  }
}
