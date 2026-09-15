import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/models/log_event.dart';
import 'package:aperture/state/event_log.dart';
import 'package:aperture/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tmp;
  late EventLog log;
  late SessionController session;

  ConnectionConfig sqliteAt(String name, {String? path}) {
    final p = path ?? '${tmp.path}/$name.db';
    if (!File(p).existsSync()) {
      sqlite3.open(p)
        ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY);')
        ..dispose();
    }
    return ConnectionConfig(
      id: name,
      name: name,
      engine: DbEngine.sqlite,
      filePath: p,
    );
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aperture_session');
    log = EventLog();
    session = SessionController(log: log);
  });

  tearDown(() async {
    session.dispose();
    await tmp.delete(recursive: true);
  });

  group('connect', () {
    test('a good connection reaches connected and logs it', () async {
      expect(await session.connect(sqliteAt('a')), isTrue);
      expect(session.status, ConnectionStatus.connected);
      expect(session.isConnected, isTrue);
      expect(session.service, isNotNull);
      expect(log.events.map((e) => e.kind), contains(LogEventKind.connect));
    });

    test('a missing file fails with a friendly error and no service', () async {
      final ok = await session.connect(
        ConnectionConfig(
          id: 'x',
          name: 'x',
          engine: DbEngine.sqlite,
          filePath: '${tmp.path}/nope.db',
        ),
      );
      expect(ok, isFalse);
      expect(session.status, ConnectionStatus.error);
      expect(session.service, isNull);
      expect(session.error, isNotNull);
      expect(log.events.last.kind, LogEventKind.error);
    });

    test('a superseded attempt does not overwrite the winner', () async {
      // Clicking a second connection while the first is still resolving.
      // The loser used to null `_service` on its own failure, leaving the
      // winner's socket open but unreachable.
      final first = session.connect(
        ConnectionConfig(
          id: 'slow',
          name: 'slow',
          engine: DbEngine.sqlite,
          filePath: '${tmp.path}/missing.db',
        ),
      );
      final second = session.connect(sqliteAt('b'));
      final results = await Future.wait([first, second]);

      expect(results.last, isTrue, reason: 'the last click wins');
      expect(session.status, ConnectionStatus.connected);
      expect(session.service, isNotNull);
      expect(session.activeConnection!.id, 'b');
    });

    test('connecting again replaces the previous session', () async {
      await session.connect(sqliteAt('a'));
      final firstService = session.service;
      await session.connect(sqliteAt('b'));
      expect(session.service, isNot(same(firstService)));
      expect(session.activeConnection!.id, 'b');
    });
  });

  group('markLost and reconnect', () {
    test('markLost keeps the connection config for a retry', () async {
      await session.connect(sqliteAt('a'));
      await session.markLost('socket died');

      expect(session.status, ConnectionStatus.lost);
      expect(session.service, isNull);
      // The workspace stays mounted for `lost`, so the config has to
      // survive for the banner's Reconnect to have something to open.
      expect(session.activeConnection, isNotNull);
      expect(log.events.last.kind, LogEventKind.lost);
    });

    test('markLost is a no-op once lost or disconnected', () async {
      await session.connect(sqliteAt('a'));
      await session.markLost('first');
      await session.markLost('second');
      expect(session.error, 'first');

      await session.disconnect();
      await session.markLost('third');
      expect(session.status, ConnectionStatus.disconnected);
    });

    test('reconnect from lost never passes through connecting', () async {
      await session.connect(sqliteAt('a'));
      await session.markLost('dropped');

      final seen = <ConnectionStatus>[];
      session.addListener(() => seen.add(session.status));
      expect(await session.reconnect(), isTrue);

      // A `connecting` transition would unmount the workspace, since the
      // shell only mounts it for connected || lost.
      expect(seen, isNot(contains(ConnectionStatus.connecting)));
      expect(session.status, ConnectionStatus.connected);
    });

    test('a failed reconnect from lost stays lost', () async {
      final path = '${tmp.path}/vanishing.db';
      await session.connect(sqliteAt('vanishing', path: path));
      await session.markLost('dropped');
      File(path).deleteSync();

      expect(await session.reconnect(), isFalse);
      expect(session.status, ConnectionStatus.lost);
      expect(session.error, isNotNull);
    });

    test('reconnect with no active connection is a no-op', () async {
      expect(await session.reconnect(), isFalse);
    });
  });

  group('disconnect', () {
    test('clears everything and logs it', () async {
      await session.connect(sqliteAt('a'));
      await session.disconnect();

      expect(session.status, ConnectionStatus.disconnected);
      expect(session.service, isNull);
      expect(session.activeConnection, isNull);
      expect(session.error, isNull);
      expect(log.events.last.kind, LogEventKind.disconnect);
    });

    test('does not report itself as a lost connection', () async {
      await session.connect(sqliteAt('a'));
      await session.disconnect();
      // The status used to flip after the socket closed, so an in-flight
      // request failing mid-close raised a phantom `lost`.
      expect(
        log.events.map((e) => e.kind),
        isNot(contains(LogEventKind.lost)),
      );
    });
  });

  group('setActiveConnection', () {
    test('replaces the snapshot for the same id', () async {
      final config = sqliteAt('a');
      await session.connect(config);
      session.setActiveConnection(config.copyWith(name: 'renamed'));
      expect(session.activeConnection!.name, 'renamed');
    });

    test('ignores a snapshot for a different connection', () async {
      await session.connect(sqliteAt('a'));
      session.setActiveConnection(sqliteAt('b'));
      expect(session.activeConnection!.id, 'a');
    });
  });

  group('keepalive', () {
    test('a probe on a live connection stays out of the log', () async {
      final quick = SessionController(
        log: log,
        keepaliveInterval: const Duration(milliseconds: 20),
      );
      await quick.connect(sqliteAt('a'));
      final before = log.events.length;
      await Future<void>.delayed(const Duration(milliseconds: 90));

      // Several ticks have fired by now; none of them may reach the log,
      // or an afternoon's worth would evict the user's real history.
      expect(log.events.length, before);
      expect(quick.status, ConnectionStatus.connected);
      quick.dispose();
    });

    test('a probe against a closed database marks the session lost',
        () async {
      final quick = SessionController(
        log: log,
        keepaliveInterval: const Duration(milliseconds: 20),
      );
      await quick.connect(sqliteAt('a'));
      // Pull the handle out from under the probe.
      await quick.service!.close();
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(quick.status, ConnectionStatus.lost);
      quick.dispose();
    });
  });

  group('setError', () {
    test('surfaces a pre-connect failure without a service', () {
      session.setError('Master passphrase required.');
      expect(session.status, ConnectionStatus.error);
      expect(session.error, 'Master passphrase required.');
      expect(session.service, isNull);
    });
  });

  group('updateLostError', () {
    test('refreshes the banner text only while lost', () async {
      await session.connect(sqliteAt('a'));
      session.updateLostError('ignored while connected');
      expect(session.error, isNull);

      await session.markLost('dropped');
      session.updateLostError('op not installed');
      expect(session.error, 'op not installed');
      expect(session.status, ConnectionStatus.lost);
    });
  });
}
