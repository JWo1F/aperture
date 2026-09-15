import 'dart:convert';
import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/models/query_message.dart';
import 'package:aperture/services/atomic_json.dart';
import 'package:aperture/state/app_store.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

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

ConnectionConfig _conn(String id, {String name = 'a'}) {
  return ConnectionConfig(id: id, name: name);
}

DbTable _table(String schema, String name) {
  return DbTable(
    oid: 0,
    schema: schema,
    name: name,
    kind: DbRelationKind.table,
  );
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('app_store_test');
    PathProviderPlatform.instance = _StubPathProvider(dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  // Dispose every AppStore we create — a leftover 500ms debounce timer
  // from one test will otherwise fire mid-flight in the next test and
  // overwrite its store.json (the path_provider stub is global).
  AppStore makeStore({
    AtomicJsonFile? file,
    Duration debounce = const Duration(milliseconds: 30),
  }) {
    final store = AppStore(
      file: file ?? AtomicJsonFile('store.json'),
      saveDebounce: debounce,
    );
    addTearDown(store.dispose);
    return store;
  }

  test('load on a missing file lands on defaults without throwing', () async {
    final store = makeStore();
    await store.load();
    expect(store.connections, isEmpty);
    expect(store.sidebarVisible, isTrue);
    expect(store.isPassphraseConfigured, isFalse);
  });

  test('mutations coalesce: a burst within the window writes once', () async {
    final fake = _CountingAtomicJsonFile('store.json');
    final store = makeStore(file: fake);
    await store.load();
    for (var i = 0; i < 20; i++) {
      store.addConnection(_conn('c$i'));
    }
    expect(fake.writes, 0, reason: 'nothing should fire before the window');

    await store.flush();
    expect(fake.writes, 1, reason: '20 mutations must collapse to 1 write');
    final list = (fake.lastPayload as Map)['connections'] as List;
    expect(list, hasLength(20));
  });

  test('flush forces a pending debounced write', () async {
    final fake = _CountingAtomicJsonFile('store.json');
    final store = makeStore(file: fake, debounce: const Duration(seconds: 5));
    await store.load();
    store.addConnection(_conn('pending'));
    expect(fake.writes, 0);
    await store.flush();
    expect(fake.writes, 1);
  });

  test('connections survive a save/load round-trip', () async {
    final a = makeStore();
    await a.load();
    a.addConnection(_conn('a', name: 'A'));
    a.setSidebarWidth(320);
    await a.flush();

    final b = makeStore();
    await b.load();
    expect(b.connections, hasLength(1));
    expect(b.connections.first.id, 'a');
    expect(b.connections.first.name, 'A');
    expect(b.sidebarWidth, 320);
  });

  test('per-connection mutators write through to the connection bag', () async {
    final store = makeStore();
    await store.load();
    store.addConnection(_conn('c'));
    final tableA = _table('public', 'a');
    final tableB = _table('public', 'b');

    store.toggleFavorite('c', tableA);
    expect(store.connectionById('c')!.favoriteTables, {tableA.qualifiedKey});

    store.toggleFavorite('c', tableA);
    expect(store.connectionById('c')!.favoriteTables, isEmpty);

    store.trackRecentTable('c', tableA);
    store.trackRecentTable('c', tableB);
    expect(store.connectionById('c')!.recentTables, [
      tableB.qualifiedKey,
      tableA.qualifiedKey,
    ]);
    expect(store.connectionById('c')!.tableUseCounts[tableA.qualifiedKey], 1);

    store.setColumnWidth('c', tableA, 'id', 60);
    expect(store.connectionById('c')!.columnWidths[tableA.qualifiedKey], {
      'id': 60,
    });

    store.upsertSavedQuery('c', 'q1', 'My query', 'select 1');
    expect(store.connectionById('c')!.savedQueries, hasLength(1));
    expect(store.connectionById('c')!.savedQueries.first.name, 'My query');

    final message = QueryMessage(
      timestamp: DateTime(2026, 1, 1),
      sql: 'select 1',
      elapsedMs: 5,
    );
    store.appendQueryMessage('c', 'q1', message);
    expect(store.queryMessagesFor('c', 'q1'), hasLength(1));
    store.clearQueryMessages('c', 'q1');
    expect(store.queryMessagesFor('c', 'q1'), isEmpty);

    await store.flush();
  });

  test(
    'master passphrase round-trip: setup, encrypt, lock, unlock, decrypt',
    () async {
      final a = makeStore();
      await a.load();
      expect(await a.setupPassphrase('hunter22'), isTrue);
      expect(a.isPassphraseConfigured, isTrue);
      expect(a.isPassphraseUnlocked, isTrue);
      final cipher = a.encryptWithPassphrase('shh');
      a.lockPassphrase();
      expect(a.isPassphraseUnlocked, isFalse);
      expect(await a.unlockPassphrase('hunter22'), isTrue);
      expect(a.decryptWithPassphrase(cipher), 'shh');
      await a.flush();

      // Passphrase metadata persists across boot.
      final b = makeStore();
      await b.load();
      expect(b.isPassphraseConfigured, isTrue);
      expect(b.isPassphraseUnlocked, isFalse);
      expect(await b.unlockPassphrase('wrong'), isFalse);
      expect(await b.unlockPassphrase('hunter22'), isTrue);
      expect(b.decryptWithPassphrase(cipher), 'shh');
    },
  );

  test('runtime password never bleeds back into the store', () async {
    final fake = _CountingAtomicJsonFile('store.json');
    final store = makeStore(file: fake);
    await store.load();
    await store.setupPassphrase('hunter22');
    final cipher = store.encryptWithPassphrase('actual-password');
    final cfg = ConnectionConfig(
      id: 'c',
      name: 'x',
      credential: EncryptedCredential(cipher),
      runtimePassword: 'actual-password',
    );
    store.addConnection(cfg);
    await store.flush();
    final json = jsonEncode(fake.lastPayload);
    expect(
      json.contains('actual-password'),
      isFalse,
      reason: 'runtime plaintext must never reach disk',
    );
    expect(json.contains(cipher), isTrue, reason: 'cipher must persist');
    expect(
      store.connectionById('c')!.runtimePassword,
      isEmpty,
      reason: 'in-memory copy must also have runtimePassword stripped',
    );
  });

  test('credential round-trip preserves the sealed variant', () async {
    final a = makeStore();
    await a.load();
    a.addConnection(
      ConnectionConfig(
        id: 'p',
        name: 'plain',
        credential: const PlainCredential('pw'),
      ),
    );
    a.addConnection(
      ConnectionConfig(
        id: 'e',
        name: 'enc',
        credential: const EncryptedCredential('abc='),
      ),
    );
    a.addConnection(
      ConnectionConfig(
        id: 'o',
        name: 'op',
        credential: const OnePasswordCredential('op://Vault/Item/password'),
      ),
    );
    await a.flush();

    final b = makeStore();
    await b.load();
    expect(b.connectionById('p')!.credential, isA<PlainCredential>());
    expect(
      (b.connectionById('p')!.credential as PlainCredential).password,
      'pw',
    );
    expect(b.connectionById('e')!.credential, isA<EncryptedCredential>());
    expect(
      (b.connectionById('e')!.credential as EncryptedCredential).cipher,
      'abc=',
    );
    expect(b.connectionById('o')!.credential, isA<OnePasswordCredential>());
    expect(
      (b.connectionById('o')!.credential as OnePasswordCredential).secretRef,
      'op://Vault/Item/password',
    );
  });

  group('theme mode', () {
    // AppColors is process-global; a test that leaves the light palette
    // pinned would decide the next one's colours.
    tearDown(() => AppColors.setPalette(darkPalette));

    test('auto resolves against the system and follows a flip', () async {
      final store = makeStore();
      store.setSystemBrightness(AppBrightness.light);
      await store.load();
      store.setThemeMode(AppThemeMode.auto);
      expect(store.brightness, AppBrightness.light);
      expect(AppColors.palette, lightPalette);

      var ticks = 0;
      store.addListener(() => ticks++);
      store.setSystemBrightness(AppBrightness.dark);

      expect(store.brightness, AppBrightness.dark);
      expect(AppColors.palette, darkPalette);
      expect(ticks, 1, reason: 'the whole tree has to repaint');
    });

    test('a pinned mode ignores the system', () async {
      final store = makeStore();
      await store.load();
      store.setThemeMode(AppThemeMode.light);
      var ticks = 0;
      store.addListener(() => ticks++);

      store.setSystemBrightness(AppBrightness.dark);

      expect(store.brightness, AppBrightness.light);
      expect(AppColors.palette, lightPalette);
      expect(ticks, 0);
    });

    test('the cycle visits every mode and returns', () async {
      final store = makeStore();
      await store.load();
      expect(store.themeMode, AppThemeMode.auto);
      store.cycleThemeMode();
      expect(store.themeMode, AppThemeMode.dark);
      store.cycleThemeMode();
      expect(store.themeMode, AppThemeMode.light);
      store.cycleThemeMode();
      expect(store.themeMode, AppThemeMode.auto);
    });

    test('the mode survives a save/load round-trip', () async {
      final a = makeStore();
      await a.load();
      a.setThemeMode(AppThemeMode.light);
      await a.flush();

      final b = makeStore();
      b.setSystemBrightness(AppBrightness.dark);
      await b.load();
      expect(b.themeMode, AppThemeMode.light);
      expect(b.brightness, AppBrightness.light);
      expect(AppColors.palette, lightPalette);
    });

    test('a store with no preference follows the system', () async {
      final store = makeStore();
      store.setSystemBrightness(AppBrightness.light);
      await store.load();
      expect(store.themeMode, AppThemeMode.auto);
      expect(store.brightness, AppBrightness.light);
      expect(AppColors.palette, lightPalette);
    });

    test(
      'a store written before auto existed still reads its palette',
      () async {
        await File('${dir.path}/store.json').writeAsString(
          jsonEncode({
            'version': 1,
            'preferences': {'brightness': 'light'},
          }),
        );
        final store = makeStore();
        await store.load();
        expect(store.themeMode, AppThemeMode.light);
        expect(AppColors.palette, lightPalette);
      },
    );
  });
}
