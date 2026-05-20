import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/preferences_store.dart';
import '../services/window_frame.dart';
import '../theme/app_theme.dart';

/// Global app preferences: theme brightness, window frame, etc.
class PreferencesController extends ChangeNotifier {
  PreferencesController({
    PreferencesStore? store,
    WindowFrame? window,
  })  : _store = store ?? PreferencesStore(),
        _window = window ?? WindowFrame();

  final PreferencesStore _store;
  final WindowFrame _window;

  AppBrightness _brightness = AppBrightness.dark;
  AppBrightness get brightness => _brightness;

  Map<String, double>? _frame;
  Timer? _frameSaveTimer;

  /// Hydrate from disk and restore the native window frame. Called once
  /// at startup; failures fall back to defaults so a corrupt prefs file
  /// never blocks launch.
  Future<void> hydrate() async {
    final prefs = await _store.load();
    final brightnessName = prefs['brightness'];
    if (brightnessName is String) {
      for (final b in AppBrightness.values) {
        if (b.name == brightnessName && b != _brightness) {
          _brightness = b;
          AppColors.setPalette(
            b == AppBrightness.dark ? darkPalette : lightPalette,
          );
          break;
        }
      }
    }

    final frame = prefs['windowFrame'];
    if (frame is Map) {
      _frame = {
        'x': (frame['x'] as num).toDouble(),
        'y': (frame['y'] as num).toDouble(),
        'w': (frame['w'] as num).toDouble(),
        'h': (frame['h'] as num).toDouble(),
      };
      await _window.write(_frame!);
    }

    notifyListeners();
  }

  void setBrightness(AppBrightness value) {
    if (_brightness == value) return;
    _brightness = value;
    AppColors.setPalette(
      value == AppBrightness.dark ? darkPalette : lightPalette,
    );
    unawaited(_persist());
    notifyListeners();
  }

  void toggleBrightness() {
    setBrightness(
      _brightness == AppBrightness.dark
          ? AppBrightness.light
          : AppBrightness.dark,
    );
  }

  /// Read the current native window frame and schedule a debounced save.
  /// Called from a resize / move listener on the AppLifecycleState.
  Future<void> captureWindowFrame() async {
    final frame = await _window.read();
    if (frame == null) return;
    _frame = frame;
    _frameSaveTimer?.cancel();
    _frameSaveTimer = Timer(const Duration(seconds: 1), _persist);
  }

  Future<void> _persist() async {
    await _store.save({
      'brightness': _brightness.name,
      if (_frame != null) 'windowFrame': _frame,
    });
  }

  @override
  void dispose() {
    _frameSaveTimer?.cancel();
    super.dispose();
  }
}
