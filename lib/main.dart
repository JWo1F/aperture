import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManipulator.initialize(enableWindowDelegate: true);
  await WindowManipulator.makeTitlebarTransparent();
  await WindowManipulator.enableFullSizeContentView();
  await WindowManipulator.hideTitle();
  runApp(const ApertureApp());
}

class ApertureApp extends StatelessWidget {
  const ApertureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Builder(
        builder: (context) {
          // Subscribe only to the brightness slice so MaterialApp doesn't
          // rebuild on every AppState notification (sidebar drags, log
          // ticks, tab edits, ...). The theme only depends on brightness;
          // everything else propagates through child widgets that watch
          // their own narrow slices.
          final brightness = context.select<AppState, AppBrightness>(
            (s) => s.brightness,
          );
          return MaterialApp(
            title: 'Aperture',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(brightness),
            // Colours are read through the `AppColors` static shim, which
            // Flutter's dependency tracking can't see — swapping the palette
            // wouldn't repaint `const` subtrees or any branch a parent
            // short-circuits. Keying the shell on brightness unmounts the
            // whole tree on a theme switch so every widget rebuilds against
            // the new palette. Workspace state lives in AppState (above
            // MaterialApp) and survives; only transient widget state like
            // scroll offset is reset.
            home: AppShell(key: ValueKey(brightness)),
          );
        },
      ),
    );
  }
}
