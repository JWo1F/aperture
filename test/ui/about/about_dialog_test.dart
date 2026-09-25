import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/about/about_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppColors.setPalette(darkPalette));

  for (final (name, palette) in [
    ('dark', darkPalette),
    ('light', lightPalette),
  ]) {
    testWidgets('names the author and lays out in the $name palette', (
      tester,
    ) async {
      AppColors.setPalette(palette);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAboutAperture(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Aleksandr Ivashkin'), findsOneWidget);
      expect(find.textContaining('© 2026 Aleksandr Ivashkin'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Aleksandr Ivashkin'), findsNothing);
    });
  }
}
