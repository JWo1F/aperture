import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/postgres_table_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final table = DbTable(
    oid: 1,
    schema: 'public',
    name: 'events',
    kind: DbRelationKind.table,
  );

  EditBatch updates(Map<String, Map<String, CellEditValue>> u) =>
      EditBatch(updatesByCtid: u);

  group('buildEditStatements', () {
    test('renders one UPDATE per ctid with quoted columns', () {
      final stmts = buildPostgresEditStatements(
        table,
        updates({
          '(0,5)': {
            'name': const CellLiteral('Alice'),
            'count': const CellLiteral('42'),
          },
        }),
      );
      expect(stmts, hasLength(1));
      expect(stmts.first, contains('UPDATE "public"."events" SET'));
      expect(stmts.first, contains('"name" = \'Alice\''));
      expect(stmts.first, contains('"count" = \'42\''));
      expect(stmts.first, contains("WHERE ctid = '(0,5)'::tid"));
    });

    test('renders NULL for a null literal', () {
      final stmts = buildPostgresEditStatements(
        table,
        updates({
          '(0,1)': {'note': const CellLiteral(null)},
        }),
      );
      expect(stmts.first, contains('"note" = NULL'));
    });

    test('renders DEFAULT for CellDefault', () {
      final stmts = buildPostgresEditStatements(
        table,
        updates({
          '(0,1)': {'created_at': const CellDefault()},
        }),
      );
      expect(stmts.first, contains('"created_at" = DEFAULT'));
    });

    test('doubles single quotes inside the literal', () {
      final stmts = buildPostgresEditStatements(
        table,
        updates({
          '(0,1)': {'name': const CellLiteral("O'Brien")},
        }),
      );
      expect(stmts.first, contains("'O''Brien'"));
    });

    test('escapes embedded quotes in column names', () {
      final stmts = buildPostgresEditStatements(
        table,
        updates({
          '(0,1)': {'weird"col': const CellLiteral('x')},
        }),
      );
      expect(stmts.first, contains('"weird""col" = '));
    });

    test('one statement per ctid', () {
      final stmts = buildPostgresEditStatements(
        table,
        updates({
          '(0,1)': {'a': const CellLiteral('1')},
          '(0,2)': {'a': const CellLiteral('2')},
        }),
      );
      expect(stmts, hasLength(2));
    });

    test('renders one DELETE per ctid', () {
      final stmts = buildPostgresEditStatements(
        table,
        EditBatch(deleteCtids: ['(0,3)', '(0,4)']),
      );
      expect(stmts, hasLength(2));
      expect(stmts.first, contains('DELETE FROM "public"."events"'));
      expect(stmts.first, contains("ctid = '(0,3)'::tid"));
      expect(stmts.last, contains("ctid = '(0,4)'::tid"));
    });

    test('renders INSERT with column list and DEFAULT for PK', () {
      final stmts = buildPostgresEditStatements(
        table,
        EditBatch(
          inserts: [
            PendingInsert(
              values: {
                'id': const CellDefault(),
                'name': const CellLiteral('Alice'),
                'note': const CellLiteral(null),
              },
            ),
          ],
        ),
      );
      expect(stmts, hasLength(1));
      expect(stmts.first, contains('INSERT INTO "public"."events"'));
      expect(stmts.first, contains('("id", "name", "note")'));
      expect(stmts.first, contains('(DEFAULT, \'Alice\', NULL)'));
    });

    test('empty INSERT falls back to DEFAULT VALUES', () {
      final stmts = buildPostgresEditStatements(
        table,
        EditBatch(inserts: [PendingInsert()]),
      );
      expect(stmts.single, contains('DEFAULT VALUES'));
    });

    test('orders updates → deletes → inserts', () {
      final stmts = buildPostgresEditStatements(
        table,
        EditBatch(
          updatesByCtid: {
            '(0,1)': {'a': const CellLiteral('u')},
          },
          deleteCtids: ['(0,2)'],
          inserts: [
            PendingInsert(values: {'a': const CellLiteral('i')}),
          ],
        ),
      );
      expect(stmts, hasLength(3));
      expect(stmts[0], startsWith('UPDATE'));
      expect(stmts[1], startsWith('DELETE FROM'));
      expect(stmts[2], startsWith('INSERT INTO'));
    });
  });
}
