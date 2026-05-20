import 'package:dbv/models/db_catalog.dart';
import 'package:dbv/models/db_object.dart';
import 'package:dbv/services/sql_complete.dart';
import 'package:flutter_test/flutter_test.dart';

DbTable _t(int oid, String schema, String name) =>
    DbTable(oid: oid, schema: schema, name: name, kind: DbRelationKind.table);

DatabaseCatalog _catalog(List<DbTable> tables) {
  final byOid = {for (final t in tables) t.oid: t};
  return DatabaseCatalog.empty.copyWith(
    schemas: const [],
    relationsByOid: byOid,
    phases: {CatalogPhase.schemas},
  );
}

void main() {
  group('parseScope', () {
    test('picks up FROM <table>', () {
      final cat = _catalog([_t(1, 'public', 'users')]);
      final scope = parseScope('SELECT * FROM users WHERE id = 1', cat);
      expect(scope.tables.map((t) => t.name), ['users']);
      expect(scope.aliases.keys, contains('users'));
    });

    test('picks up FROM schema.table', () {
      final cat = _catalog([_t(2, 'app', 'orders')]);
      final scope = parseScope('SELECT * FROM app.orders', cat);
      expect(scope.tables.single.qualifiedKey, 'app.orders');
    });

    test('captures alias and ignores trailing clause keywords', () {
      final cat = _catalog([_t(1, 'public', 'users')]);
      final scope =
          parseScope('SELECT u.id FROM users u WHERE u.active', cat);
      expect(scope.aliases.containsKey('u'), isTrue);
      expect(scope.aliases.containsKey('where'), isFalse);
    });

    test('captures both sides of a JOIN', () {
      final cat = _catalog([
        _t(1, 'public', 'users'),
        _t(2, 'public', 'orders'),
      ]);
      final scope = parseScope(
        'SELECT * FROM users JOIN orders ON users.id = orders.user_id',
        cat,
      );
      expect(scope.tables.map((t) => t.name), ['users', 'orders']);
    });

    test('unknown table is skipped', () {
      final cat = _catalog([_t(1, 'public', 'users')]);
      final scope = parseScope('SELECT * FROM nope', cat);
      expect(scope.tables, isEmpty);
    });
  });

  group('previousWord', () {
    test('returns lowercased word immediately before tokenStart', () {
      expect(previousWord('SELECT * FROM u', 14), 'from');
      expect(previousWord('select * from u', 14), 'from');
    });

    test('returns empty when nothing precedes the token', () {
      expect(previousWord('users', 0), '');
    });

    test('skips whitespace between token and prior word', () {
      expect(previousWord('JOIN    orders', 8), 'join');
    });
  });
}
