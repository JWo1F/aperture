import 'dart:convert';
import 'dart:typed_data';

import 'package:aperture/services/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('randomBytes', () {
    test('returns the requested length', () {
      expect(randomBytes(0), isEmpty);
      expect(randomBytes(12), hasLength(12));
      expect(randomBytes(32), hasLength(32));
    });

    test('two draws differ', () {
      expect(randomBytes(32), isNot(randomBytes(32)));
    });
  });

  group('derivePassphraseKey', () {
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));

    test('is deterministic for the same passphrase, salt and cost', () {
      final a = derivePassphraseKey('correct horse', salt, iterations: 1000);
      final b = derivePassphraseKey('correct horse', salt, iterations: 1000);
      expect(a, b);
      expect(a, hasLength(passphraseKeyBytes));
    });

    test('a different passphrase gives a different key', () {
      expect(
        derivePassphraseKey('a', salt, iterations: 1000),
        isNot(derivePassphraseKey('b', salt, iterations: 1000)),
      );
    });

    test('a different salt gives a different key', () {
      final other = Uint8List.fromList(List<int>.filled(16, 9));
      expect(
        derivePassphraseKey('a', salt, iterations: 1000),
        isNot(derivePassphraseKey('a', other, iterations: 1000)),
      );
    });

    test('a different cost gives a different key', () {
      // Which is why the cost has to be stored with each vault and read
      // back on unlock — raising the constant would otherwise lock the
      // user out of every password they had already saved.
      expect(
        derivePassphraseKey('a', salt, iterations: 1000),
        isNot(derivePassphraseKey('a', salt, iterations: 2000)),
      );
    });
  });

  group('aesGcm', () {
    final key = derivePassphraseKey(
      'pass',
      Uint8List.fromList(List<int>.filled(16, 1)),
      iterations: 1000,
    );

    test('round-trips a value', () {
      final sealed = aesGcmEncrypt(key, utf8.encode('hunter2'));
      expect(utf8.decode(aesGcmDecrypt(key, sealed)), 'hunter2');
    });

    test('round-trips empty and multi-byte text', () {
      for (final plain in ['', 'a', 'naïve café — ✓', 'x' * 5000]) {
        final sealed = aesGcmEncrypt(key, utf8.encode(plain));
        expect(utf8.decode(aesGcmDecrypt(key, sealed)), plain);
      }
    });

    test('the nonce is fresh per call, so output never repeats', () {
      final a = aesGcmEncrypt(key, utf8.encode('same'));
      final b = aesGcmEncrypt(key, utf8.encode('same'));
      expect(a, isNot(b));
      expect(
        a.sublist(0, aesGcmNonceBytes),
        isNot(b.sublist(0, aesGcmNonceBytes)),
      );
    });

    test('the blob carries nonce, ciphertext and tag', () {
      final sealed = aesGcmEncrypt(key, utf8.encode('abc'));
      expect(sealed, hasLength(aesGcmNonceBytes + 3 + aesGcmTagBits ~/ 8));
    });

    test('the wrong key is rejected, not silently mis-decrypted', () {
      final sealed = aesGcmEncrypt(key, utf8.encode('secret'));
      final wrong = derivePassphraseKey(
        'other',
        Uint8List.fromList(List<int>.filled(16, 1)),
        iterations: 1000,
      );
      expect(() => aesGcmDecrypt(wrong, sealed), throwsA(anything));
    });

    test('a flipped ciphertext bit is rejected by the tag', () {
      final sealed = aesGcmEncrypt(key, utf8.encode('secret'));
      sealed[sealed.length - 1] ^= 0x01;
      expect(() => aesGcmDecrypt(key, sealed), throwsA(anything));
    });

    test('a flipped nonce bit is rejected too', () {
      final sealed = aesGcmEncrypt(key, utf8.encode('secret'));
      sealed[0] ^= 0x01;
      expect(() => aesGcmDecrypt(key, sealed), throwsA(anything));
    });

    test('a blob too short to hold a nonce and tag is rejected', () {
      expect(
        () => aesGcmDecrypt(key, Uint8List(aesGcmNonceBytes)),
        throwsArgumentError,
      );
      expect(() => aesGcmDecrypt(key, Uint8List(0)), throwsArgumentError);
    });
  });

  group('cost parameters', () {
    test('are strong enough to be worth the wait', () {
      // OWASP's floor for PBKDF2-HMAC-SHA256 is six figures; a regression
      // to a few thousand would be invisible without an assertion.
      expect(passphraseIterations, greaterThanOrEqualTo(100000));
      expect(passphraseSaltBytes, greaterThanOrEqualTo(16));
      expect(passphraseKeyBytes, 32);
      expect(aesGcmNonceBytes, 12);
      expect(aesGcmTagBits, 128);
    });
  });
}
