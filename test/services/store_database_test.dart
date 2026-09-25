import 'dart:convert';
import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/models/query_message.dart';
import 'package:aperture/models/saved_query.dart';
import 'package:aperture/services/store_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('store_db');
    path = '${dir.path}/${StoreDatabase.fileName}';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  StoreDatabase openStore([String passphrase = 'correct horse']) {
    final db = StoreDatabase.open(path, passphrase);
    addTearDown(db.close);
    return db;
  }

  final connection = ConnectionConfig(
    id: 'c1',
    name: 'Production',
    host: 'db.internal',
    port: 6432,
    database: 'app',
    username: 'alice',
    credential: const CommandCredential("op read 'op://V/I/password'"),
    useSsl: true,
    readOnly: true,
    color: 0xFF3B82F6,
    lastConnectedAt: DateTime.fromMillisecondsSinceEpoch(1_760_000_000_000),
    favoriteTables: {'public.users'},
    recentTables: ['public.orders', 'public.users'],
    tableUseCounts: {'public.users': 7, 'public.orders': 2},
    columnWidths: {
      'public.users': {'id': 60.0, 'email': 240.5},
    },
    savedQueries: [
      SavedQuery(
        id: 'q1',
        name: 'recent signups',
        sql: 'select * from users',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1_760_000_100_000),
      ),
      SavedQuery(id: 'q2', name: 'untouched', sql: ''),
    ],
    queryMessages: {
      'q1': [
        QueryMessage(
          timestamp: DateTime.fromMillisecondsSinceEpoch(1_760_000_200_000),
          sql: 'select 1',
          elapsedMs: 4,
          affectedRows: 1,
        ),
        QueryMessage(
          timestamp: DateTime.fromMillisecondsSinceEpoch(1_760_000_300_000),
          sql: 'select nope',
          error: 'column "nope" does not exist',
        ),
      ],
    },
  );

  final sqlite = ConnectionConfig(
    id: 'c2',
    name: 'Local',
    engine: DbEngine.sqlite,
    filePath: '/Users/me/app.db',
    credential: const PasswordCredential("it's secret"),
  );

  test('a snapshot round-trips every field and bag', () {
    openStore().save(
      StoreSnapshot(
        preferences: {'themeMode': 'light', 'sidebarVisible': 0, 'w': 1.5},
        connections: [connection, sqlite],
      ),
    );

    final loaded = openStore().load();
    expect(loaded.preferences, {
      'themeMode': 'light',
      'sidebarVisible': 0,
      'w': 1.5,
    });
    expect(loaded.connections.map((c) => c.id), ['c1', 'c2']);

    final c = loaded.connections.first;
    expect(c.name, 'Production');
    expect(c.host, 'db.internal');
    expect(c.port, 6432);
    expect(c.useSsl, isTrue);
    expect(c.readOnly, isTrue);
    expect(c.color, 0xFF3B82F6);
    expect(c.lastConnectedAt, connection.lastConnectedAt);
    expect(
      (c.credential as CommandCredential).command,
      "op read 'op://V/I/password'",
    );
    expect(c.favoriteTables, {'public.users'});
    expect(c.recentTables, ['public.orders', 'public.users']);
    expect(c.tableUseCounts, {'public.users': 7, 'public.orders': 2});
    expect(c.columnWidths, {
      'public.users': {'id': 60.0, 'email': 240.5},
    });
    expect(c.savedQueries.map((q) => q.id), ['q1', 'q2']);
    expect(
      c.savedQueries.first.updatedAt,
      connection.savedQueries[0].updatedAt,
    );
    expect(c.savedQueries.last.updatedAt, isNull);
    final messages = c.queryMessages['q1']!;
    expect(messages.map((m) => m.sql), ['select 1', 'select nope']);
    expect(messages.first.elapsedMs, 4);
    expect(messages.last.error, contains('nope'));

    final s = loaded.connections.last;
    expect(s.engine, DbEngine.sqlite);
    expect(s.filePath, '/Users/me/app.db');
    expect((s.credential as PasswordCredential).password, "it's secret");
  });

  test('a save replaces the previous snapshot rather than merging', () {
    final db = openStore();
    db.save(StoreSnapshot(preferences: {}, connections: [connection, sqlite]));
    db.save(StoreSnapshot(preferences: {}, connections: [sqlite]));
    final loaded = db.load();
    expect(loaded.connections.map((c) => c.id), ['c2']);
  });

  test('nothing readable reaches the disk', () {
    openStore().save(
      StoreSnapshot(preferences: {}, connections: [connection, sqlite]),
    );
    final raw = File(path).readAsStringSync(encoding: latin1);
    for (final plain in ['db.internal', "it's secret", 'recent signups']) {
      expect(raw, isNot(contains(plain)));
    }
  });

  test('a wrong passphrase is refused', () {
    openStore().save(StoreSnapshot.empty);
    expect(
      () => StoreDatabase.open(path, 'wrong'),
      throwsA(isA<WrongPassphraseException>()),
    );
  });

  test('a passphrase with quotes works', () {
    openStore(
      "o'brien \"q\"",
    ).save(StoreSnapshot(preferences: {}, connections: [sqlite]));
    expect(openStore("o'brien \"q\"").load().connections, hasLength(1));
  });

  test('rekey moves the store to the new passphrase', () {
    final db = openStore('old');
    db.save(StoreSnapshot(preferences: {}, connections: [sqlite]));
    db.rekey('new');
    expect(
      () => StoreDatabase.open(path, 'old'),
      throwsA(isA<WrongPassphraseException>()),
    );
    expect(openStore('new').load().connections, hasLength(1));
  });

  test('erase removes the store', () {
    StoreDatabase.open(path, 'pw')
      ..save(StoreSnapshot.empty)
      ..close();
    expect(StoreDatabase.exists(path), isTrue);
    StoreDatabase.erase(path);
    expect(StoreDatabase.exists(path), isFalse);
  });
}
