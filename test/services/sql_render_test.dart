import 'package:dbv/models/cell_edit.dart';
import 'package:dbv/services/sql_render.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('literalSql', () {
    test('null becomes the bare NULL keyword', () {
      expect(literalSql(null), 'NULL');
    });

    test('plain string is single-quoted', () {
      expect(literalSql('Alice'), "'Alice'");
    });

    test('embedded single quote is doubled', () {
      expect(literalSql("O'Brien"), "'O''Brien'");
    });

    test('empty string round-trips as an empty literal', () {
      expect(literalSql(''), "''");
    });

    test('does not escape backslashes or double quotes', () {
      expect(literalSql(r'a\b"c'), '\'a\\b"c\'');
    });
  });

  group('renderAssignment', () {
    test('CellLiteral routes through literalSql', () {
      expect(renderAssignment(const CellLiteral('x')), "'x'");
      expect(renderAssignment(const CellLiteral(null)), 'NULL');
    });

    test('CellDefault becomes the bare DEFAULT keyword', () {
      expect(renderAssignment(const CellDefault()), 'DEFAULT');
    });
  });

  group('whereClause', () {
    test('empty filter produces no clause', () {
      expect(whereClause(''), '');
    });

    test('whitespace-only filter produces no clause', () {
      expect(whereClause('   '), '');
    });

    test('non-empty filter is prefixed with a leading space and WHERE', () {
      expect(whereClause('a = 1'), ' WHERE a = 1');
    });

    test('trims surrounding whitespace before emitting the clause', () {
      expect(whereClause('  a = 1  '), ' WHERE a = 1');
    });
  });

  group('orderClause', () {
    test('empty input produces no clause', () {
      expect(orderClause(''), '');
      expect(orderClause('   '), '');
    });

    test('non-empty input is prefixed with a leading space and ORDER BY', () {
      expect(orderClause('a DESC'), ' ORDER BY a DESC');
    });
  });
}
