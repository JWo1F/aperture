import 'package:aperture/ui/workspace/query/sql_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('gutter actions sit on their lines and take taps', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText(
      'select 1;\n\nselect\n  2;',
    );
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SqlEditor(
            controller: controller,
            focusNode: focus,
            bands: [
              LineBand(
                startLine: 2,
                endLine: 3,
                color: Colors.blue.withValues(alpha: 0.1),
                spine: Colors.blue,
              ),
            ],
            gutterActions: {
              for (final line in [0, 2])
                line: GutterAction(
                  icon: Text('run$line'),
                  onTap: () => tapped.add(line),
                ),
            },
            suggest: (_) => const [],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final first = tester.getTopLeft(find.text('run0'));
    final third = tester.getTopLeft(find.text('run2'));
    expect(third.dy, greaterThan(first.dy));
    expect(find.text('run1'), findsNothing);

    await tester.tap(find.text('run2'));
    expect(tapped, [2]);

    // re_editor starts the caret blink 100 ms after focus and does not
    // cancel that delay on dispose; let it fire while the editor is alive.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });
}
