import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../services/security_store.dart';

/// Owns the master-passphrase lifecycle for the session: setup, unlock,
/// lock, and the AES-GCM helpers used by [ConnectionRegistry] to
/// encrypt and decrypt connection passwords.
///
/// The derived key lives in memory only — `lock()` (and app shutdown)
/// drop it, and the user must re-enter the passphrase next time an
/// encrypted credential is needed.
class MasterPassphrase extends ChangeNotifier {
  MasterPassphrase({SecurityStore? store})
    : _store = store ?? SecurityStore();

  final SecurityStore _store;

  static const _sentinel = 'dbv-vault-ok';
  static const _iterations = 200000;
  static const _keyBytes = 32;
  static const _saltBytes = 16;
  static const _nonceBytes = 12;
  static const _tagBits = 128;

  Map<String, dynamic>? _meta;
  Uint8List? _key;
  bool _loaded = false;

  /// True once we've checked `security.json` at least once.
  bool get isLoaded => _loaded;

  /// True if the user has already set up a passphrase.
  bool get isConfigured => _meta != null;

  /// True if the derived key is in memory and ready to encrypt/decrypt.
  bool get isUnlocked => _key != null;

  Future<void> hydrate() async {
    _meta = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  /// First-time setup. Generates a salt, derives the key, encrypts the
  /// sentinel, persists the verifier, and leaves the session unlocked.
  /// Returns false if a passphrase is already configured — callers
  /// should route to [unlock] in that case.
  Future<bool> setup(String passphrase) async {
    if (passphrase.isEmpty) return false;
    if (_meta != null) return false;
    final salt = _randomBytes(_saltBytes);
    final key = _deriveKey(passphrase, salt);
    final verifier = _encrypt(key, utf8.encode(_sentinel));
    final meta = <String, dynamic>{
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'verifier': base64Encode(verifier),
    };
    await _store.save(meta);
    _meta = meta;
    _key = key;
    notifyListeners();
    return true;
  }

  /// Tries to unlock the session with [passphrase]. Returns true on
  /// success and leaves [isUnlocked] true; returns false otherwise.
  Future<bool> unlock(String passphrase) async {
    final meta = _meta;
    if (meta == null) return false;
    final salt = base64Decode(meta['salt'] as String);
    final verifier = base64Decode(meta['verifier'] as String);
    final key = _deriveKey(passphrase, salt);
    try {
      final plain = _decrypt(key, verifier);
      if (utf8.decode(plain) != _sentinel) return false;
    } catch (_) {
      return false;
    }
    _key = key;
    notifyListeners();
    return true;
  }

  void lock() {
    if (_key == null) return;
    _key = null;
    notifyListeners();
  }

  /// Returns base64-encoded `nonce || ciphertext || tag`. Throws
  /// [StateError] if the session is locked.
  String encrypt(String plaintext) {
    final key = _key;
    if (key == null) {
      throw StateError('master passphrase is locked');
    }
    final out = _encrypt(key, utf8.encode(plaintext));
    return base64Encode(out);
  }

  /// Decrypts a base64 blob produced by [encrypt]. Returns null on any
  /// decryption failure (wrong key, tampered ciphertext).
  String? decrypt(String cipher) {
    final key = _key;
    if (key == null) {
      throw StateError('master passphrase is locked');
    }
    try {
      final plain = _decrypt(key, base64Decode(cipher));
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  // ---- crypto primitives -------------------------------------------

  Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, _iterations, _keyBytes);
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(params);
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  Uint8List _encrypt(Uint8List key, List<int> plaintext) {
    final nonce = _randomBytes(_nonceBytes);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    final ct = cipher.process(Uint8List.fromList(plaintext));
    return Uint8List.fromList([...nonce, ...ct]);
  }

  Uint8List _decrypt(Uint8List key, Uint8List blob) {
    if (blob.length < _nonceBytes + _tagBits ~/ 8) {
      throw ArgumentError('blob too short');
    }
    final nonce = blob.sublist(0, _nonceBytes);
    final ct = blob.sublist(_nonceBytes);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    return cipher.process(ct);
  }

  Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }
}
