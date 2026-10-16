import 'dart:io';

import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/models/connection_config.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/mysql_service.dart';
import 'package:aperture/services/sql_render.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs against a live server, so it is skipped unless
/// `APERTURE_MYSQL_PORT` names one on localhost. The user is `root`, the
/// password `APERTURE_MYSQL_PASSWORD` (default `secret`), and the database
/// `aperture_test` is dropped and recreated. For example:
///
///     docker run -d -p 33306:3306 -e MYSQL_ROOT_PASSWORD=secret mysql:8.4
///     APERTURE_MYSQL_PORT=33306 flutter test test/services/mysql_service_live_test.dart
void main() {
  final port = int.tryParse(Platform.environment['APERTURE_MYSQL_PORT'] ?? '');
  final skip = port == null ? 'APERTURE_MYSQL_PORT is not set' : null;
  final password = Platform.environment['APERTURE_MYSQL_PASSWORD'] ?? 'secret';

  ConnectionConfig config(String database) => ConnectionConfig(
    id: 'live',
    name: 'live',
    engine: DbEngine.mysql,
    host: '127.0.0.1',
    port: port ?? 0,
    database: database,
    username: 'root',
    runtimePassword: password,
  );

  late MysqlService svc;

  setUpAll(() async {
    if (port == null) return;
    final admin = MysqlService(config('mysql'));
    await admin.connect();
    await admin.execute('DROP DATABASE IF EXISTS aperture_test');
    await admin.execute('CREATE DATABASE aperture_test');
    await admin.close();
    svc = MysqlService(config('aperture_test'));
    await svc.connect();
    for (final sql in [
      'CREATE TABLE customers (id INT PRIMARY KEY AUTO_INCREMENT, '
          "name VARCHAR(50) NOT NULL COMMENT 'display name', "
          'UNIQUE KEY uq_name (name))',
      'CREATE TABLE orders (id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT, '
          'customer_id INT NOT NULL, total DECIMAL(10,2), note TEXT, '
          'meta JSON, placed DATETIME(3), flags BIT(3), '
          'KEY ix_customer (customer_id), '
          'CONSTRAINT fk_customer FOREIGN KEY (customer_id) '
          'REFERENCES customers (id) ON DELETE CASCADE)',
      'CREATE TABLE logbook (line TEXT)',
      'CREATE VIEW big_orders AS SELECT * FROM orders WHERE total > 100',
      "INSERT INTO customers (name) VALUES ('Ada'), ('Brian')",
      'INSERT INTO orders (customer_id, total, note, meta, placed, flags) '
          "VALUES (1, 150.50, 'first', '{\"a\": [1, 2]}', "
          "'2024-01-02 03:04:05.123', b'101'), "
          "(2, 20.00, NULL, NULL, NULL, NULL)",
      "INSERT INTO logbook VALUES ('x')",
      'CREATE FUNCTION twice(n INT) RETURNS INT DETERMINISTIC RETURN n * 2',
      'CREATE PROCEDURE touch(IN who INT, OUT done INT) BEGIN '
          'SELECT who; SET done = 1; END',
      'CREATE FUNCTION boom(n INT) RETURNS INT DETERMINISTIC BEGIN '
          "IF n = 2 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'boom'; "
          'END IF; RETURN n; END',
    ]) {
      await svc.execute(sql);
    }
  });

  tearDownAll(() async {
    if (port == null) return;
    await svc.close();
    final admin = MysqlService(config('mysql'));
    await admin.connect();
    await admin.execute('DROP DATABASE aperture_test');
    await admin.close();
  });

  DbTable table(String name, {bool view = false}) => DbTable(
    oid: 0,
    schema: 'aperture_test',
    name: name,
    kind: view ? DbRelationKind.view : DbRelationKind.table,
    dialect: DbEngine.mysql.dialect,
  );

  group('MysqlService (live)', skip: skip, () {
    test('reads the catalog of the connected database', () async {
      final intro = svc.introspector;
      final schemas = await intro.loadSchemas();
      expect(schemas.single.name, 'aperture_test');
      final byName = {for (final t in schemas.single.tables) t.name: t};
      expect(byName.keys, ['big_orders', 'customers', 'logbook', 'orders']);
      expect(byName['big_orders']!.kind, DbRelationKind.view);

      final columns = await intro.loadAllColumns();
      final customers = columns[byName['customers']!.oid]!;
      expect(customers.first.isPrimaryKey, isTrue);
      expect(customers.first.hasDefault, isTrue);
      expect(customers[1].comment, 'display name');

      final fks = (await intro.loadAllForeignKeys())[byName['orders']!.oid]!;
      expect(fks.single.localColumns, ['customer_id']);
      expect(fks.single.refTableOid, byName['customers']!.oid);
      expect(fks.single.onDelete, 'CASCADE');

      final keys = (await intro.loadAllKeys())[byName['customers']!.oid]!;
      expect(keys.map((k) => k.kind), [DbKeyKind.primary, DbKeyKind.unique]);

      final indexes = (await intro.loadAllIndexes())[byName['orders']!.oid]!;
      expect(
        indexes.map((i) => i.def),
        contains(
          'CREATE INDEX `ix_customer` ON `aperture_test`.`orders` '
          '(`customer_id`)',
        ),
      );

      final routines = await intro.loadAllRoutines();
      expect(routines.map((r) => r.name), ['boom', 'touch', 'twice']);
      // MariaDB keeps the display width MySQL 8 dropped: `int(11)`.
      expect(
        routines[1].arguments,
        matches(r'^IN who int(\(11\))?, OUT done int(\(11\))?$'),
      );
      expect(routines.last.result, startsWith('int'));
      expect(
        await intro.loadRoutineDdl(routines[1]),
        allOf(startsWith('DELIMITER \$\$\nCREATE'), endsWith('DELIMITER ;\n')),
      );
    });

    test('decodes values by column type', () async {
      final r = await svc.runQuery(
        'SELECT id, total, meta, placed, flags, note FROM orders ORDER BY id',
      );
      expect(r.isError, isFalse, reason: r.error);
      // MariaDB's JSON is a LONGTEXT, so it stays the text it is there.
      final json = r.rows.first[2];
      expect(
        json,
        anyOf(
          equals({
            'a': [1, 2],
          }),
          equals('{"a": [1, 2]}'),
        ),
      );
      expect(r.rows.first..removeAt(2), [
        1,
        '150.50',
        '2024-01-02 03:04:05.123',
        5,
        'first',
      ]);
    });

    test('pages a table with key identities and a view without', () async {
      final page = await svc.fetchTablePage(
        table('orders'),
        limit: 10,
        offset: 0,
        orderBy: 'id',
      );
      expect(page.isError, isFalse, reason: page.error);
      expect(page.columns.first, 'id');
      expect(page.rowIds, hasLength(2));

      final view = await svc.fetchTablePage(
        table('big_orders', view: true),
        limit: 10,
        offset: 0,
      );
      expect(view.rowIds, isNull);

      final keyless = await svc.fetchTablePage(
        table('logbook'),
        limit: 10,
        offset: 0,
      );
      expect(keyless.rowIds, isNull);
      expect(await svc.countRows(table('orders'), filter: 'total > 100'), 1);
    });

    test('rejects a clause snippet MySQL would run as two statements', () {
      expect(
        () => svc.fetchTablePage(
          table('orders'),
          limit: 1,
          offset: 0,
          filter: r"note = 'a\'' ; DROP TABLE orders; -- '",
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('applies edits by primary key, unchanged values included', () async {
      final page = await svc.fetchTablePage(
        table('customers'),
        limit: 10,
        offset: 0,
        orderBy: 'id',
      );
      final ada = page.rowIds![0];
      final brian = page.rowIds![1];
      final result = await svc.applyTableEdits(
        table('customers'),
        EditBatch(
          updatesByCtid: {
            ada: {'name': const CellLiteral('Ada')},
            brian: {'name': const CellLiteral(r'Bri\an')},
          },
          inserts: [
            PendingInsert(
              values: {
                'id': const CellDefault(),
                'name': const CellLiteral("O'Hara"),
              },
            ),
          ],
        ),
      );
      expect(result.ok, isTrue, reason: result.error);
      final names = await svc.runQuery(
        'SELECT name FROM customers ORDER BY id',
      );
      expect(names.rows.map((r) => r.single), ['Ada', r'Bri\an', "O'Hara"]);
    });

    test('a stale key rolls the whole batch back', () async {
      final result = await svc.applyTableEdits(
        table('customers'),
        EditBatch(
          updatesByCtid: {
            '[["id","1"]]': {'name': const CellLiteral('Changed')},
            '[["id","999"]]': {'name': const CellLiteral('Ghost')},
          },
        ),
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('Reload and retry'));
      final ada = await svc.runQuery('SELECT name FROM customers WHERE id = 1');
      expect(ada.rows.single.single, 'Ada');
    });

    test('shows CREATE TABLE as the DDL', () async {
      expect(
        await svc.loadTableDdl(table('customers')),
        contains('CREATE TABLE `customers`'),
      );
    });

    test('queues commands sent at once on the one connection', () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) svc.runQuery('SELECT $i AS n'),
      ]);
      expect([for (final r in results) r.rows.single.single], [0, 1, 2, 3, 4]);
      await svc.ping();
    });

    test('reports a server error by its message', () async {
      final r = await svc.runQuery('SELECT nope FROM orders');
      expect(r.error, startsWith("Unknown column 'nope'"));
    });

    // The server can end a statement with an error after rows have started;
    // the vendored driver reports it instead of dropping the socket.
    test('an error after the first row keeps the session', () async {
      final r = await svc.runQuery(
        'SELECT n, boom(n) AS v '
        'FROM (SELECT 1 AS n UNION ALL SELECT 2) t ORDER BY n',
      );
      expect(r.error, 'boom');
      expect((await svc.runQuery('SELECT 1')).rows.single.single, 1);
    });

    // MariaDB answers a kill with an error packet where the next row would
    // be, MySQL only once rows are streaming.
    test('cancels a running statement and keeps the session', () async {
      final running = svc.runQuery('SELECT SLEEP(10)');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();
      await svc.cancelCurrent();
      await running;
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect((await svc.runQuery('SELECT 1')).rows.single.single, 1);
    });
  });
}
