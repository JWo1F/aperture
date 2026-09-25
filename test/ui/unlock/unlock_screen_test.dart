import 'dart:io';

import 'package:aperture/services/keychain.dart';
import 'package:aperture/state/app_globals.dart';
import 'package:aperture/state/app_state.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/unlock/unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoKeychain extends Keychain {
  @override
  Future<String?> readPassphrase() async => null;

  @override
  Future<bool> writePassphrase(String passphrase) async => true;

  @override
  Future<void> deletePassphrase() async {}
}

void main() {
  final dir = Directory.systemTemp.createTempSync('unlock_screen');
  tearDownAll(() => dir.deleteSync(recursive: true));
  appState = AppState(
    keychain: _NoKeychain(),
    storePath: '${dir.path}/store.sqlite',
  );

  Future<void> pump(WidgetTester tester) async {
    AppColors.setPalette(darkPalette);
    await tester.pumpWidget(const MaterialApp(home: UnlockScreen()));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('first launch asks for a passphrase twice and creates the '
      'store', (tester) async {
    await pump(tester);
    expect(find.text('Protect your settings'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'pw');
    await tester.enterText(fields.at(1), 'other');
    await tester.tap(find.text('Encrypt settings'));
    await tester.pump();
    expect(find.text("The passphrases don't match."), findsOneWidget);
    expect(appState.store.isOpen, isFalse);

    await tester.enterText(fields.at(1), 'pw');
    await tester.tap(find.text('Encrypt settings'));
    // Past the paint-first delay; the key derivation itself is synchronous.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(appState.store.isOpen, isTrue);
    expect(tester.takeException(), isNull);
  });
}
