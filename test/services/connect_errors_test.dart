import 'dart:async';
import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/connect_errors.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
