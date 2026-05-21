import 'dart:io';

import 'package:dbv/services/atomic_json.dart';
import 'package:dbv/services/security_store.dart';
import 'package:dbv/state/master_passphrase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('master_passphrase_test');
    PathProviderPlatform.instance = _StubPathProvider(dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  MasterPassphrase build() => MasterPassphrase(
    store: SecurityStore(file: AtomicJsonFile('security.json')),
  );

  test('setup → unlock round-trip', () async {
    final mp = build();
    await mp.hydrate();
    expect(mp.isConfigured, false);
    expect(mp.isUnlocked, false);

    final ok = await mp.setup('correct horse');
    expect(ok, true);
    expect(mp.isConfigured, true);
    expect(mp.isUnlocked, true);

    final cipher = mp.encrypt('hunter2');
    expect(cipher.isNotEmpty, true);

    mp.lock();
    expect(mp.isUnlocked, false);

    final fresh = build();
    await fresh.hydrate();
    expect(fresh.isConfigured, true);
    expect(fresh.isUnlocked, false);

    expect(await fresh.unlock('wrong'), false);
    expect(fresh.isUnlocked, false);

    expect(await fresh.unlock('correct horse'), true);
    expect(fresh.decrypt(cipher), 'hunter2');
  });

  test('decrypt returns null on tampered ciphertext', () async {
    final mp = build();
    await mp.hydrate();
    await mp.setup('pw');
    final cipher = mp.encrypt('secret');
    final mangled = '${cipher.substring(0, cipher.length - 4)}AAAA';
    expect(mp.decrypt(mangled), null);
  });
}
