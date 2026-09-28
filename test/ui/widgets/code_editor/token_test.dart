import 'package:aperture/ui/widgets/code_editor/token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenStart', () {
    test('returns cursor for an empty buffer', () {
      expect(tokenStart('', 0), 0);
    });

    test('returns cursor when the caret sits on whitespace', () {
      expect(tokenStart('SELECT  ', 8), 8);
    });

    test('walks back through letters, digits, and underscore', () {
      expect(tokenStart('SELECT created_at1 FROM', 17), 7);
    });

    test('returns cursor at a token boundary (start of identifier)', () {
      expect(tokenStart('SELECT id', 7), 7);
    });
  });
}
