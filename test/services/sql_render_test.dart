import 'package:aperture/models/cell_edit.dart';
import 'package:aperture/models/db_object.dart';
import 'package:aperture/services/sql_identifier.dart';
import 'package:aperture/services/sql_render.dart';
import 'package:flutter_test/flutter_test.dart';

const _ansi = SqlDialect.ansi;

void _validateAnsi(String snippet, {required ClauseKind kind}) =>
    validateClauseSnippet(snippet, kind: kind, dialect: _ansi);

void main() {
  group('SqlDialect.ansi.literal', () {
    test('null becomes the bare NULL keyword', () {
      expect(_ansi.literal(null), 'NULL');
    });

    test('plain string is single-quoted', () {
      expect(_ansi.literal('Alice'), "'Alice'");
    });

    test('embedded single quote is doubled', () {
      expect(_ansi.literal("O'Brien"), "'O''Brien'");
    });

    test('empty string round-trips as an empty literal', () {
      expect(_ansi.literal(''), "''");
    });

    test('does not escape backslashes or double quotes', () {
      expect(_ansi.literal(r'a\b"c'), '\'a\\b"c\'');
    });
  });

  group('renderAssignment', () {
    test('CellLiteral routes through the dialect literal', () {
      expect(renderAssignment(const CellLiteral('x'), _ansi), "'x'");
      expect(renderAssignment(const CellLiteral(null), _ansi), 'NULL');
    });

    test('CellDefault becomes the bare DEFAULT keyword', () {
      expect(renderAssignment(const CellDefault(), _ansi), 'DEFAULT');
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

  group('validateClauseSnippet — a bare trailing semicolon', () {
    test('a filter ending in ; is rejected', () {
      // SQLite's prepare compiles the first statement and discards the
      // tail without complaint, so `1=1;` silently dropped the LIMIT,
      // OFFSET and ORDER BY that follow it — fetching a whole table into
      // one page. Postgres errors instead, which made it look like engine
      // flakiness.
      expect(
        () => _validateAnsi('1=1;', kind: ClauseKind.filter),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('order by and select list too', () {
      expect(
        () => _validateAnsi('name;', kind: ClauseKind.orderBy),
        throwsA(isA<ClauseSyntaxException>()),
      );
      expect(
        () => _validateAnsi('id;', kind: ClauseKind.selectList),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('a semicolon inside a string literal is still fine', () {
      expect(
        () => _validateAnsi(
          "title = 'a;b'",
          kind: ClauseKind.filter,
        ),
        returnsNormally,
      );
    });

    test('a semicolon inside a comment is still fine', () {
      expect(
        () => _validateAnsi(
          '1=1 /* a;b */',
          kind: ClauseKind.filter,
        ),
        returnsNormally,
      );
    });
  });

  group('validateClauseSnippet', () {
    test('empty filter passes', () {
      expect(
        () => _validateAnsi('', kind: ClauseKind.filter),
        returnsNormally,
      );
    });

    test('whitespace-only filter passes', () {
      expect(
        () => _validateAnsi('   \n\t', kind: ClauseKind.filter),
        returnsNormally,
      );
    });

    test('plain boolean filter passes', () {
      expect(
        () => _validateAnsi('1 = 1', kind: ClauseKind.filter),
        returnsNormally,
      );
    });

    test('filter with stacked DROP is rejected', () {
      expect(
        () => _validateAnsi(
          '1=1; DROP TABLE x',
          kind: ClauseKind.filter,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('filter with trailing semicolon + comment is rejected', () {
      expect(
        () => _validateAnsi('1=1; --', kind: ClauseKind.filter),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('semicolon inside a string literal is allowed', () {
      expect(
        () => _validateAnsi(
          "name = 'a;b;c'",
          kind: ClauseKind.filter,
        ),
        returnsNormally,
      );
    });

    test('semicolon inside a dollar-quoted block is allowed', () {
      expect(
        () => _validateAnsi(
          r"body = $tag$ raw ; text $tag$",
          kind: ClauseKind.filter,
        ),
        returnsNormally,
      );
    });

    test('multi-column order by passes', () {
      expect(
        () => _validateAnsi(
          'name asc, id desc',
          kind: ClauseKind.orderBy,
        ),
        returnsNormally,
      );
    });

    test('order by with stacked statement is rejected', () {
      expect(
        () => _validateAnsi(
          'name; DROP TABLE x',
          kind: ClauseKind.orderBy,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('multi-column select list passes', () {
      expect(
        () => _validateAnsi(
          'id, name, lower(email)',
          kind: ClauseKind.selectList,
        ),
        returnsNormally,
      );
    });

    test('select list with stacked statement is rejected', () {
      expect(
        () => _validateAnsi(
          'id; DROP TABLE x',
          kind: ClauseKind.selectList,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    test('exception message names the clause kind', () {
      try {
        _validateAnsi('1=1; DROP TABLE x', kind: ClauseKind.filter);
        fail('expected ClauseSyntaxException');
      } on ClauseSyntaxException catch (e) {
        expect(e.toString(), contains('filter'));
        expect(e.kind, ClauseKind.filter);
      }
    });
  });

  group('MySQL', () {
    // ANSI sees one statement here — `'a\''` doubles the quote and the
    // string runs on to the final `'`. MySQL reads `\'` as an escape, closes
    // the string after it, and runs the DROP.
    test('the clause gate splits snippets the way MySQL reads them', () {
      const snippet = r"x = 'a\'' ; DROP TABLE t; -- '";
      expect(
        () => validateClauseSnippet(
          snippet,
          kind: ClauseKind.filter,
          dialect: SqlDialect.mysql,
        ),
        throwsA(isA<ClauseSyntaxException>()),
      );
    });

    final table = DbTable(
      oid: 1,
      schema: 'shop',
      name: 'orders',
      kind: DbRelationKind.table,
      dialect: SqlDialect.mysql,
    );
    final policy = EditPolicy(
      rowIdPredicate: (id) => 'WHERE `id` = $id',
      insertOmitsDefaultColumns: false,
      updateDropsDefaultAssignments: false,
    );

    test('edit statements quote with backticks and escape backslashes', () {
      final sql = buildEditStatements(
        table,
        EditBatch(
          updatesByCtid: {
            '7': {'note': const CellLiteral(r'C:\tmp')},
          },
        ),
        policy,
      );
      expect(sql, [
        "UPDATE `shop`.`orders` SET\n  `note` = 'C:\\\\tmp'\nWHERE `id` = 7",
      ]);
    });

    test('an insert with no columns uses the MySQL empty-row form', () {
      final sql = buildEditStatements(
        table,
        EditBatch(inserts: [PendingInsert()]),
        policy,
      );
      expect(sql, ['INSERT INTO `shop`.`orders` () VALUES ()']);
    });
  });
}
