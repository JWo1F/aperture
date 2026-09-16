import 'package:aperture/services/sql_statements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _statementKindTests();
  group('parseSqlStatements — comment-only tails', () {
    test('a trailing line comment is not a statement', () {
      // The run-all loop executes each entry, and SQLite's prepare()
      // throws "Must contain an SQL statement" on a bare comment — so a
      // script ending `-- done` reported itself as failed after it had
      // actually succeeded.
      final stmts = parseSqlStatements('SELECT 1; -- done');
      expect(stmts, hasLength(1));
      expect(stmts.single.text, 'SELECT 1;');
    });

    test('a trailing block comment is not a statement', () {
      final stmts = parseSqlStatements('SELECT 1;\n/* done */\n');
      expect(stmts, hasLength(1));
    });

    test('a leading comment stays attached to its statement', () {
      final stmts = parseSqlStatements('-- why\nSELECT 1;');
      expect(stmts, hasLength(1));
      expect(stmts.single.text, '-- why\nSELECT 1;');
    });

    test('a script of nothing but comments yields nothing', () {
      expect(parseSqlStatements('-- a\n/* b */\n'), isEmpty);
    });

    test('a comment between statements does not split them apart', () {
      final stmts = parseSqlStatements('SELECT 1; -- mid\nSELECT 2;');
      expect(stmts, hasLength(2));
      // The comment rides along with the statement it precedes, which is
      // where the user put it.
      expect(stmts.last.text, contains('SELECT 2;'));
    });

    test('a real trailing statement with no semicolon survives', () {
      final stmts = parseSqlStatements('SELECT 1; SELECT 2');
      expect(stmts, hasLength(2));
      expect(stmts.last.text, 'SELECT 2');
    });

    test('a semicolon inside a trailing comment is not a separator', () {
      final stmts = parseSqlStatements('SELECT 1 -- a; b');
      expect(stmts, hasLength(1));
      expect(stmts.single.text, 'SELECT 1 -- a; b');
    });
  });

  group('parseSqlStatements', () {
    test('splits on top-level semicolons', () {
      final stmts = parseSqlStatements('SELECT 1; SELECT 2');
      expect(stmts, hasLength(2));
      expect(stmts[0].text, 'SELECT 1;');
      expect(stmts[1].text, 'SELECT 2');
    });

    test('drops empty fragments', () {
      final stmts = parseSqlStatements(';;SELECT 1;;');
      expect(stmts, hasLength(1));
      expect(stmts[0].text, 'SELECT 1;');
    });

    test('keeps semicolons inside single-quoted strings', () {
      final stmts =
          parseSqlStatements("SELECT 'a;b;c'; SELECT 'd'");
      expect(stmts, hasLength(2));
      expect(stmts[0].text, "SELECT 'a;b;c';");
      expect(stmts[1].text, "SELECT 'd'");
    });

    test("doubled '' inside a string does not close it", () {
      final stmts =
          parseSqlStatements("SELECT 'O''Brien;Smith'; SELECT 2");
      expect(stmts, hasLength(2));
      expect(stmts[0].text, "SELECT 'O''Brien;Smith';");
      expect(stmts[1].text, 'SELECT 2');
    });

    test('keeps semicolons inside dollar-quoted bodies', () {
      const sql = r'''
CREATE FUNCTION f() RETURNS void AS $$
BEGIN
  SELECT 1; SELECT 2;
END;
$$ LANGUAGE plpgsql;
SELECT 99;
''';
      final stmts = parseSqlStatements(sql);
      expect(stmts, hasLength(2));
      expect(stmts[0].text, contains(r'$$'));
      expect(stmts[0].text, contains('BEGIN'));
      expect(stmts[0].text, contains('SELECT 1; SELECT 2;'));
      expect(stmts[1].text, 'SELECT 99;');
    });

    test('handles tagged dollar quotes', () {
      const sql = r'''
DO $body$
  SELECT $inner$ raw ; text $inner$;
$body$;
SELECT 1;
''';
      final stmts = parseSqlStatements(sql);
      expect(stmts, hasLength(2));
      expect(stmts[0].text, contains(r'$body$'));
      expect(stmts[1].text, 'SELECT 1;');
    });

    test('handles backslash escapes inside E-strings', () {
      final stmts =
          parseSqlStatements(r"SELECT E'a\';b'; SELECT 2");
      expect(stmts, hasLength(2));
      expect(stmts[0].text, r"SELECT E'a\';b';");
      expect(stmts[1].text, 'SELECT 2');
    });

    test('does not mis-identify identifier-prefixed E', () {
      // `error` is a regular identifier — should NOT be parsed as E-string.
      final stmts =
          parseSqlStatements("SELECT error;SELECT 2");
      expect(stmts, hasLength(2));
    });

    test('a line comment does not introduce a fake separator', () {
      const sql = '''
SELECT 1; -- inline; not a separator
SELECT 2
''';
      final stmts = parseSqlStatements(sql);
      // The trailing comment-line plus the next SELECT come back as one
      // statement. The important contract is that the `;` inside the
      // comment is NOT treated as a separator (otherwise we'd get 3).
      expect(stmts, hasLength(2));
      expect(stmts[1].text, contains('SELECT 2'));
    });

    test('treats block comments as transparent', () {
      const sql = '''
SELECT /* ;;;; */ 1;
SELECT 2
''';
      final stmts = parseSqlStatements(sql);
      expect(stmts, hasLength(2));
      expect(stmts[0].text, contains('SELECT /* ;;;; */ 1;'));
    });

    test('honours doubled "" inside quoted identifiers', () {
      final stmts =
          parseSqlStatements('SELECT "weird""name"; SELECT 1');
      expect(stmts, hasLength(2));
      expect(stmts[0].text, 'SELECT "weird""name";');
    });
  });

  group('statementAtOffset', () {
    test('finds the statement at a given offset', () {
      const sql = 'SELECT 1; SELECT 2;';
      final stmts = parseSqlStatements(sql);
      expect(statementAtOffset(stmts, 0)?.text, 'SELECT 1;');
      expect(statementAtOffset(stmts, 10)?.text, 'SELECT 2;');
    });

    test('the caret just past a semicolon is still in that statement', () {
      const sql = 'SELECT 1;\n\nSELECT 2';
      final stmts = parseSqlStatements(sql);
      expect(statementAtOffset(stmts, 9)?.text, 'SELECT 1;');
    });

    test('the whitespace gap between statements belongs to neither', () {
      const sql = 'SELECT 1;\n\nSELECT 2';
      final stmts = parseSqlStatements(sql);
      // Offsets 10 and 11 are the two newlines.
      expect(statementAtOffset(stmts, 10), isNull);
    });

    test('abutting statements do not both claim the boundary', () {
      // `SELECT 1;SELECT 2` — a caret at offset 9 sits at the start of the
      // second statement. Run-statement used to send the first one.
      const sql = 'SELECT 1;SELECT 2';
      final stmts = parseSqlStatements(sql);
      expect(stmts, hasLength(2));
      expect(statementAtOffset(stmts, 9)?.text, 'SELECT 2');
      expect(statementAtOffset(stmts, 8)?.text, 'SELECT 1;');
    });

    test('an offset past the end belongs to the last statement', () {
      const sql = 'SELECT 1';
      final stmts = parseSqlStatements(sql);
      expect(statementAtOffset(stmts, 8)?.text, 'SELECT 1');
    });
  });
}

void _statementKindTests() {
  group('statementKind', () {
    test('reports the leading keyword uppercased', () {
      expect(statementKind('select 1'), 'SELECT');
      expect(statementKind('INSERT INTO t VALUES (1)'), 'INSERT');
      expect(statementKind('  update t set a = 1'), 'UPDATE');
    });

    test('skips leading line and block comments', () {
      expect(statementKind('-- pick everyone\nSELECT * FROM users'), 'SELECT');
      expect(statementKind('/* header */ delete from t'), 'DELETE');
      expect(statementKind('/* a */\n-- b\n  CREATE TABLE t ()'), 'CREATE');
    });

    test('sees through a leading open paren', () {
      expect(statementKind('(SELECT 1) UNION (SELECT 2)'), 'SELECT');
    });

    test('reports WITH for a CTE rather than resolving the inner verb', () {
      expect(statementKind('WITH x AS (SELECT 1) SELECT * FROM x'), 'WITH');
    });

    test('returns null when nothing executable is present', () {
      expect(statementKind(''), isNull);
      expect(statementKind('   \n\t '), isNull);
      expect(statementKind('-- only a comment'), isNull);
      expect(statementKind('/* only a block */'), isNull);
    });

    test('stops at the first non-identifier character', () {
      expect(statementKind('SELECT*FROM t'), 'SELECT');
      expect(statementKind('vacuum;'), 'VACUUM');
    });
  });
}
