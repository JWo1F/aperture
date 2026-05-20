import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// Native macOS window-frame plumbing routed through `dbv/window`.
///
/// The Swift side translates between AppKit's bottom-left-origin frame
/// and our preference shape. Off-screen restorations (e.g. after the
/// user disconnects an external monitor) are ignored by the Swift side
/// and the window stays at its default position.
class WindowFrame {
  WindowFrame({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('dbv/window');

  final MethodChannel _channel;

  Future<Map<String, double>?> read() async {
    try {
      final raw = await _channel.invokeMethod('getWindowFrame');
      if (raw is Map) {
        return {
          'x': (raw['x'] as num).toDouble(),
          'y': (raw['y'] as num).toDouble(),
          'w': (raw['w'] as num).toDouble(),
          'h': (raw['h'] as num).toDouble(),
        };
      }
    } on MissingPluginException {
      // Tests / non-macOS — no-op.
    } catch (e, st) {
      developer.log(
        'getWindowFrame failed',
        name: 'dbv.window',
        error: e,
        stackTrace: st,
      );
    }
    return null;
  }

  Future<void> write(Map<String, double> frame) async {
    try {
      await _channel.invokeMethod('setWindowFrame', frame);
    } on MissingPluginException {
      // No-op in tests.
    } catch (e, st) {
      developer.log(
        'setWindowFrame failed',
        name: 'dbv.window',
        error: e,
        stackTrace: st,
      );
    }
  }
}
