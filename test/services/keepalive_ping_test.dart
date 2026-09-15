import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('DbService.ping', () {
    late Directory tmp;
    late SqliteService svc;
    late List<String> logged;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aperture_ping_test');
      final dbPath = '${tmp.path}/ping.db';
      sqlite3.open(dbPath)
        ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY);')
        ..dispose();

      logged = <String>[];
      svc = SqliteService(
        ConnectionConfig(
          id: 'p',
          name: 'ping',
          engine: DbEngine.sqlite,
          filePath: dbPath,
        ),
        onQueryRun:
            ({
              required sql,
              required elapsed,
              required affectedRows,
              required error,
            }) => logged.add(sql),
      );
      await svc.connect();
    });

    tearDown(() async {
      await svc.close();
      await tmp.delete(recursive: true);
    });

    test('a health probe stays out of the activity log', () async {
      await svc.ping();
      await svc.ping();

      // The keepalive fires every 30s for as long as a connection is open.
      // Logging it would evict the user's real query history from the
      // event log's ring buffer within a few hours.
      expect(logged, isEmpty);
    });

    test('a user query still reaches the activity log', () async {
      await svc.runQuery('SELECT 1');
      expect(logged, hasLength(1));
    });

    test('a probe on a closed connection throws', () async {
      await svc.close();
      expect(svc.ping(), throwsA(isA<StateError>()));
    });
  });
}
