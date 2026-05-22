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

  group('validateClauseSnippet', () {
    test('empty filter passes', () {
      expect(
        () => validateClauseSnippet('', kind: ClauseKind.filter),
        returnsNormally,
      );
    });

    test('whitespace-only filter passes', () {
      expect(
        () => validateClauseSnippet('   \n\t', kind: ClauseKind.filter),
        returnsNormally,
      );
    });

    test('plain boolean filter passes', () {
      expect(
        () => validateClauseSnippet('1 = 1', kind: ClauseKind.filter),
        returnsNormally,
      );
    });

    test('filter with stacked DROP is rejected', () {
      expect(
        () => validateClauseSnippet(
          '1=1; DROP TABLE x',
          kind: ClauseKind.filter,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('filter with trailing semicolon + comment is rejected', () {
      expect(
        () => validateClauseSnippet('1=1; --', kind: ClauseKind.filter),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('semicolon inside a string literal is allowed', () {
      expect(
        () => validateClauseSnippet(
          "name = 'a;b;c'",
          kind: ClauseKind.filter,
        ),
        returnsNormally,
      );
    });

    test('semicolon inside a dollar-quoted block is allowed', () {
      expect(
        () => validateClauseSnippet(
          r"body = $tag$ raw ; text $tag$",
          kind: ClauseKind.filter,
        ),
        returnsNormally,
      );
    });

    test('multi-column order by passes', () {
      expect(
        () => validateClauseSnippet(
          'name asc, id desc',
          kind: ClauseKind.orderBy,
        ),
        returnsNormally,
      );
    });

    test('order by with stacked statement is rejected', () {
      expect(
        () => validateClauseSnippet(
          'name; DROP TABLE x',
          kind: ClauseKind.orderBy,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('multi-column select list passes', () {
      expect(
        () => validateClauseSnippet(
          'id, name, lower(email)',
          kind: ClauseKind.selectList,
        ),
        returnsNormally,
      );
    });

    test('select list with stacked statement is rejected', () {
      expect(
        () => validateClauseSnippet(
          'id; DROP TABLE x',
          kind: ClauseKind.selectList,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('exception message names the clause kind', () {
      try {
        validateClauseSnippet('1=1; DROP TABLE x', kind: ClauseKind.filter);
        fail('expected ClauseSyntaxException');
      } on ClauseSyntaxException catch (e) {
        expect(e.toString(), contains('filter'));
        expect(e.kind, ClauseKind.filter);
      }
    });
  });
}
