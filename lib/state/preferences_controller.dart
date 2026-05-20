import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/preferences_store.dart';
import '../theme/app_theme.dart';

/// Global app preferences: theme brightness, and (later) anything else that
/// belongs neither to a connection nor to a tab.
class PreferencesController extends ChangeNotifier {
  PreferencesController({PreferencesStore? store})
      : _store = store ?? PreferencesStore();

  final PreferencesStore _store;

  AppBrightness _brightness = AppBrightness.dark;
  AppBrightness get brightness => _brightness;

  /// Hydrate from disk. Called once at startup; failures fall back to the
  /// default palette so a corrupt preferences file never blocks launch.
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
          notifyListeners();
          return;
        }
      }
    }
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

  Future<void> _persist() async {
    await _store.save({'brightness': _brightness.name});
  }
}
