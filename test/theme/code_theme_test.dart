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

    test('a long source is highlighted in full', () {
      // jsonSpans no longer caps — callers truncate upstream. A long value
      // is tokenized whole and round-trips losslessly.
      final padding = 'x' * 1200;
      final source = '{"k":"$padding"}';
      expect(source.length, greaterThan(1024));
      final spans = jsonSpans(source, base);
      expect(spans, isNotEmpty);
      expect(spansToText(spans), source);
    });
  });
}
