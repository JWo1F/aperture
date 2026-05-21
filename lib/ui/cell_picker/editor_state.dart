import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../state/workspace_tab.dart';

/// What `Panel` owns per kind. Each subclass holds the live editor value
/// plus its baseline so `isDirty` and the save dispatch need no type
/// switch beyond the sealed switch.
sealed class EditorState {
  bool get isDirty;
  void disposeResources() {}
}

final class TextEditorState extends EditorState {
  TextEditorState({
    required this.controller,
    required this.baseline,
    required this.isJson,
  });

  final TextEditingController controller;
  final String baseline;
  final bool isJson;
  String? jsonError;

  @override
  bool get isDirty => controller.text != baseline;

  @override
  void disposeResources() => controller.dispose();
}

final class BoolEditorState extends EditorState {
  BoolEditorState({required this.value, required this.baseline});

  bool? value;
  final bool? baseline;

  @override
  bool get isDirty => value != baseline;
}

final class MomentEditorState extends EditorState {
  MomentEditorState({
    required this.value,
    required this.baselineValue,
    required this.tz,
    required this.baselineTz,
    required this.withTz,
  });

  DateTime value;
  final DateTime baselineValue;
  String tz;
  final String baselineTz;
  final bool withTz;

  @override
  bool get isDirty =>
      value != baselineValue || (withTz && tz != baselineTz);
}

// --- Initial state extraction -----------------------------------------

String initialText(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) return pending.value ?? '';
  if (pending is CellDefault) return '';
  if (raw == null) return '';
  if (raw is Map || raw is List) {
    try {
      return const JsonEncoder.withIndent('  ').convert(raw);
    } catch (_) {
      return raw.toString();
    }
  }
  if (raw is Uint8List) return '';
  if (raw is DateTime) return raw.toIso8601String();
  return raw.toString();
}

bool? initialBool(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) {
    if (pending.value == null) return null;
    final v = pending.value!.toLowerCase();
    if (v == 'true' || v == 't' || v == '1') return true;
    if (v == 'false' || v == 'f' || v == '0') return false;
    return null;
  }
  if (raw is bool) return raw;
  return null;
}

DateTime initialMoment(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) {
    final s = pending.value;
    if (s != null && s.isNotEmpty) {
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed;
      // Try time-only "HH:MM:SS(.mmm)?(<space>tz)?"
      final tm = RegExp(
        r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.(\d{1,3}))?)?',
      ).firstMatch(s);
      if (tm != null) {
        final h = int.parse(tm.group(1)!);
        final m = int.parse(tm.group(2)!);
        final sec = int.parse(tm.group(3) ?? '0');
        final msStr = tm.group(4);
        final ms = msStr == null
            ? 0
            : int.parse(msStr.padRight(3, '0').substring(0, 3));
        return DateTime(1970, 1, 1, h, m, sec, ms);
      }
    }
  }
  if (raw is DateTime) return raw;
  if (raw is String) {
    final p = DateTime.tryParse(raw);
    if (p != null) return p;
  }
  return DateTime.now();
}

/// Extracts a trailing timezone hint from a pending literal so re-opening a
/// staged edit pre-fills the TZ field. Falls back to empty (server default).
String initialTz(Object? raw, CellEditValue? pending) {
  if (pending is CellLiteral) {
    final s = pending.value;
    if (s != null) {
      final m = RegExp(
        r'(?:[+-]\d{2}(?::?\d{2})?|\b[A-Z][A-Za-z_/+\-0-9]{1,})$',
      ).firstMatch(s.trim());
      if (m != null) {
        final hit = m.group(0)!;
        // Don't mistake the date's first 4-digit year for a tz.
        if (hit.length >= 2 && !RegExp(r'^\d').hasMatch(hit)) return hit;
      }
    }
  }
  return '';
}
