import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Crash-safe JSON-on-disk helper used by [ConnectionStore] and
/// [PreferencesStore].
///
/// Writes go to `<name>.tmp`, are flushed to disk, then atomically renamed
/// over the destination. POSIX guarantees rename(2) atomicity on the same
/// filesystem, and APFS honours it — a crash or power loss can never leave
/// the destination half-written.
///
/// Loads that fail to decode preserve the offending file as `<name>.bak.<ts>`
/// so a corrupt write never silently wipes the user's data.
class AtomicJsonFile {
  AtomicJsonFile(this.filename);

  final String filename;

  // Serializes overlapping save() calls so two writers can't both truncate
  // the same `.tmp` file and race on rename(2). Without this, the loser's
  // rename throws PathNotFoundException because the winner already moved
  // the tmp aside.
  Future<void> _writeChain = Future.value();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$filename');
  }

  Future<Object?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (e, st) {
      developer.log(
        'corrupt JSON in $filename — preserving as .bak',
        name: 'aperture.store',
        error: e,
        stackTrace: st,
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      try {
        await file.rename('${file.path}.bak.$ts');
      } catch (renameErr, renameSt) {
        developer.log(
          'failed to preserve corrupt $filename',
          name: 'aperture.store',
          error: renameErr,
          stackTrace: renameSt,
        );
      }
      return null;
    }
  }

  Future<void> save(Object data) {
    final next = _writeChain.then((_) => _save(data));
    _writeChain = next.catchError((_) {});
    return next;
  }

  /// Resolves once every save scheduled before this call has finished. Used
  /// by [ConnectionStore.flush] on shutdown to make sure pending writes
  /// reach disk before the process exits.
  Future<void> drain() => _writeChain;

  Future<void> _save(Object data) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeString(jsonEncode(data));
      await raf.flush();
    } finally {
      await raf.close();
    }
    await tmp.rename(file.path);
  }
}
