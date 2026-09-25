import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cipher'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a keyed file reopens with its key and refuses a wrong one', () {
    final path = '${dir.path}/sealed.sqlite';
    sqlite3.open(path)
      ..execute("PRAGMA cipher = 'sqlcipher'")
      ..execute('PRAGMA legacy = 4')
      ..execute("PRAGMA key = 'right'")
      ..execute('CREATE TABLE t (v TEXT)')
      ..execute("INSERT INTO t VALUES ('secret')")
      ..close();

    expect(
      File(path).readAsStringSync(encoding: latin1),
      isNot(contains('secret')),
    );

    final ok = sqlite3.open(path)
      ..execute("PRAGMA cipher = 'sqlcipher'")
      ..execute('PRAGMA legacy = 4')
      ..execute("PRAGMA key = 'right'");
    expect(ok.select('SELECT v FROM t').single['v'], 'secret');
    ok.close();

    final bad = sqlite3.open(path)
      ..execute("PRAGMA cipher = 'sqlcipher'")
      ..execute('PRAGMA legacy = 4')
      ..execute("PRAGMA key = 'wrong'");
    expect(
      () => bad.select('SELECT count(*) FROM sqlite_master'),
      throwsA(isA<SqliteException>()),
    );
    bad.close();
  });

  test('an unkeyed file stays plain SQLite', () {
    final path = '${dir.path}/plain.sqlite';
    sqlite3.open(path)
      ..execute('CREATE TABLE t (v TEXT)')
      ..execute("INSERT INTO t VALUES ('visible')")
      ..close();
    expect(
      File(path).readAsStringSync(encoding: latin1),
      contains('SQLite format 3'),
    );
    final db = sqlite3.open(path);
    expect(db.select('SELECT v FROM t').single['v'], 'visible');
    db.close();
  });
}
