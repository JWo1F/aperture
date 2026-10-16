import 'dart:async';
import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/connect_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_dart/exception.dart';

void main() {
  final config = ConnectionConfig(
    id: '1',
    name: 'prod',
    host: 'db.example.com',
    port: 5432,
    database: 'analytics',
    username: 'alice',
    credential: const PasswordCredential('secret'),
  );

  test('SocketException → "Can\'t reach …"', () {
    final f = friendlyConnectError(
      const SocketException('failed'),
      config,
    );
    expect(f.message, contains("Can't reach db.example.com:5432"));
  });

  test('TimeoutException → "… timed out."', () {
    final f = friendlyConnectError(TimeoutException('slow'), config);
    expect(f.message, contains('timed out'));
  });

  test('falls back to the raw toString on unknown types', () {
    final f = friendlyConnectError(StateError('???'), config);
    expect(f.message, contains('???'));
  });

  test('a MySQL access-denied error names the user', () {
    final f = friendlyConnectError(
      const MySQLServerException("Access denied for user 'alice'", 1045),
      config.copyWith(engine: DbEngine.mysql),
    );
    expect(f.message, startsWith('Wrong password for user "alice"'));
  });

  test('a MySQL unknown-database error names the database', () {
    final f = friendlyConnectError(
      const MySQLServerException("Unknown database 'analytics'", 1049),
      config.copyWith(engine: DbEngine.mysql),
    );
    expect(f.message, 'Database "analytics" does not exist on the server.');
  });
}
