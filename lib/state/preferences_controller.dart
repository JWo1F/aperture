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

  bool _sidebarVisible = true;
  bool get sidebarVisible => _sidebarVisible;

  // Pane geometry. Fractions are clamped at the call site; widths are clamped
  // here so an out-of-range disk value can't push a pane off-screen.
  static const double sidebarWidthMin = 180;
  static const double sidebarWidthMax = 520;
  static const double sidebarWidthDefault = 248;

  static const double logPanelWidthMin = 240;
  static const double logPanelWidthMax = 720;
  static const double logPanelWidthDefault = 380;

  static const double queryResultsFractionMin = 0.15;
  static const double queryResultsFractionMax = 0.85;
  static const double queryResultsFractionDefault = 0.6;

  double _sidebarWidth = sidebarWidthDefault;
  double get sidebarWidth => _sidebarWidth;

  double _logPanelWidth = logPanelWidthDefault;
  double get logPanelWidth => _logPanelWidth;

  double _queryResultsFraction = queryResultsFractionDefault;
  double get queryResultsFraction => _queryResultsFraction;

  Map<String, double>? _frame;
  Timer? _frameSaveTimer;
  Timer? _paneSaveTimer;

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

    final sidebar = prefs['sidebarVisible'];
    if (sidebar is bool) _sidebarVisible = sidebar;

    final sw = prefs['sidebarWidth'];
    if (sw is num) {
      _sidebarWidth = sw.toDouble().clamp(sidebarWidthMin, sidebarWidthMax);
    }
    final lw = prefs['logPanelWidth'];
    if (lw is num) {
      _logPanelWidth = lw.toDouble().clamp(logPanelWidthMin, logPanelWidthMax);
    }
    final qf = prefs['queryResultsFraction'];
    if (qf is num) {
      _queryResultsFraction = qf
          .toDouble()
          .clamp(queryResultsFractionMin, queryResultsFractionMax);
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

  void toggleSidebar() {
    _sidebarVisible = !_sidebarVisible;
    unawaited(_persist());
    notifyListeners();
  }

  void setSidebarWidth(double width) {
    final clamped = width.clamp(sidebarWidthMin, sidebarWidthMax);
    if (clamped == _sidebarWidth) return;
    _sidebarWidth = clamped;
    _schedulePaneSave();
    notifyListeners();
  }

  void setLogPanelWidth(double width) {
    final clamped = width.clamp(logPanelWidthMin, logPanelWidthMax);
    if (clamped == _logPanelWidth) return;
    _logPanelWidth = clamped;
    _schedulePaneSave();
    notifyListeners();
  }

  void setQueryResultsFraction(double fraction) {
    final clamped = fraction
        .clamp(queryResultsFractionMin, queryResultsFractionMax);
    if (clamped == _queryResultsFraction) return;
    _queryResultsFraction = clamped;
    _schedulePaneSave();
    notifyListeners();
  }

  void _schedulePaneSave() {
    _paneSaveTimer?.cancel();
    _paneSaveTimer = Timer(const Duration(milliseconds: 400), _persist);
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
      'sidebarVisible': _sidebarVisible,
      'sidebarWidth': _sidebarWidth,
      'logPanelWidth': _logPanelWidth,
      'queryResultsFraction': _queryResultsFraction,
      if (_frame != null) 'windowFrame': _frame,
    });
  }

  @override
  void dispose() {
    _frameSaveTimer?.cancel();
    _paneSaveTimer?.cancel();
    super.dispose();
  }
}
