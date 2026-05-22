import 'package:dbv/ui/widgets/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the [CodeEditor] with real key events to verify Tab indentation,
/// Enter auto-indent, and Tab-to-accept of an autocomplete suggestion.
void main() {
  Future<TextEditingController> pumpEditor(
    WidgetTester tester, {
    required String text,
    CodeSuggestProvider? suggest,
  }) async {
    final controller = TextEditingController(text: text);
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            focusNode: focus,
            suggest: suggest,
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    return controller;
  }

  Future<void> openPopup(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Tab inserts a two-space soft tab at the caret', (tester) async {
    final c = await pumpEditor(tester, text: 'SELECT');
    c.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(c.text, 'SELECT  ');
    expect(c.selection.baseOffset, 8);
  });

  testWidgets('Tab replaces a single-line selection with a soft tab', (
    tester,
  ) async {
    final c = await pumpEditor(tester, text: 'SELECT xyz');
    c.selection = const TextSelection(baseOffset: 7, extentOffset: 10);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(c.text, 'SELECT   ');
  });

  testWidgets('Tab indents every line of a multi-line selection', (
    tester,
  ) async {
    final c = await pumpEditor(tester, text: 'one\ntwo\nthree');
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 13);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(c.text, '  one\n  two\n  three');
  });

  testWidgets('Shift-Tab dedents the current line', (tester) async {
    final c = await pumpEditor(tester, text: '    SELECT');
    c.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(c.text, '  SELECT');
  });

  testWidgets('Enter copies the current line indentation onto the new line', (
    tester,
  ) async {
    final c = await pumpEditor(tester, text: '  name = 1');
    c.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(c.text, '  name = 1\n  ');
    expect(c.selection.baseOffset, 13);
  });

  testWidgets('Tab accepts the highlighted suggestion', (tester) async {
    final c = await pumpEditor(
      tester,
      text: 'SEL',
      suggest: (_) => const [
        CodeSuggestion(label: 'SELECT', insertText: 'SELECT'),
      ],
    );
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await openPopup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(c.text, 'SELECT');
  });

  testWidgets('Enter no longer accepts — it inserts a newline instead', (
    tester,
  ) async {
    final c = await pumpEditor(
      tester,
      text: 'SEL',
      suggest: (_) => const [
        CodeSuggestion(label: 'SELECT', insertText: 'SELECT'),
      ],
    );
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await openPopup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(c.text, 'SEL\n');
  });
}
