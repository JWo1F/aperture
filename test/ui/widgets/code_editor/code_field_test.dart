import 'package:aperture/ui/widgets/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the [CodeField] with real key events through its autocomplete
/// popup and submit path.
void main() {
  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    required String text,
    CodeSuggestProvider? suggest,
    VoidCallback? onSubmit,
  }) async {
    final controller = TextEditingController(text: text);
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeField(
            controller: controller,
            focusNode: focus,
            suggest: suggest,
            onSubmit: onSubmit,
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

  List<CodeSuggestion> select(SuggestRequest _) => const [
    CodeSuggestion(label: 'SELECT', insertText: 'SELECT'),
  ];

  testWidgets('Tab accepts the highlighted suggestion', (tester) async {
    final c = await pumpField(tester, text: 'SEL', suggest: select);
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await openPopup(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(c.text, 'SELECT');
  });

  testWidgets('Enter closes the popup and submits the text as typed', (
    tester,
  ) async {
    var submitted = 0;
    final c = await pumpField(
      tester,
      text: 'SEL',
      suggest: select,
      onSubmit: () => submitted++,
    );
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await openPopup(tester);
    expect(find.text('SELECT'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(c.text, 'SEL');
    expect(submitted, 1);
    expect(find.text('SELECT'), findsNothing);
  });

  testWidgets('the hint shows only while the field is empty', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeField(controller: controller, hintText: 'type here'),
        ),
      ),
    );
    expect(find.text('type here'), findsOneWidget);
    controller.text = 'x';
    await tester.pump();
    expect(find.text('type here'), findsNothing);
  });
}
