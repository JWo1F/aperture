import 'package:flutter/foundation.dart';

import '../models/log_event.dart';

/// Ring-buffer log of every meaningful thing the app did during this
/// session: queries run, edits applied, connection lifecycle events,
/// errors. The most recent [bufferSize] entries are held in memory and
/// dropped when the app exits.
class EventLog extends ChangeNotifier {
  EventLog({this.bufferSize = 500});

  final int bufferSize;
  final List<LogEvent> _events = [];

  bool _visible = false;
  int _unread = 0;

  List<LogEvent> get events => List.unmodifiable(_events);

  bool get isVisible => _visible;

  int get unreadCount => _unread;

  void toggleVisible() {
    _visible = !_visible;
    if (_visible) _unread = 0;
    notifyListeners();
  }

  void setVisible(bool v) {
    if (v == _visible) return;
    _visible = v;
    if (v) _unread = 0;
    notifyListeners();
  }

  void add(LogEvent event) {
    _events.add(event);
    if (_events.length > bufferSize) {
      _events.removeRange(0, _events.length - bufferSize);
    }
    if (!_visible) _unread++;
    notifyListeners();
  }
}
