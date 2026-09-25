import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Outcome of running a connection's password command.
sealed class CommandResult {
  const CommandResult();
}

class CommandOk extends CommandResult {
  const CommandOk(this.password);
  final String password;
}

class CommandFailure extends CommandResult {
  const CommandFailure(this.message);
  final String message;
}

/// Runs a user-supplied shell command whose standard output is a password —
/// `op read …`, `security find-generic-password -w …`, `pass show …`.
///
/// The command goes through the user's login shell (`-l -c`) so the PATH
/// their profile builds, Homebrew included, is in effect: an app started
/// from the Dock inherits launchd's minimal environment instead. Nothing is
/// cached; every connect runs the command again.
class PasswordCommand {
  PasswordCommand({
    this.timeout = const Duration(seconds: 60),
    String? shell,
  }) : _shell = shell ?? _loginShell();

  /// Long enough for a biometric or 1Password unlock prompt to be answered.
  final Duration timeout;
  final String _shell;

  /// `$SHELL` when launchd passed one down, otherwise zsh — the macOS
  /// default login shell since Catalina.
  static String _loginShell() {
    final shell = Platform.environment['SHELL'];
    return shell == null || shell.isEmpty ? '/bin/zsh' : shell;
  }

  Future<CommandResult> run(String command) async {
    final Process process;
    try {
      process = await Process.start(_shell, ['-l', '-c', command]);
    } on ProcessException catch (e) {
      return CommandFailure('could not start $_shell: ${e.message}');
    }
    await process.stdin.close();
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      return CommandFailure(
        'timed out after ${timeout.inSeconds} s: $command',
      );
    }
    final out = await stdout;
    if (code != 0) {
      final err = (await stderr).trim();
      return CommandFailure(err.isEmpty ? 'exited with code $code' : err);
    }
    final password = _stripFinalNewline(out);
    if (password.isEmpty) {
      return const CommandFailure('the command printed no password');
    }
    return CommandOk(password);
  }

  /// Drops the one line break a command prints after its value. Anything
  /// else is kept: a password may legitimately end in whitespace.
  static String _stripFinalNewline(String s) {
    if (s.endsWith('\r\n')) return s.substring(0, s.length - 2);
    if (s.endsWith('\n')) return s.substring(0, s.length - 1);
    return s;
  }
}
