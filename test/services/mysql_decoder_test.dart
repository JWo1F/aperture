import 'dart:convert';
import 'dart:typed_data';

import 'package:aperture/services/mysql_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_dart/mysql_protocol.dart' show MySQLColumnType;

void main() {
  test('integers become int, and BigInt past 2^63', () {
    expect(decodeMysqlValue('42', MySQLColumnType.longType), 42);
    expect(decodeMysqlValue('2024', MySQLColumnType.yearType), 2024);
    expect(
      decodeMysqlValue('18446744073709551615', MySQLColumnType.longLongType),
      BigInt.parse('18446744073709551615'),
    );
  });

  test('DECIMAL keeps its text so no precision is lost', () {
    expect(decodeMysqlValue('0.10', MySQLColumnType.newDecimalType), '0.10');
  });

  test('DOUBLE becomes double', () {
    expect(decodeMysqlValue('1.5', MySQLColumnType.doubleType), 1.5);
  });

  test('JSON decodes to a map, and stays text when it is not JSON', () {
    expect(decodeMysqlValue('{"a": [1]}', MySQLColumnType.jsonType), {
      'a': [1],
    });
    expect(decodeMysqlValue('{oops', MySQLColumnType.jsonType), '{oops');
  });

  test('BIT reads its bytes big-endian', () {
    expect(
      decodeMysqlValue(Uint8List.fromList([1, 2]), MySQLColumnType.bitType),
      258,
    );
  });

  // MariaDB's JSON and any `_bin`-collated TEXT carry the binary flag.
  test('blob bytes that read as text become a string', () {
    final bytes = Uint8List.fromList(utf8.encode('héllo\nworld'));
    expect(decodeMysqlValue(bytes, MySQLColumnType.blobType), 'héllo\nworld');
  });

  test('genuinely binary blob bytes stay bytes', () {
    final bytes = Uint8List.fromList([0, 255, 16]);
    expect(decodeMysqlValue(bytes, MySQLColumnType.blobType), same(bytes));
  });

  test('dates stay as the server printed them', () {
    expect(
      decodeMysqlValue('2024-01-02 03:04:05', MySQLColumnType.dateTimeType),
      '2024-01-02 03:04:05',
    );
  });
}
