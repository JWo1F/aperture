import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// The store passphrase in the user's login keychain, through the
/// `aperture/keychain` channel in `MainFlutterWindow.swift`.
///
/// A generic-password item: macOS unlocks it with the login session, and
/// asks the user before letting a differently-signed build read it — which
/// every ad-hoc debug build is, so a rebuild prompts once.
class Keychain {
  Keychain({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aperture/keychain');

  final MethodChannel _channel;

  static const _account = 'store-passphrase';

  /// Null when no passphrase is remembered, or the keychain refused.
  Future<String?> readPassphrase() async {
    try {
      return await _channel.invokeMethod<String>('read', {'account': _account});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      developer.log(
        'keychain read failed',
        name: 'aperture.keychain',
        error: e,
      );
      return null;
    }
  }

  /// Returns false when the keychain refused the write.
  Future<bool> writePassphrase(String passphrase) async {
    try {
      await _channel.invokeMethod<void>('write', {
        'account': _account,
        'secret': passphrase,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      developer.log(
        'keychain write failed',
        name: 'aperture.keychain',
        error: e,
      );
      return false;
    }
  }

  Future<void> deletePassphrase() async {
    try {
      await _channel.invokeMethod<void>('delete', {'account': _account});
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      developer.log(
        'keychain delete failed',
        name: 'aperture.keychain',
        error: e,
      );
    }
  }
}
