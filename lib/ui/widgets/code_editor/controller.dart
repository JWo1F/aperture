import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:highlight/languages/json.dart' as lang_json;
import 'package:highlight/languages/pgsql.dart' as lang_pgsql;

import '../../../theme/app_theme.dart';
import '../../../theme/code_theme.dart';

/// `TextEditingController` that returns a highlight-tinted `TextSpan` tree
/// using a registered language grammar from the `highlight` package and the
/// shared [apertureCodeStyles] theme map.
class CodeEditorController extends TextEditingController {
  CodeEditorController({super.text, this.language = 'pgsql'}) {
    _registerLanguage(language);
  }

  /// Highlight language name (`pgsql`, `json`, …). Override and call
  /// [notifyListeners] to repaint with a new grammar.
  String language;

  String? _parsedText;
  String? _parsedLanguage;
  List<Node>? _parsedNodes;

  String? _cachedText;
  String? _cachedLanguage;
  TextStyle? _cachedBase;
  AppBrightness? _cachedBrightness;
  TextSpan? _cachedSpan;

  /// Memoised on everything the result depends on.
  ///
  /// `highlight.parse` walks the whole document, and a single keystroke
  /// reaches this more than once: the editor measures line metrics, then
  /// keeps the caret visible, then re-anchors the suggestion popup, then
  /// the `TextField` paints. On a few-hundred-line script that was four
  /// full parses and two full layouts per character. The palette is part
  /// of the key because `apertureCodeStyles` is a live getter — the spans
  /// have to be rebuilt after a theme swap.
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final brightness = AppColors.brightness;
    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedLanguage == language &&
        _cachedBase == base &&
        _cachedBrightness == brightness) {
      return _cachedSpan!;
    }
    final span = text.isEmpty
        ? TextSpan(text: '', style: base)
        : TextSpan(
            style: base,
            children: highlightNodesToSpans(_nodes(), base, apertureCodeStyles),
          );
    _cachedText = text;
    _cachedLanguage = language;
    _cachedBase = base;
    _cachedBrightness = brightness;
    _cachedSpan = span;
    return span;
  }

  List<Node> _nodes() {
    if (_parsedNodes == null ||
        _parsedText != text ||
        _parsedLanguage != language) {
      _parsedNodes = highlight.parse(text, language: language).nodes ?? [];
      _parsedText = text;
      _parsedLanguage = language;
    }
    return _parsedNodes!;
  }

  /// Parses the current text on a background isolate, so the first
  /// `buildTextSpan` finds the grammar walk already done. Only the parse
  /// moves: laying the spans out is still the UI thread's.
  Future<void> parseInBackground() async {
    final text = this.text;
    final language = this.language;
    final nodes = await _parseOnIsolate(text, language);
    if (this.text != text || this.language != language) return;
    _parsedText = text;
    _parsedLanguage = language;
    _parsedNodes = nodes;
  }
}

// Top-level so the isolate closure captures only its two arguments; one
// built inside a method would carry `this` and everything reachable from it.
Future<List<Node>> _parseOnIsolate(String text, String language) =>
    Isolate.run(() {
      _registerLanguage(language);
      return highlight.parse(text, language: language).nodes ?? <Node>[];
    });

final _registeredLanguages = <String>{};

void _registerLanguage(String name) {
  if (!_registeredLanguages.add(name)) return;
  switch (name) {
    case 'pgsql':
      highlight.registerLanguage('pgsql', lang_pgsql.pgsql);
    case 'json':
      highlight.registerLanguage('json', lang_json.json);
  }
}
