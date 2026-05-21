import 'dart:async';
import 'dart:io';

/// Outcome of a `op read` invocation.
///
/// Modeled explicitly so the connect path can distinguish "you haven't
/// installed `op`" from "the secret reference is wrong" from "1Password is
/// locked" — each wants a different message in the UI.
sealed class OpResult {
  const OpResult();
}

class OpSuccess extends OpResult {
  const OpSuccess(this.value);
  final String value;
}

class OpMissing extends OpResult {
  const OpMissing();
}

class OpFailure extends OpResult {
  const OpFailure(this.message);
  final String message;
}

/// Thin wrapper around the 1Password CLI (`op`). Looks the binary up in
/// the usual Homebrew prefixes plus `$PATH`, then shells out to
/// `op read <ref>` and returns the trimmed value.
///
/// The 1Password desktop app handles all auth (biometrics, master
/// password, account switching). We never see credentials and we don't
/// cache the resolved password — every connect re-reads through `op`.
class OnePasswordClient {
  OnePasswordClient({List<String>? searchPaths})
    : _searchPaths =
          searchPaths ??
          const [
            '/opt/homebrew/bin/op',
            '/usr/local/bin/op',
            '/usr/bin/op',
          ];

  final List<String> _searchPaths;
  String? _cachedBinary;

  /// Resolves the absolute path to `op`. Returns null when not installed.
  Future<String?> _resolveBinary() async {
    if (_cachedBinary != null) return _cachedBinary;
    for (final path in _searchPaths) {
      if (await File(path).exists()) {
        return _cachedBinary = path;
      }
    }
    final which = await Process.run('/usr/bin/which', ['op']);
    if (which.exitCode == 0) {
      final out = (which.stdout as String).trim();
      if (out.isNotEmpty) return _cachedBinary = out;
    }
    return null;
  }

  Future<OpResult> read(String secretRef) async {
    final binary = await _resolveBinary();
    if (binary == null) return const OpMissing();
    try {
      final proc = await Process.run(binary, ['read', secretRef]);
      if (proc.exitCode == 0) {
        return OpSuccess((proc.stdout as String).trimRight());
      }
      final err = (proc.stderr as String).trim();
      return OpFailure(err.isEmpty ? 'op exited with ${proc.exitCode}' : err);
    } on ProcessException catch (e) {
      return OpFailure(e.message);
    }
  }
}
