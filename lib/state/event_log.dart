import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/log_event.dart';

/// Ring-buffer log of every meaningful thing the app did during this
/// session: queries run, edits applied, connection lifecycle events,
/// errors. The most recent [bufferSize] entries are held in memory; every
/// entry is also appended to a per-day NDJSON file under Application
/// Support so the user has an audit trail across launches.
///
/// The log is read-only for UI consumers; mutators live on this class
/// so all events flow through one place that handles both the in-memory
/// ring and the file append.
class EventLog extends ChangeNotifier {
  EventLog({this.bufferSize = 500});

  final int bufferSize;
  final List<LogEvent> _events = [];

  /// Set true once the user has explicitly opened the log pane. We hold a
  /// notify-aware bool so the toolbar's log button can render an "unread"
  /// dot otherwise.
  bool _visible = false;
  int _unread = 0;

  List<LogEvent> get events => List.unmodifiable(_events);

  bool get isVisible => _visible;

  int get unreadCount => _unread;

  IOSink? _fileSink;
  String? _fileDay;
  bool _persisting = true;

  /// Disable NDJSON persistence (tests).
  void disablePersistence() {
    _persisting = false;
    _fileSink?.close();
    _fileSink = null;
    _fileDay = null;
  }

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
    if (_persisting) unawaited(_persist(event));
  }

  Future<void> _persist(LogEvent event) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logsDir = Directory('${dir.path}/log');
      if (!await logsDir.exists()) await logsDir.create(recursive: true);
      final day = _today();
      if (_fileDay != day) {
        await _fileSink?.close();
        _fileSink = File(
          '${logsDir.path}/$day.ndjson',
        ).openWrite(mode: FileMode.append);
        _fileDay = day;
      }
      _fileSink!.writeln(jsonEncode(event.toJson()));
      await _fileSink!.flush();
    } catch (e, st) {
      developer.log(
        'event log persistence failed',
        name: 'dbv.log',
        error: e,
        stackTrace: st,
      );
    }
  }

  String _today() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  @override
  void dispose() {
    unawaited(_fileSink?.close());
    super.dispose();
  }
}
