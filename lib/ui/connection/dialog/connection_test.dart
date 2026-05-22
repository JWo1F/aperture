import '../../../models/connection_config.dart';
import '../../../services/db_service.dart';
import '../../../services/one_password_client.dart';

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
/// For 1Password-backed configs the secret is resolved through [op] first;
/// the resolved password lives only for the probe and is never persisted.
Future<TestResult> runConnectionTest(
  ConnectionConfig cfg,
  OnePasswordClient op,
) async {
  var resolved = cfg;
  if (cfg.credentialSource == CredentialSource.onePassword) {
    final r = await op.read(cfg.opSecretRef ?? '');
    switch (r) {
      case OpSuccess(value: final v):
        resolved = cfg.copyWith(password: v);
      case OpMissing():
        return const TestResult(
          status: TestStatus.fail,
          message: 'op CLI not installed (brew install 1password-cli)',
        );
      case OpFailure(message: final m):
        return TestResult(status: TestStatus.fail, message: '1Password: $m');
    }
  }
  final svc = createDbService(resolved);
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
