import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';

import '../models/connection_config.dart';

/// Turns the wire-level exception thrown by `Connection.open` (or by
/// `Connection.execute` during a follow-up failure) into a one-line
/// message a user can act on. Keeps the original `toString()` available
/// as the technical detail line.
class FriendlyConnectError {
  FriendlyConnectError({required this.message, required this.detail});

  final String message;
  final String detail;

  @override
  String toString() => message;
}

FriendlyConnectError friendlyConnectError(
  Object error,
  ConnectionConfig config,
) {
  final detail = error.toString();
  final host = '${config.host}:${config.port}';

  if (error is SocketException) {
    return FriendlyConnectError(
      message: "Can't reach $host. Check the host, port, and your VPN.",
      detail: detail,
    );
  }
  if (error is TimeoutException) {
    return FriendlyConnectError(
      message: 'Connection to $host timed out.',
      detail: detail,
    );
  }
  if (error is ServerException) {
    final code = error.code;
    final byCode = _byCode(code, config);
    if (byCode != null) {
      return FriendlyConnectError(message: byCode, detail: detail);
    }
    final byMessage = _byMessage(error.message, config);
    if (byMessage != null) {
      return FriendlyConnectError(message: byMessage, detail: detail);
    }
    return FriendlyConnectError(message: error.message, detail: detail);
  }
  return FriendlyConnectError(message: detail, detail: detail);
}

String? _byCode(String? code, ConnectionConfig c) {
  switch (code) {
    case '28P01':
      return 'Wrong password for user "${c.username}".';
    case '28000':
      return 'Authentication failed for user "${c.username}".';
    case '3D000':
      return 'Database "${c.database}" does not exist on the server.';
    case '3F000':
      return 'Schema not found.';
    case '53300':
      return 'Server has too many open connections.';
    case '57P03':
      return 'Server is starting up; try again in a moment.';
    case '08006':
      return 'Server closed the connection.';
    default:
      return null;
  }
}

/// Last-resort message-pattern matching for older servers that don't
/// surface a sqlState on the exception.
String? _byMessage(String message, ConnectionConfig c) {
  final m = message.toLowerCase();
  if (m.contains('password authentication')) {
    return 'Wrong password for user "${c.username}".';
  }
  if (m.contains('does not exist') && m.contains('database')) {
    return 'Database "${c.database}" does not exist on the server.';
  }
  if (m.contains('ssl') && m.contains('required')) {
    return 'Server requires SSL — toggle the SSL switch in the connection dialog.';
  }
  return null;
}
