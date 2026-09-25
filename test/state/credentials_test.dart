import 'package:aperture/models/connection_config.dart';
import 'package:aperture/services/password_command.dart';
import 'package:aperture/services/store_database.dart';
import 'package:aperture/state/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCommand extends PasswordCommand {
  _FakeCommand(this.result);

  final CommandResult result;
  final commands = <String>[];

  @override
  Future<CommandResult> run(String command) async {
    commands.add(command);
    return result;
  }
}

ConnectionConfig _withCredential(Credential credential) =>
    ConnectionConfig(id: 'c', name: 'c', credential: credential);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppStore storeWith([PasswordCommand? command]) {
    final store = AppStore(passwordCommand: command)
      ..open(StoreDatabase.inMemory());
    addTearDown(store.dispose);
    return store;
  }

  group('stored passwords', () {
    test('hand back the stored password as-is', () async {
      final store = storeWith();
      final r = await store.readCredential(
        _withCredential(const PasswordCredential('hunter2')),
      );
      expect(r, isA<CredentialOk>());
      expect((r as CredentialOk).password, 'hunter2');
    });

    test('an empty password is still a value, not an error', () async {
      // Trust-authentication and unix-socket setups legitimately have none.
      final store = storeWith();
      final r = await store.readCredential(
        _withCredential(const PasswordCredential('')),
      );
      expect((r as CredentialOk).password, '');
    });
  });

  group('command credentials', () {
    test("the command's output comes back as the password", () async {
      final command = _FakeCommand(const CommandOk('hunter2'));
      final store = storeWith(command);
      final r = await store.readCredential(
        _withCredential(const CommandCredential("op read 'op://v/i/pw'")),
      );
      expect((r as CredentialOk).password, 'hunter2');
      expect(command.commands, ["op read 'op://v/i/pw'"]);
    });

    test('an empty command is caught before shelling out', () async {
      final command = _FakeCommand(const CommandOk('unused'));
      final store = storeWith(command);
      final r = await store.readCredential(
        _withCredential(const CommandCredential('  ')),
      );
      expect(r, isA<CredentialError>());
      expect(command.commands, isEmpty);
    });

    test("the command's own error text is surfaced", () async {
      final store = storeWith(
        _FakeCommand(const CommandFailure('item not found')),
      );
      final r = await store.readCredential(
        _withCredential(const CommandCredential('op read x')),
      );
      expect((r as CredentialError).message, contains('item not found'));
    });
  });
}
