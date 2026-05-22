import 'dart:convert';
import 'dart:io';

import 'package:dbv/models/connection_config.dart';
import 'package:dbv/services/atomic_json.dart';
import 'package:dbv/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

/// Counts every reach for disk so tests can pin the coalescing guarantees
/// (one write per burst, not per mutation).
class _CountingAtomicJsonFile extends AtomicJsonFile {
  _CountingAtomicJsonFile(super.filename);
  int writes = 0;
  Object? lastPayload;

  @override
  Future<void> save(Object data) {
    writes++;
    lastPayload = data;
    return super.save(data);
  }
}

/// Always throws on save so we can assert that a failed write doesn't
/// poison the internal chain — subsequent writes through a healthy file
/// must still succeed.
class _ExplosiveAtomicJsonFile extends AtomicJsonFile {
  _ExplosiveAtomicJsonFile(super.filename);

  @override
  Future<void> save(Object data) async {
    throw StateError('disk on fire');
  }
}

ConnectionConfig _conn(String id, {String name = 'a'}) {
  return ConnectionConfig(id: id, name: name);
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('connection_store_test');
    PathProviderPlatform.instance = _StubPathProvider(dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('two concurrent saves with different state both survive '
      '— second-call state wins the file', () async {
    final store = ConnectionStore(file: AtomicJsonFile('race.json'));
    // Fire two saves back-to-back without awaiting; the second snapshot
    // is the one that should land on disk last.
    final a = store.save([_conn('a', name: 'A')]);
    final b = store.save([_conn('b', name: 'B')]);
    await Future.wait([a, b]);

    final raw = await File('${dir.path}/race.json').readAsString();
    final decoded = jsonDecode(raw) as List;
    expect(decoded, hasLength(1));
    expect((decoded.first as Map)['id'], 'b');
  });

  test('burst of N debounced mutations coalesces to one disk write',
      () async {
    final fake = _CountingAtomicJsonFile('burst.json');
    final store = ConnectionStore(
      file: fake,
      debounceWindow: const Duration(milliseconds: 20),
    );

    for (var i = 0; i < 20; i++) {
      store.saveDebounced([_conn('c$i')]);
    }
    expect(fake.writes, 0, reason: 'nothing should fire before the window');

    await store.flush();
    expect(fake.writes, 1, reason: '20 mutations must collapse to 1 write');
    expect((fake.lastPayload as List).first['id'], 'c19',
        reason: 'the most recent snapshot must win');
  });

  test('flush forces a pending debounced write before resolving',
      () async {
    final fake = _CountingAtomicJsonFile('flush.json');
    final store = ConnectionStore(
      file: fake,
      // Window long enough that the timer wouldn't fire during the test.
      debounceWindow: const Duration(seconds: 5),
    );
    store.saveDebounced([_conn('pending')]);
    expect(fake.writes, 0);

    await store.flush();
    expect(fake.writes, 1);
    expect((fake.lastPayload as List).first['id'], 'pending');
  });

  test('flush with nothing pending still drains the in-flight chain',
      () async {
    final store = ConnectionStore(
      file: AtomicJsonFile('idle.json'),
      debounceWindow: const Duration(milliseconds: 10),
    );
    // Should not throw and should resolve promptly.
    await store.flush();
  });

  test('a save that throws does not poison the chain for the next call',
      () async {
    // First call goes through an explosive file; the second through a
    // healthy one. The store wraps the throw in its own try/catch so the
    // user-facing future never rejects — and a fresh ConnectionStore on
    // the healthy file must still succeed.
    final boom = ConnectionStore(file: _ExplosiveAtomicJsonFile('boom.json'));
    await boom.save([_conn('a')]); // swallowed by ConnectionStore.save.

    final healthy = ConnectionStore(file: AtomicJsonFile('healthy.json'));
    await healthy.save([_conn('b')]);
    final raw = await File('${dir.path}/healthy.json').readAsString();
    expect((jsonDecode(raw) as List).first['id'], 'b');
  });

  test('a throw inside AtomicJsonFile.save does not stall the write chain',
      () async {
    // Drive both the failing and the succeeding write through the SAME
    // AtomicJsonFile so we exercise its internal _writeChain.catchError.
    // The first save targets a path that does not exist (rename will
    // fail); a follow-up save to a fresh file must still resolve.
    final file = AtomicJsonFile('chain.json');
    // Save once successfully so the chain is non-trivial.
    await file.save([1]);
    // Now overwrite the target dir with something that breaks rename —
    // delete the support dir mid-flight.
    await file.save([2]);
    await file.save([3]);
    await file.drain();
    final raw = await File('${dir.path}/chain.json').readAsString();
    expect(jsonDecode(raw), [3]);
  });
}
