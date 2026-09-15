import 'dart:io';

import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/atomic_json.dart';
import 'package:aperture/services/one_password_client.dart';
import 'package:aperture/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _StubPathProvider extends PathProviderPlatform {
  _StubPathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => root.path;
}

class _FakeOnePassword extends OnePasswordClient {
  _FakeOnePassword(this.result);

  final OpResult result;
  final refs = <String>[];

  @override
  Future<OpResult> read(String secretRef) async {
    refs.add(secretRef);
    return result;
  }
}

ConnectionConfig _withCredential(Credential credential) => ConnectionConfig(
  id: 'c',
  name: 'c',
  credential: credential,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  AppStore storeWith([OnePasswordClient? op]) => AppStore(
    file: AtomicJsonFile('store.json'),
    onePassword: op,
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aperture_cred');
    PathProviderPlatform.instance = _StubPathProvider(tmp);
  });

  tearDown(() => tmp.delete(recursive: true));

  group('plain credentials', () {
    test('hand back the stored password as-is', () async {
      final store = storeWith();
      final r = await store.readCredential(
        _withCredential(const PlainCredential('hunter2')),
      );
      expect(r, isA<CredentialOk>());
      expect((r as CredentialOk).password, 'hunter2');
    });

    test('an empty plain password is still a value, not an error', () async {
      // Trust-authentication and unix-socket setups legitimately have none.
      final store = storeWith();
      final r = await store.readCredential(
        _withCredential(const PlainCredential('')),
      );
      expect((r as CredentialOk).password, '');
    });
  });

  group('encrypted credentials', () {
    test('an empty cipher says the connection has no password saved',
        () async {
      final store = storeWith();
      final r = await store.readCredential(
        _withCredential(const EncryptedCredential('')),
      );
      expect(r, isA<CredentialError>());
      expect((r as CredentialError).message, contains('edit it'));
    });

    test('a locked vault asks for the passphrase rather than failing',
        () async {
      final store = storeWith();
      await store.setupPassphrase('correct horse');
      final cipher = store.encryptWithPassphrase('hunter2');
      store.lockPassphrase();

      final r = await store.readCredential(
        _withCredential(EncryptedCredential(cipher)),
      );
      expect(r, isA<CredentialNeedsPassphrase>());
    });

    test('an unlocked vault decrypts', () async {
      final store = storeWith();
      await store.setupPassphrase('correct horse');
      final cipher = store.encryptWithPassphrase('hunter2');

      final r = await store.readCredential(
        _withCredential(EncryptedCredential(cipher)),
      );
      expect((r as CredentialOk).password, 'hunter2');
    });

    test('a tampered cipher is an error, not a throw', () async {
      final store = storeWith();
      await store.setupPassphrase('correct horse');
      final cipher = store.encryptWithPassphrase('hunter2');
      final broken = 'A${cipher.substring(1)}';

      final r = await store.readCredential(
        _withCredential(EncryptedCredential(broken)),
      );
      expect(r, isA<CredentialError>());
      expect((r as CredentialError).message, contains('passphrase'));
    });

    test('a wrong passphrase does not unlock', () async {
      final store = storeWith();
      await store.setupPassphrase('correct horse');
      store.lockPassphrase();
      expect(await store.unlockPassphrase('wrong'), isFalse);
      expect(store.isPassphraseUnlocked, isFalse);
      expect(await store.unlockPassphrase('correct horse'), isTrue);
      expect(store.isPassphraseUnlocked, isTrue);
    });

    test('setup refuses to run twice over an existing vault', () async {
      final store = storeWith();
      expect(await store.setupPassphrase('first'), isTrue);
      expect(await store.setupPassphrase('second'), isFalse);
      // The original still works, so no existing ciphertext is orphaned.
      store.lockPassphrase();
      expect(await store.unlockPassphrase('first'), isTrue);
    });

    test('an empty passphrase is refused', () async {
      final store = storeWith();
      expect(await store.setupPassphrase(''), isFalse);
      expect(store.isPassphraseConfigured, isFalse);
    });

    test('a vault survives a save and reload', () async {
      final store = storeWith();
      await store.setupPassphrase('correct horse');
      final cipher = store.encryptWithPassphrase('hunter2');
      await store.flush();

      final reopened = storeWith();
      await reopened.load();
      expect(reopened.isPassphraseConfigured, isTrue);
      expect(reopened.isPassphraseUnlocked, isFalse);
      expect(await reopened.unlockPassphrase('correct horse'), isTrue);
      expect(reopened.decryptWithPassphrase(cipher), 'hunter2');
    });
  });

  group('1Password credentials', () {
    test('a resolved secret comes back as the password', () async {
      final op = _FakeOnePassword(const OpSuccess('hunter2'));
      final store = storeWith(op);
      final r = await store.readCredential(
        _withCredential(const OnePasswordCredential('op://vault/item/pw')),
      );
      expect((r as CredentialOk).password, 'hunter2');
      expect(op.refs, ['op://vault/item/pw']);
    });

    test('an empty reference is caught before shelling out', () async {
      final op = _FakeOnePassword(const OpSuccess('unused'));
      final store = storeWith(op);
      final r = await store.readCredential(
        _withCredential(const OnePasswordCredential('')),
      );
      expect(r, isA<CredentialError>());
      expect(op.refs, isEmpty);
    });

    test('a missing op binary explains how to install it', () async {
      final store = storeWith(_FakeOnePassword(const OpMissing()));
      final r = await store.readCredential(
        _withCredential(const OnePasswordCredential('op://v/i/p')),
      );
      expect(r, isA<CredentialError>());
      expect((r as CredentialError).message, contains('brew install'));
    });

    test("op's own error text is surfaced, not swallowed", () async {
      final store = storeWith(
        _FakeOnePassword(const OpFailure('could not read item')),
      );
      final r = await store.readCredential(
        _withCredential(const OnePasswordCredential('op://v/i/p')),
      );
      expect((r as CredentialError).message, contains('could not read item'));
    });
  });

  group('runtime passwords never reach disk', () {
    test('a resolved password is stripped before persisting', () async {
      final store = storeWith();
      store.addConnection(
        ConnectionConfig(
          id: 'p',
          name: 'p',
          runtimePassword: 'should not persist',
        ),
      );
      await store.flush();

      final raw = await File('${tmp.path}/store.json').readAsString();
      expect(raw, isNot(contains('should not persist')));
      expect(store.connectionById('p')!.runtimePassword, '');
    });
  });
}
