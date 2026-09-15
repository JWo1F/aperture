import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/widgets/code_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TextSpan _span(
  CodeEditorController c, {
  TextStyle style = const TextStyle(fontSize: 12),
}) => c.buildTextSpan(
  context: _FakeContext(),
  style: style,
  withComposing: false,
);

/// Every colour in the span tree, however deeply nested — the highlighter
/// merges class styles onto the base and groups children under styleless
/// parents, so a shallow scan finds nothing.
Set<Color> _colours(InlineSpan span) {
  final out = <Color>{};
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      final c = s.style?.color;
      if (c != null) out.add(c);
      for (final child in s.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(span);
  return out;
}

/// `buildTextSpan` never touches the context; the highlighter works off
/// `text` and the palette alone.
class _FakeContext extends BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppColors.setPalette(darkPalette));

  group('CodeEditorController.buildTextSpan', () {
    test('highlights SQL into classed children', () {
      final c = CodeEditorController(text: 'SELECT 1 FROM t');
      final span = _span(c);
      expect(span.children, isNotEmpty);
      // The keyword must not simply inherit the base style.
      expect(_colours(span), isNotEmpty);
    });

    test('empty text yields an empty span, not a parse', () {
      final c = CodeEditorController(text: '');
      expect(_span(c).text, '');
    });

    test('the same inputs return the identical span object', () {
      // One keystroke reaches this more than once — line metrics, caret
      // visibility, popup anchoring, then paint. Re-parsing the whole
      // document each time is what made typing lag on long scripts.
      final c = CodeEditorController(text: 'SELECT 1');
      expect(_span(c), same(_span(c)));
    });

    test('changed text invalidates the memo', () {
      final c = CodeEditorController(text: 'SELECT 1');
      final first = _span(c);
      c.text = 'SELECT 2';
      expect(_span(c), isNot(same(first)));
    });

    test('a changed base style invalidates the memo', () {
      final c = CodeEditorController(text: 'SELECT 1');
      final first = _span(c, style: const TextStyle(fontSize: 12));
      final second = _span(c, style: const TextStyle(fontSize: 14));
      expect(second, isNot(same(first)));
      expect(second.style?.fontSize, 14);
    });

    test('a palette swap invalidates the memo', () {
      // `apertureCodeStyles` is a live getter, so a cached span would keep
      // painting the previous theme's syntax colours after a toggle.
      AppColors.setPalette(darkPalette);
      final c = CodeEditorController(text: 'SELECT 1');
      final dark = _span(c);
      AppColors.setPalette(lightPalette);
      final light = _span(c);
      expect(light, isNot(same(dark)));

      expect(_colours(light), isNot(_colours(dark)));
    });

    test('a changed language invalidates the memo', () {
      final c = CodeEditorController(text: '{"a": 1}', language: 'json');
      final asJson = _span(c);
      c.language = 'pgsql';
      expect(_span(c), isNot(same(asJson)));
    });
  });
}
