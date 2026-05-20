import 'package:dbv/models/cell_edit.dart';
import 'package:dbv/models/db_object.dart';
import 'package:dbv/services/table_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final table = DbTable(
    oid: 1,
    schema: 'public',
    name: 'events',
    kind: DbRelationKind.table,
  );

  group('buildEditStatements', () {
    test('renders one UPDATE per ctid with quoted columns', () {
      final stmts = buildEditStatements(table, {
        '(0,5)': {
          'name': const CellLiteral('Alice'),
          'count': const CellLiteral('42'),
        },
      });
      expect(stmts, hasLength(1));
      expect(stmts.first, contains('UPDATE "public"."events" SET'));
      expect(stmts.first, contains('"name" = \'Alice\''));
      expect(stmts.first, contains('"count" = \'42\''));
      expect(stmts.first, contains("WHERE ctid = '(0,5)'::tid"));
    });

    test('renders NULL for a null literal', () {
      final stmts = buildEditStatements(table, {
        '(0,1)': {'note': const CellLiteral(null)},
      });
      expect(stmts.first, contains('"note" = NULL'));
    });

    test('renders DEFAULT for CellDefault', () {
      final stmts = buildEditStatements(table, {
        '(0,1)': {'created_at': const CellDefault()},
      });
      expect(stmts.first, contains('"created_at" = DEFAULT'));
    });

    test("doubles single quotes inside the literal", () {
      final stmts = buildEditStatements(table, {
        '(0,1)': {'name': const CellLiteral("O'Brien")},
      });
      expect(stmts.first, contains("'O''Brien'"));
    });

    test('escapes embedded quotes in column names', () {
      final stmts = buildEditStatements(table, {
        '(0,1)': {'weird"col': const CellLiteral('x')},
      });
      expect(stmts.first, contains('"weird""col" = '));
    });

    test('one statement per ctid', () {
      final stmts = buildEditStatements(table, {
        '(0,1)': {'a': const CellLiteral('1')},
        '(0,2)': {'a': const CellLiteral('2')},
      });
      expect(stmts, hasLength(2));
    });
  });
}
