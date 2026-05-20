import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// macOS Keychain-backed password store, keyed by connection id.
///
/// Bridged through the `dbv/window` MethodChannel into a small SecItem*
/// helper in MainFlutterWindow.swift — avoids the dependency on a Pods-
/// based plugin while still keeping passwords out of plaintext JSON.
///
/// Sandboxed macOS apps each get their own keychain partition automatically,
/// so no extra entitlement beyond `com.apple.security.app-sandbox` is needed
/// to read/write items the app itself created.
class PasswordVault {
  PasswordVault({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dbv/window');

  final MethodChannel _channel;

  Future<String?> read(String connectionId) async {
    try {
      return await _channel.invokeMethod<String>(
        'keychainRead',
        {'key': connectionId},
      );
    } on PlatformException catch (e, st) {
      developer.log(
        'keychain read failed',
        name: 'dbv.vault',
        error: e,
        stackTrace: st,
      );
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> write(String connectionId, String password) async {
    try {
      await _channel.invokeMethod<bool>(
        'keychainWrite',
        {'key': connectionId, 'value': password},
      );
    } on PlatformException catch (e, st) {
      developer.log(
        'keychain write failed',
        name: 'dbv.vault',
        error: e,
        stackTrace: st,
      );
    } on MissingPluginException {
      // No-op in environments without the native bridge (tests).
    }
  }

  Future<void> delete(String connectionId) async {
    try {
      await _channel.invokeMethod<bool>(
        'keychainDelete',
        {'key': connectionId},
      );
    } on PlatformException catch (e, st) {
      developer.log(
        'keychain delete failed',
        name: 'dbv.vault',
        error: e,
        stackTrace: st,
      );
    } on MissingPluginException {
      // No-op in tests.
    }
  }
}
