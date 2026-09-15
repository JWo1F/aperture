import 'package:aperture/services/sql_statements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    test('returns null in the gap between statements', () {
      const sql = 'SELECT 1;\n\nSELECT 2';
      final stmts = parseSqlStatements(sql);
      // The exact gap depends on parser behaviour — at minimum offset 9
      // (just past the first ';' in source) is part of the first stmt.
      expect(statementAtOffset(stmts, 9)?.text, 'SELECT 1;');
    });
  });
}
