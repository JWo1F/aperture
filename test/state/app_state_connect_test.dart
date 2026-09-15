import 'dart:io';

import 'package:dbv/models/connection_config.dart';
import 'package:dbv/services/atomic_json.dart';
import 'package:dbv/state/app_state.dart';
import 'package:dbv/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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
    tmp = await Directory.systemTemp.createTemp('dbv_connect_test');
    PathProviderPlatform.instance = _StubPathProvider(tmp);
    state = AppState(store: AppStore(file: AtomicJsonFile('store.json')));
  });

  tearDown(() async {
    state.dispose();
    await tmp.delete(recursive: true);
  });

  test('a connect that never opens keeps the workspace', () async {
    state.tabsController.newQueryTab();
    state.tabsController.newQueryTab();
    expect(state.tabsController.tabs, hasLength(2));

    // Resolving the credential is a pre-flight step, and it can fail for
    // reasons that have nothing to do with the database: a locked vault, a
    // missing `op` binary, a connection saved with no password at all.
    await state.connect(
      ConnectionConfig(
        id: 'c1',
        name: 'never opens',
        credential: const EncryptedCredential(''),
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
