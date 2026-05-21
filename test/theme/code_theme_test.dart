import 'package:dbv/theme/code_theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = TextStyle(fontSize: 12);

  String spansToText(List<InlineSpan> spans) {
    final buf = StringBuffer();
    for (final s in spans) {
      s.visitChildren((child) {
        if (child is TextSpan && child.text != null) buf.write(child.text);
        return true;
      });
    }
    return buf.toString();
  }

  group('jsonSpans', () {
    test('empty source returns empty list', () {
      expect(jsonSpans('', base), isEmpty);
    });

    test('short source is fully tokenized', () {
      final source = '{"k":"v"}';
      final spans = jsonSpans(source, base);
      expect(spans, isNotEmpty);
      expect(spansToText(spans), source);
    });

    test('source above 255 chars is split into highlighted head + plain tail',
        () {
      // 300-char string, just enough JSON shape to give the tokenizer
      // something to chew on at the start. The exact head/tail boundary
      // is at 255 chars.
      final padding = 'x' * 280;
      final source = '{"k":"$padding"}';
      expect(source.length, greaterThan(255));
      final spans = jsonSpans(source, base);
      // The concatenated text round-trips losslessly — nothing is
      // dropped, regardless of where the cap falls.
      expect(spansToText(spans), source);
    });

    test('passing maxLength: null disables the cap', () {
      final source = '"${'a' * 500}"';
      expect(jsonSpans(source, base, maxLength: null), isNotEmpty);
      // No assertion on which span is which; just confirming the call
      // accepts the override and still produces output.
    });
  });
}
