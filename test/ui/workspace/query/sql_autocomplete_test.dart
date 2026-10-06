import 'package:aperture/ui/widgets/code_editor/suggestions/suggestion.dart';
import 'package:aperture/ui/workspace/query/sql_autocomplete.dart';
import 'package:aperture/ui/workspace/query/sql_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// re_editor listens to delta input only; [TestTextInput] sends whole
/// values, which it ignores.
Future<void> _typeDelta(
  WidgetTester tester, {
  required String oldText,
  required String insert,
  required int at,
}) async {
  final client =
      tester.testTextInput.log
              .lastWhere((c) => c.method == 'TextInput.setClient')
              .arguments[0]
          as int;
  final caret = at + insert.length;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.textInput.name,
    SystemChannels.textInput.codec.encodeMethodCall(
      MethodCall('TextInputClient.updateEditingStateWithDeltas', [
        client,
        {
          'deltas': [
            {
              'oldText': oldText,
              'deltaText': insert,
              'deltaStart': at,
              'deltaEnd': at,
              'selectionBase': caret,
              'selectionExtent': caret,
              'selectionAffinity': 'TextAffinity.downstream',
              'selectionIsDirectional': false,
              'composingBase': -1,
              'composingExtent': -1,
            },
          ],
        },
      ]),
    ),
    (_) {},
  );
}

void main() {
  test('flatOffset joins lines with a newline', () {
    final c = CodeLineEditingController.fromText('ab\ncde\n\nf');
    addTearDown(c.dispose);
    expect(
      flatOffset(c.codeLines, const CodeLinePosition(index: 0, offset: 1)),
      1,
    );
    expect(
      flatOffset(c.codeLines, const CodeLinePosition(index: 1, offset: 0)),
      3,
    );
    expect(
      flatOffset(c.codeLines, const CodeLinePosition(index: 3, offset: 1)),
      9,
    );
  });

  testWidgets(
    'typing opens the engine suggestions and picking one inserts it',
    (tester) async {
      // re_editor caches the platform in top-level finals on first read, and
      // takes its mobile path on the test's default Android.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final controller = CodeLineEditingController.fromText('select 1;\nsel');
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      SuggestRequest? seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodeAutocomplete(
              viewBuilder: (context, notifier, onSelected) =>
                  SqlAutocompleteView(
                    notifier: notifier,
                    onSelected: onSelected,
                  ),
              promptsBuilder: SqlPromptsBuilder(
                controller: controller,
                suggest: (req) {
                  seen = req;
                  return req.token.isEmpty
                      ? const []
                      : const [
                          CodeSuggestion(label: 'SELECT', insertText: 'SELECT'),
                          CodeSuggestion(label: 'SET', insertText: 'SET'),
                        ];
                },
              ),
              child: CodeEditor(controller: controller, focusNode: focus),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 3,
      );
      await tester.pump();

      await _typeDelta(tester, oldText: 'sel', insert: 'e', at: 3);
      // Lay the edit out before re_editor's 50 ms prompt delay fires, as a
      // real frame would; `pump(duration)` runs timers before the frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(seen?.token, 'sele');
      expect(seen?.cursor, 14);
      expect(find.text('SELECT'), findsOneWidget);

      await tester.tap(find.text('SELECT'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.text, 'select 1;\nSELECT');
      expect(controller.selection.extent.offset, 6);
      expect(find.text('SET'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Tab accepts a prompt, Enter breaks the line', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = CodeLineEditingController.fromText('sel');
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SqlEditor(
            controller: controller,
            focusNode: focus,
            bands: const [],
            gutterActions: const {},
            suggest: (req) => req.token.isEmpty
                ? const []
                : const [CodeSuggestion(label: 'SELECT', insertText: 'SELECT')],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );
    await tester.pump();

    Future<void> type(String oldText, String insert, int at) async {
      await _typeDelta(tester, oldText: oldText, insert: insert, at: at);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SELECT'), findsOneWidget);
    }

    await type('sel', 'e', 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.text, 'sele\n');
    expect(find.text('SELECT'), findsNothing);

    await type('', 's', 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.text, 'sele\nSELECT');
    expect(find.text('SELECT'), findsNothing);
    expect(controller.selection.extent.offset, 6);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, isNot('sele\nSELECT'));
    expect(controller.text, startsWith('sele\n'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    debugDefaultTargetPlatformOverride = null;
  });
}
