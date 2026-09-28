import 'dart:io';

import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/widgets/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final bytes = File(
      'assets/fonts/JetBrainsMono-Regular.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      AppTheme.monoFamily,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets('long wrapped lines scroll in one scroll view', (tester) async {
    // Line lengths that sweep across the wrap edge: a field that wraps any
    // of them a row earlier than the editor measured outgrows its scroll
    // content and scrolls on its own, hiding the last lines.
    final text = [for (var i = 0; i < 300; i++) 'x' * i].join('\n');
    final controller = CodeEditorController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 540,
            height: 270,
            child: CodeEditor(controller: controller, showLineNumbers: true),
          ),
        ),
      ),
    );
    await tester.pump();

    final scrolling = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((s) => s.position.maxScrollExtent > 0);
    expect(scrolling, hasLength(1));
  });
}
