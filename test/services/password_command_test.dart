import 'package:aperture/services/password_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // /bin/sh keeps these independent of the developer's shell profile.
  final command = PasswordCommand(shell: '/bin/sh');

  test('stdout minus its final newline is the password', () async {
    final r = await command.run(r"printf 'hunter2\n'");
    expect((r as CommandOk).password, 'hunter2');
  });

  test('only the final line break is dropped, not other whitespace', () async {
    final r = await command.run(r"printf ' pa ss \n'");
    expect((r as CommandOk).password, ' pa ss ');
  });

  test('a failing command reports its stderr', () async {
    final r = await command.run("echo 'no such item' >&2; exit 3");
    expect((r as CommandFailure).message, 'no such item');
  });

  test('a silent failure reports its exit code', () async {
    final r = await command.run('exit 4');
    expect((r as CommandFailure).message, contains('4'));
  });

  test('empty output is an error, not an empty password', () async {
    final r = await command.run('true');
    expect(r, isA<CommandFailure>());
  });

  test('a command that hangs is killed at the timeout', () async {
    final quick = PasswordCommand(
      shell: '/bin/sh',
      timeout: const Duration(milliseconds: 200),
    );
    final r = await quick.run('sleep 5');
    expect((r as CommandFailure).message, contains('timed out'));
  });
}
