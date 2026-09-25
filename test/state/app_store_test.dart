import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/models/query_message.dart';
import 'package:aperture/services/store_database.dart';
import 'package:aperture/state/app_store.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

class _CountingStore extends StoreDatabase {
  _CountingStore() : super(sqlite3.openInMemory());
  int writes = 0;
  StoreSnapshot? last;

  @override
  void save(StoreSnapshot snapshot) {
    writes++;
    last = snapshot;
    super.save(snapshot);
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
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('app_store_test');
    path = '${dir.path}/store.sqlite';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  // Dispose every AppStore we create — a leftover 500ms debounce timer
  // from one test would otherwise fire mid-flight in the next.
  AppStore makeStore({Duration debounce = const Duration(milliseconds: 30)}) {
    final store = AppStore(saveDebounce: debounce);
    addTearDown(store.dispose);
    return store;
  }

  /// Opens [store] on the test's encrypted file, or on [db].
  void open(AppStore store, [StoreDatabase? db]) =>
      store.open(db ?? StoreDatabase.open(path, 'pw'));

  test('before open the store holds defaults and writes nothing', () async {
    final store = makeStore();
    expect(store.isOpen, isFalse);
    store.setSidebarWidth(300);
    await store.flush();
    expect(File(path).existsSync(), isFalse);
  });

  test('a new store opens on defaults', () async {
    final store = makeStore();
    open(store);
    expect(store.connections, isEmpty);
    expect(store.sidebarVisible, isTrue);
  });

  test('mutations coalesce: a burst within the window writes once', () async {
    final fake = _CountingStore();
    final store = makeStore();
    open(store, fake);
    for (var i = 0; i < 20; i++) {
      store.addConnection(_conn('c$i'));
    }
    expect(fake.writes, 0, reason: 'nothing should fire before the window');

    await store.flush();
    expect(fake.writes, 1, reason: '20 mutations must collapse to 1 write');
    expect(fake.last!.connections, hasLength(20));
  });

  test('flush forces a pending debounced write', () async {
    final fake = _CountingStore();
    final store = makeStore(debounce: const Duration(seconds: 5));
    open(store, fake);
    store.addConnection(_conn('pending'));
    expect(fake.writes, 0);
    await store.flush();
    expect(fake.writes, 1);
  });

  test('connections survive a save/load round-trip', () async {
    final a = makeStore();
    open(a);
    a.addConnection(_conn('a', name: 'A'));
    a.setSidebarWidth(320);
    await a.flush();

    final b = makeStore();
    open(b);
    expect(b.connections, hasLength(1));
    expect(b.connections.first.id, 'a');
    expect(b.connections.first.name, 'A');
    expect(b.sidebarWidth, 320);
  });

  test('per-connection mutators write through to the connection bag', () async {
    final store = makeStore();
    open(store);
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

  test('runtime password never bleeds back into the store', () async {
    final store = makeStore();
    open(store);
    final cfg = ConnectionConfig(
      id: 'c',
      name: 'x',
      credential: const CommandCredential('op read x'),
      runtimePassword: 'actual-password',
    );
    store.addConnection(cfg);
    await store.flush();
    final reopened = StoreDatabase.open(path, 'pw');
    addTearDown(reopened.close);
    final saved = reopened.load().connections.single;
    expect(
      saved.runtimePassword,
      isEmpty,
      reason: 'runtime plaintext must never reach disk',
    );
    expect(
      (saved.credential as CommandCredential).command,
      'op read x',
      reason: 'command must persist',
    );
    expect(
      store.connectionById('c')!.runtimePassword,
      isEmpty,
      reason: 'in-memory copy must also have runtimePassword stripped',
    );
  });

  test('credential round-trip preserves the sealed variant', () async {
    final a = makeStore();
    open(a);
    a.addConnection(
      ConnectionConfig(
        id: 'p',
        name: 'password',
        credential: const PasswordCredential('pw'),
      ),
    );
    a.addConnection(
      ConnectionConfig(
        id: 'c',
        name: 'command',
        credential: const CommandCredential("op read 'op://V/I/password'"),
      ),
    );
    await a.flush();

    final b = makeStore();
    open(b);
    expect(
      (b.connectionById('p')!.credential as PasswordCredential).password,
      'pw',
    );
    expect(
      (b.connectionById('c')!.credential as CommandCredential).command,
      "op read 'op://V/I/password'",
    );
  });

  group('theme mode', () {
    // AppColors is process-global; a test that leaves the light palette
    // pinned would decide the next one's colours.
    tearDown(() => AppColors.setPalette(darkPalette));

    test('auto resolves against the system and follows a flip', () async {
      final store = makeStore();
      store.setSystemBrightness(AppBrightness.light);
      open(store);
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
      open(store);
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
      open(store);
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
      open(a);
      a.setThemeMode(AppThemeMode.light);
      await a.flush();

      final b = makeStore();
      b.setSystemBrightness(AppBrightness.dark);
      open(b);
      expect(b.themeMode, AppThemeMode.light);
      expect(b.brightness, AppBrightness.light);
      expect(AppColors.palette, lightPalette);
    });

    test('a store with no preference follows the system', () async {
      final store = makeStore();
      store.setSystemBrightness(AppBrightness.light);
      open(store);
      expect(store.themeMode, AppThemeMode.auto);
      expect(store.brightness, AppBrightness.light);
      expect(AppColors.palette, lightPalette);
    });
  });
}
