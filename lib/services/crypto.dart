import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

const int passphraseSaltBytes = 16;
const int passphraseKeyBytes = 32;
const int passphraseIterations = 200000;
const int aesGcmNonceBytes = 12;
const int aesGcmTagBits = 128;

Uint8List randomBytes(int n) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
}

Uint8List derivePassphraseKey(String passphrase, Uint8List salt) {
  final params = Pbkdf2Parameters(salt, passphraseIterations, passphraseKeyBytes);
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
  return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
}

Uint8List aesGcmEncrypt(Uint8List key, List<int> plaintext) {
  final nonce = randomBytes(aesGcmNonceBytes);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), aesGcmTagBits, nonce, Uint8List(0)),
    );
  final ct = cipher.process(Uint8List.fromList(plaintext));
  return Uint8List.fromList([...nonce, ...ct]);
}

Uint8List aesGcmDecrypt(Uint8List key, Uint8List blob) {
  if (blob.length < aesGcmNonceBytes + aesGcmTagBits ~/ 8) {
    throw ArgumentError('blob too short');
  }
  final nonce = blob.sublist(0, aesGcmNonceBytes);
  final ct = blob.sublist(aesGcmNonceBytes);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), aesGcmTagBits, nonce, Uint8List(0)),
    );
  return cipher.process(ct);
}
