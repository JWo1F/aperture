import 'package:aperture/models/connection_config.dart';
import 'package:aperture/theme/app_theme.dart';
import 'package:aperture/ui/app_shell/welcome/connection_cards.dart';
import 'package:aperture/ui/app_shell/welcome/hero.dart';
import 'package:aperture/ui/app_shell/welcome/states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lays every welcome-screen piece out at phone, split-view and full widths
/// in both palettes; a RenderFlex overflow surfaces as a test exception.
void main() {
  tearDown(() => AppColors.setPalette(darkPalette));

  final c = ConnectionConfig(
    id: 'a',
    name: 'Production analytics warehouse replica',
    host: 'db.example.internal',
    database: 'analytics',
    username: 'readonly_user',
    readOnly: true,
    lastConnectedAt: DateTime.now().subtract(const Duration(hours: 3)),
  );
  for (final width in [360.0, 600.0, 960.0]) {
    for (final pal in [darkPalette, lightPalette]) {
      testWidgets('lays out at $width px without overflow', (tester) async {
        AppColors.setPalette(pal);
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WelcomeHero(
                      onSearch: () {},
                      onNew: () {},
                      stacked: width < 640,
                    ),
                    ResumeCard(
                      config: c,
                      onConnect: () {},
                      onEdit: () {},
                      onDelete: () {},
                      compact: width < 560,
                    ),
                    SizedBox(
                      width: width / 3,
                      child: ConnectionCard(
                        config: c,
                        onConnect: () {},
                        onEdit: () {},
                        onDelete: () {},
                      ),
                    ),
                    const WelcomePreparing(
                      connecting: true,
                      connectionName: 'x',
                    ),
                    const WelcomeError(
                      message: 'password authentication failed',
                    ),
                    WelcomeEmpty(onNew: () {}),
                    WelcomeFooter(onAbout: () {}),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
