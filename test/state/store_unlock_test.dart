import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/keychain.dart';
import 'package:aperture/services/store_database.dart';
import 'package:aperture/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKeychain extends Keychain {
  String? stored;

  @override
  Future<String?> readPassphrase() async => stored;

  @override
  Future<bool> writePassphrase(String passphrase) async {
    stored = passphrase;
    return true;
  }

  @override
  Future<void> deletePassphrase() async => stored = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String path;
  late _FakeKeychain keychain;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('unlock');
    path = '${dir.path}/store.sqlite';
    keychain = _FakeKeychain();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppState newState() {
    final state = AppState(keychain: keychain, storePath: path);
    addTearDown(state.store.dispose);
    return state;
  }

  test('the first unlock creates the store', () async {
    final state = newState();
    expect(await state.storeExists(), isFalse);
    await state.unlockStore('pw', remember: false);
    expect(state.store.isOpen, isTrue);
    expect(await state.storeExists(), isTrue);
  });

  test('remember puts the passphrase in the Keychain and it unlocks next '
      'launch', () async {
    final first = newState();
    await first.unlockStore('pw', remember: true);
    first.store.addConnection(ConnectionConfig(id: 'c', name: 'kept'));
    await first.store.flush();
    expect(keychain.stored, 'pw');

    final second = newState();
    expect(await second.unlockFromKeychain(), isTrue);
    expect(second.store.connectionById('c')!.name, 'kept');
  });

  test('not remembering removes a stored passphrase', () async {
    keychain.stored = 'pw';
    await newState().unlockStore('pw', remember: false);
    expect(keychain.stored, isNull);
  });

  test('a stale Keychain passphrase is dropped, not retried', () async {
    await newState().unlockStore('pw', remember: false);
    keychain.stored = 'old';
    final state = newState();
    expect(await state.unlockFromKeychain(), isFalse);
    expect(state.store.isOpen, isFalse);
    expect(keychain.stored, isNull);
  });

  test('a wrong passphrase leaves the store locked', () async {
    await newState().unlockStore('pw', remember: false);
    final state = newState();
    await expectLater(
      state.unlockStore('nope', remember: true),
      throwsA(isA<WrongPassphraseException>()),
    );
    expect(state.store.isOpen, isFalse);
    expect(keychain.stored, isNull);
  });

  test('changing the passphrase checks the current one', () async {
    final state = newState();
    await state.unlockStore('pw', remember: true);
    await expectLater(
      state.changeStorePassphrase('nope', 'next', remember: true),
      throwsA(isA<WrongPassphraseException>()),
    );
    await state.changeStorePassphrase('pw', 'next', remember: true);
    expect(keychain.stored, 'next');
    expect(
      () => StoreDatabase.open(path, 'pw'),
      throwsA(isA<WrongPassphraseException>()),
    );
  });

  test('erasing deletes the store and the remembered passphrase', () async {
    await newState().unlockStore('pw', remember: true);
    final state = newState();
    await state.eraseStore();
    expect(await state.storeExists(), isFalse);
    expect(keychain.stored, isNull);
  });
}
