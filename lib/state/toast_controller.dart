import 'package:flutter/foundation.dart';

enum ToastSeverity { info, success, warning, error }

/// One floating notification. Identity is the [id] string — the overlay
/// keys cards on it so a particular card preserves its enter/exit
/// animation state across rebuilds even as the list around it changes.
@immutable
class Toast {
  const Toast({
    required this.id,
    required this.severity,
    required this.message,
    this.title,
    this.duration,
  });

  final String id;
  final ToastSeverity severity;
  final String message;

  /// Optional bold first line. Null = single-line body only.
  final String? title;

  /// Auto-dismiss timer the overlay's card schedules on mount. Null means
  /// sticky — the user must close it manually. Errors default to sticky.
  final Duration? duration;
}

/// Floating-toast queue, stacked in the bottom-right corner.
///
/// The controller owns the list of live toasts; the card widgets own
/// their own animation + auto-dismiss timers and call [dismiss] when
/// their exit animation finishes.
class ToastController extends ChangeNotifier {
  final List<Toast> _toasts = [];
  int _seq = 0;

  List<Toast> get toasts => List.unmodifiable(_toasts);

  /// Push a new toast and return its id. Default durations: 3s for info /
  /// success, 5s for warning, sticky for error. Pass [duration] explicitly
  /// to override (Duration.zero is treated as sticky).
  String show({
    required ToastSeverity severity,
    required String message,
    String? title,
    Duration? duration,
  }) {
    final id = '${++_seq}';
    final resolved = _resolveDuration(severity, duration);
    _toasts.add(
      Toast(
        id: id,
        severity: severity,
        message: message,
        title: title,
        duration: resolved,
      ),
    );
    notifyListeners();
    return id;
  }

  String info(String message, {String? title, Duration? duration}) =>
      show(severity: ToastSeverity.info, message: message, title: title, duration: duration);

  String success(String message, {String? title, Duration? duration}) =>
      show(severity: ToastSeverity.success, message: message, title: title, duration: duration);

  String warning(String message, {String? title, Duration? duration}) =>
      show(severity: ToastSeverity.warning, message: message, title: title, duration: duration);

  String error(String message, {String? title, Duration? duration}) =>
      show(severity: ToastSeverity.error, message: message, title: title, duration: duration);

  void dismiss(String id) {
    final i = _toasts.indexWhere((t) => t.id == id);
    if (i == -1) return;
    _toasts.removeAt(i);
    notifyListeners();
  }

  void clear() {
    if (_toasts.isEmpty) return;
    _toasts.clear();
    notifyListeners();
  }

  static Duration? _resolveDuration(ToastSeverity severity, Duration? explicit) {
    if (explicit != null) {
      return explicit == Duration.zero ? null : explicit;
    }
    return switch (severity) {
      ToastSeverity.info => const Duration(seconds: 3),
      ToastSeverity.success => const Duration(seconds: 3),
      ToastSeverity.warning => const Duration(seconds: 5),
      ToastSeverity.error => null,
    };
  }
}
