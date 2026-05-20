import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbv/main.dart';

void main() {
  testWidgets('app boots to the welcome panel', (tester) async {
    // Toolbar is tuned for a typical desktop window — the default Flutter
    // test surface (800×600) is narrower than any real dbv window. Bump it
    // so we exercise the same layout the user actually sees.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DbvApp());
    await tester.pump();

    expect(find.text('New Connection'), findsWidgets);
  });
}
