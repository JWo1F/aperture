import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/store_database.dart';
import 'package:aperture/state/app_state.dart';
import 'package:aperture/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppState state;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aperture_connect_test');
    PathProviderPlatform.instance = _StubPathProvider(tmp);
    state = AppState(store: AppStore()..open(StoreDatabase.inMemory()));
  });

  tearDown(() async {
    state.dispose();
    await tmp.delete(recursive: true);
  });

  group('ConnectionConfig.sameTarget', () {
    final base = ConnectionConfig(
      id: 'c',
      name: 'base',
      host: 'db.internal',
      port: 5432,
      database: 'app',
      username: 'postgres',
    );

    test('name, colour and credential do not change the target', () {
      expect(base.sameTarget(base.copyWith(name: 'renamed')), isTrue);
      expect(base.sameTarget(base.copyWith(color: 0xFF00FF00)), isTrue);
      expect(
        base.sameTarget(
          base.copyWith(credential: const CommandCredential('x')),
        ),
        isTrue,
      );
    });

    test('anything a socket was opened against does', () {
      expect(base.sameTarget(base.copyWith(host: 'other')), isFalse);
      expect(base.sameTarget(base.copyWith(port: 5433)), isFalse);
      expect(base.sameTarget(base.copyWith(database: 'app_test')), isFalse);
      expect(base.sameTarget(base.copyWith(username: 'readonly')), isFalse);
      expect(base.sameTarget(base.copyWith(tls: TlsMode.require)), isFalse);
      expect(base.sameTarget(base.copyWith(engine: DbEngine.sqlite)), isFalse);
      expect(base.sameTarget(base.copyWith(filePath: '/tmp/a.db')), isFalse);
    });

    test('readOnly counts, because the grid gates editing on it', () {
      expect(base.sameTarget(base.copyWith(readOnly: true)), isFalse);
    });
  });

  test('deleting the active connection closes the session', () async {
    final path = '${tmp.path}/gone.db';
    sqlite3.open(path)
      ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY);')
      ..close();
    final config = ConnectionConfig(
      id: 'gone',
      name: 'gone',
      engine: DbEngine.sqlite,
      filePath: path,
    );
    state.store.addConnection(config);
    await state.connect(config);
    expect(state.session.status, ConnectionStatus.connected);

    // Nothing can be persisted against a connection that no longer exists,
    // so leaving the session open would drop every later write silently.
    state.store.removeConnection('gone');
    await Future<void>.delayed(Duration.zero);

    expect(state.session.status, ConnectionStatus.disconnected);
    expect(state.session.activeConnection, isNull);
  });

  test('editing the active connection re-opens against the new target',
      () async {
    final a = '${tmp.path}/a.db';
    final b = '${tmp.path}/b.db';
    for (final p in [a, b]) {
      sqlite3.open(p)
        ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY);')
        ..close();
    }
    final config = ConnectionConfig(
      id: 'sw',
      name: 'switcher',
      engine: DbEngine.sqlite,
      filePath: a,
    );
    state.store.addConnection(config);
    await state.connect(config);
    expect(state.session.activeConnection!.filePath, a);

    // Repointing the config used to leave the UI naming b while every
    // query still went to a.
    state.store.updateConnection(config.copyWith(filePath: b));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(state.session.status, ConnectionStatus.connected);
    expect(state.session.activeConnection!.filePath, b);
    expect(state.session.service!.config.filePath, b);
  });

  test('a connect that never opens keeps the workspace', () async {
    state.tabsController.newQueryTab();
    state.tabsController.newQueryTab();
    expect(state.tabsController.tabs, hasLength(2));

    // Resolving the credential is a pre-flight step, and it can fail for
    // reasons that have nothing to do with the database: a password command
    // that errors, times out, or was never filled in.
    await state.connect(
      ConnectionConfig(
        id: 'c1',
        name: 'never opens',
        credential: const CommandCredential(''),
      ),
    );

    expect(state.session.status, ConnectionStatus.error);
    expect(
      state.tabsController.tabs,
      hasLength(2),
      reason: 'the previous session is still the live one',
    );
  });
}
