import '../../../models/connection_config.dart';
import '../../../services/db_service.dart';
import '../../../services/password_command.dart';

/// Lifecycle of the dialog's "Test connection" probe.
enum TestStatus { idle, busy, ok, fail }

/// Outcome of one [runConnectionTest] probe — drives the footer status pill.
class TestResult {
  const TestResult({
    required this.status,
    this.message,
    this.elapsed,
    this.version,
  });

  const TestResult.idle() : this(status: TestStatus.idle);

  const TestResult.busy() : this(status: TestStatus.busy);

  final TestStatus status;
  final String? message;
  final Duration? elapsed;
  final String? version;
}

/// Opens a throwaway connection described by [cfg] and reports how it went.
/// A command credential is run through [command] first; the resolved
/// password lives only for the probe and is never persisted.
Future<TestResult> runConnectionTest(
  ConnectionConfig cfg,
  PasswordCommand command,
) async {
  final String runtimePassword;
  switch (cfg.credential) {
    case PasswordCredential(password: final p):
      runtimePassword = p;
    case CommandCredential(command: final c):
      switch (await command.run(c)) {
        case CommandOk(password: final p):
          runtimePassword = p;
        case CommandFailure(message: final m):
          return TestResult(
            status: TestStatus.fail,
            message: 'Password command: $m',
          );
      }
  }
  final svc = createDbService(cfg.copyWith(runtimePassword: runtimePassword));
  final watch = Stopwatch()..start();
  try {
    await svc.connect();
    final tag = await svc.fetchVersionTag();
    watch.stop();
    return TestResult(
      status: TestStatus.ok,
      elapsed: watch.elapsed,
      version: tag ?? '',
    );
  } catch (err) {
    watch.stop();
    return TestResult(
      status: TestStatus.fail,
      elapsed: watch.elapsed,
      message: err.toString().replaceFirst(
        RegExp(r'^[A-Za-z]+Exception:\s*'),
        '',
      ),
    );
  } finally {
    try {
      await svc.close();
    } catch (_) {}
  }
}

