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
///
/// Every per-connection mutation (favourite toggle, recent-table track,
/// use-count bump, saved-query autosave, column-width flush) ultimately
/// rewrites this entire JSON file. Without coalescing, a single table
/// open fires two writes back-to-back ([trackRecent] does two `_mutate`s)
/// and a column-width drag fires many. [saveDebounced] funnels a burst
/// into a single write at the end of [debounceWindow]; the underlying
/// [AtomicJsonFile] serializes any overlapping writes via its own
/// internal chain. [flush] is the shutdown hook that forces a pending
/// debounced write to land before the process exits.
class ConnectionStore {
  ConnectionStore({
    AtomicJsonFile? file,
    this.debounceWindow = const Duration(milliseconds: 100),
  }) : _file = file ?? AtomicJsonFile('connections.json');

  final AtomicJsonFile _file;
  final Duration debounceWindow;

  Timer? _debounceTimer;
  List<ConnectionConfig>? _pending;

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

  /// Write [connections] to disk immediately. Concurrent calls don't race —
  /// [AtomicJsonFile] chains overlapping writes — but they each produce
  /// one I/O. Prefer [saveDebounced] for high-frequency mutations.
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

  /// Coalesces a burst of mutations into one disk write at the end of
  /// [debounceWindow]. Each call overwrites the pending snapshot, so only
  /// the most recent state survives — earlier calls' lists are dropped on
  /// the floor (correct: every snapshot represents the full state).
  void saveDebounced(List<ConnectionConfig> connections) {
    _pending = List.of(connections);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceWindow, _firePending);
  }

  void _firePending() {
    _debounceTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    unawaited(save(pending));
  }

  /// Drains the debounce + the underlying write chain so callers can wait
  /// for every queued mutation to hit disk. Must be awaited from the app's
  /// shutdown path; otherwise a debounced favourite toggle or query edit
  /// pending at quit time would be lost.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      await save(pending);
    }
    await _file.drain();
  }
}
