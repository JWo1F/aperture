import 'package:dbv/services/safe_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyDefaultLimit', () {
    test('appends LIMIT to a bare SELECT', () {
      final s = applyDefaultLimit('SELECT * FROM events', limit: 10);
      expect(s.appliedLimit, isTrue);
      expect(s.sql, 'SELECT * FROM events LIMIT 10');
    });

    test('strips a trailing semicolon before LIMIT', () {
      final s = applyDefaultLimit('SELECT 1;', limit: 5);
      expect(s.appliedLimit, isTrue);
      expect(s.sql, 'SELECT 1 LIMIT 5');
    });

    test('leaves an existing LIMIT alone', () {
      final s = applyDefaultLimit('SELECT * FROM t LIMIT 3', limit: 100);
      expect(s.appliedLimit, isFalse);
      expect(s.sql, 'SELECT * FROM t LIMIT 3');
    });

    test('case-insensitive LIMIT detection', () {
      final s = applyDefaultLimit('select * from t limit 1', limit: 100);
      expect(s.appliedLimit, isFalse);
    });

    test('does not touch INSERT / UPDATE / DELETE', () {
      expect(
        applyDefaultLimit('INSERT INTO t VALUES (1)', limit: 10).appliedLimit,
        isFalse,
      );
      expect(
        applyDefaultLimit('UPDATE t SET x = 1', limit: 10).appliedLimit,
        isFalse,
      );
      expect(
        applyDefaultLimit('DELETE FROM t', limit: 10).appliedLimit,
        isFalse,
      );
    });

    test('does not touch DDL', () {
      expect(
        applyDefaultLimit('CREATE TABLE t (id int)', limit: 10).appliedLimit,
        isFalse,
      );
      expect(
        applyDefaultLimit('DROP TABLE t', limit: 10).appliedLimit,
        isFalse,
      );
    });

    test('does not touch WITH … INSERT or DO blocks', () {
      expect(
        applyDefaultLimit(
          'WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x',
          limit: 10,
        ).appliedLimit,
        isFalse,
      );
    });

    test('honours leading comments and whitespace', () {
      final s = applyDefaultLimit(
        '-- friendly heading\n   SELECT 1',
        limit: 5,
      );
      expect(s.appliedLimit, isTrue);
      expect(s.sql.endsWith('LIMIT 5'), isTrue);
    });

    test('limit <= 0 is a no-op', () {
      final s = applyDefaultLimit('SELECT 1', limit: 0);
      expect(s.appliedLimit, isFalse);
      expect(s.sql, 'SELECT 1');
    });
  });
}
