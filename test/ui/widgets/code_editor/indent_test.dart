import 'package:dbv/ui/widgets/code_editor/indent.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the pure indent layer. These talk to no widgets and no
/// controller — every function takes `(text, selection)` and returns the
/// new `(text, selection)`, so the editing logic is verifiable without
/// pumping a TextField.
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

  group('handleTab — collapsed and single-line selection', () {
    test('collapsed caret inserts a two-space soft tab', () {
      final r = handleTab(
        text: 'SELECT',
        selection: const TextSelection.collapsed(offset: 6),
        dedent: false,
      );
      expect(r.text, 'SELECT  ');
      expect(r.selection, const TextSelection.collapsed(offset: 8));
    });

    test('single-line selection is replaced by a soft tab', () {
      final r = handleTab(
        text: 'SELECT xyz',
        selection: const TextSelection(baseOffset: 7, extentOffset: 10),
        dedent: false,
      );
      expect(r.text, 'SELECT   ');
      expect(r.selection, const TextSelection.collapsed(offset: 9));
    });

    test('multi-line selection delegates to shiftLines (indent)', () {
      final r = handleTab(
        text: 'one\ntwo\nthree',
        selection: const TextSelection(baseOffset: 0, extentOffset: 13),
        dedent: false,
      );
      expect(r.text, '  one\n  two\n  three');
      // selStart shifts by firstDelta (+2), selEnd by totalDelta (+6).
      expect(r.selection.baseOffset, 2);
      expect(r.selection.extentOffset, 19);
    });
  });

  group('shiftLines — indent', () {
    test('indents every line touched by the selection', () {
      final r = shiftLines(
        text: 'one\ntwo\nthree',
        selStart: 0,
        selEnd: 13,
        dedent: false,
      );
      expect(r.text, '  one\n  two\n  three');
    });

    test('caret on a single line still indents that whole line', () {
      // Shift-Tab on a caret triggers shiftLines with dedent=true, but the
      // same path is reached for indent when the selection covers a line
      // boundary. Verify the indent variant on a collapsed selection too.
      final r = shiftLines(
        text: 'one\ntwo',
        selStart: 2,
        selEnd: 2,
        dedent: false,
      );
      expect(r.text, '  one\ntwo');
    });
  });

  group('shiftLines — dedent', () {
    test('strips two leading spaces from every touched line', () {
      final r = shiftLines(
        text: '  one\n  two\n  three',
        selStart: 0,
        selEnd: 19,
        dedent: true,
      );
      expect(r.text, 'one\ntwo\nthree');
    });

    test('strips a single leading tab character', () {
      final r = shiftLines(
        text: '\tone',
        selStart: 0,
        selEnd: 4,
        dedent: true,
      );
      expect(r.text, 'one');
    });

    test('strips only the indent that exists when fewer than two spaces', () {
      final r = shiftLines(
        text: ' one',
        selStart: 0,
        selEnd: 4,
        dedent: true,
      );
      expect(r.text, 'one');
    });

    test('no-op when there is nothing to strip leaves the buffer untouched', () {
      final r = shiftLines(
        text: 'one\ntwo',
        selStart: 0,
        selEnd: 7,
        dedent: true,
      );
      expect(r.text, 'one\ntwo');
      expect(r.selection.baseOffset, 0);
      expect(r.selection.extentOffset, 7);
    });
  });

  group('shiftLines — boundary (selection ending at a newline)', () {
    // These pin the current trailing-newline semantics. shiftLines walks
    // scanEnd back by one when it lands directly on a '\n' — so a
    // selection that ends *exactly at* a newline character (just past it)
    // does NOT pull the next line into the shift. The visual caret sits
    // at the start of the next line, which many editors interpret as
    // "include that next line too" — this implementation does not. If
    // the policy ever changes, these tests should fail loudly so the
    // change is deliberate.

    test('selection ending exactly at the newline only shifts the first line', () {
      // 'one\ntwo' is indexed 0..6; index 3 is '\n', selecting (0, 4)
      // means the visual caret is at the start of line 2.
      final r = shiftLines(
        text: 'one\ntwo',
        selStart: 0,
        selEnd: 4,
        dedent: false,
      );
      expect(r.text, '  one\ntwo');
    });

    test('selection ending one char into the next line shifts both lines', () {
      final r = shiftLines(
        text: 'one\ntwo',
        selStart: 0,
        selEnd: 5,
        dedent: false,
      );
      expect(r.text, '  one\n  two');
    });

    test('selection ending right before the newline shifts only line one', () {
      final r = shiftLines(
        text: 'one\ntwo',
        selStart: 0,
        selEnd: 3,
        dedent: false,
      );
      expect(r.text, '  one\ntwo');
    });
  });

  group('handleNewlineInsert', () {
    test('inserts a bare newline at the end of an unindented line', () {
      final r = handleNewlineInsert(
        text: 'SELECT',
        selection: const TextSelection.collapsed(offset: 6),
      );
      expect(r.text, 'SELECT\n');
      expect(r.selection, const TextSelection.collapsed(offset: 7));
    });

    test('preserves indent when pressing Enter at the end of an indented line', () {
      final r = handleNewlineInsert(
        text: '  name = 1',
        selection: const TextSelection.collapsed(offset: 10),
      );
      expect(r.text, '  name = 1\n  ');
      expect(r.selection, const TextSelection.collapsed(offset: 13));
    });

    test('mid-line Enter inherits the previous line indent', () {
      final r = handleNewlineInsert(
        text: '    foo bar',
        selection: const TextSelection.collapsed(offset: 7),
      );
      // Split between "foo" and " bar"; the new line inherits the 4-space
      // indent of the previous line.
      expect(r.text, '    foo\n     bar');
      expect(r.selection, const TextSelection.collapsed(offset: 12));
    });

    test('Enter inside the leading whitespace of an indented line', () {
      // Pressing Enter inside the indent itself copies the whitespace
      // measured from the line start *up to the caret*, since the scan
      // stops at the caret.
      final r = handleNewlineInsert(
        text: '    foo',
        selection: const TextSelection.collapsed(offset: 2),
      );
      expect(r.text, '  \n    foo');
      expect(r.selection, const TextSelection.collapsed(offset: 5));
    });
  });
}
