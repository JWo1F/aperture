import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// Native macOS window-frame plumbing routed through `aperture/window`.
///
/// The Swift side translates between AppKit's bottom-left-origin frame
/// and our preference shape. Off-screen restorations (e.g. after the
/// user disconnects an external monitor) are ignored by the Swift side
/// and the window stays at its default position.
class WindowFrame {
  WindowFrame({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aperture/window');

  final MethodChannel _channel;

  /// The window's frame (`x`, `y`, `w`, `h`, AppKit's bottom-left origin)
  /// and whether it is in full screen — in which case the frame is the
  /// screen's, not one worth restoring.
  Future<({Map<String, double> frame, bool fullScreen})?> read() async {
    try {
      final raw = await _channel.invokeMethod('getWindowFrame');
      if (raw is Map) {
        return (
          frame: {
            'x': (raw['x'] as num).toDouble(),
            'y': (raw['y'] as num).toDouble(),
            'w': (raw['w'] as num).toDouble(),
            'h': (raw['h'] as num).toDouble(),
          },
          fullScreen: raw['fullScreen'] == true,
        );
      }
    } on MissingPluginException {
      // Tests / non-macOS — no-op.
    } catch (e, st) {
      developer.log(
        'getWindowFrame failed',
        name: 'aperture.window',
        error: e,
        stackTrace: st,
      );
    }
    return null;
  }

  Future<void> setFullScreen(bool fullScreen) async {
    try {
      await _channel.invokeMethod('setFullScreen', fullScreen);
    } on MissingPluginException {
      // No-op in tests.
    } catch (e, st) {
      developer.log(
        'setFullScreen failed',
        name: 'aperture.window',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> write(Map<String, double> frame) async {
    try {
      await _channel.invokeMethod('setWindowFrame', frame);
    } on MissingPluginException {
      // No-op in tests.
    } catch (e, st) {
      developer.log(
        'setWindowFrame failed',
        name: 'aperture.window',
        error: e,
        stackTrace: st,
      );
    }
  }
}
