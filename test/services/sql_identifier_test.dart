import 'package:aperture/services/sql_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SqlDialect.ansi', () {
    test('double-quotes identifiers and doubles embedded quotes', () {
      expect(SqlDialect.ansi.quoteIdent('weird"name'), '"weird""name"');
      expect(SqlDialect.ansi.qualify('public', 'users'), '"public"."users"');
    });

    test('takes a backslash literally inside a string literal', () {
      expect(SqlDialect.ansi.literal(r'C:\new'), r"'C:\new'");
    });
  });

  group('SqlDialect.mysql', () {
    test('backtick-quotes identifiers and doubles embedded backticks', () {
      expect(SqlDialect.mysql.quoteIdent('weird`name'), '`weird``name`');
      expect(SqlDialect.mysql.qualify('shop', 'users'), '`shop`.`users`');
    });

    test('leaves a double quote alone inside an identifier', () {
      expect(SqlDialect.mysql.quoteIdent('a"b'), '`a"b`');
    });

    // MySQL reads `\n` inside '…' as a newline, so an undoubled backslash
    // would rewrite a Windows path on its way into the column.
    test('doubles backslashes as well as quotes in a string literal', () {
      expect(SqlDialect.mysql.literal(r'C:\new'), r"'C:\\new'");
      expect(SqlDialect.mysql.literal(r"it\'s"), r"'it\\''s'");
      expect(SqlDialect.mysql.literal(null), 'NULL');
    });
  });

  test('rejects NUL bytes in an identifier', () {
    for (final d in SqlDialect.values) {
      expect(() => d.quoteIdent('a\u0000b'), throwsArgumentError);
    }
  });
}
