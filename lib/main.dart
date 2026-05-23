import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import 'state/app_globals.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell/app_shell.dart';
import 'ui/widgets/value_selector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManipulator.initialize(enableWindowDelegate: true);
  await WindowManipulator.makeTitlebarTransparent();
  await WindowManipulator.enableFullSizeContentView();
  await WindowManipulator.hideTitle();
  final state = AppState();
  await state.load();
  appState = state;
  runApp(const ApertureApp());
}

class ApertureApp extends StatefulWidget {
  const ApertureApp({super.key});

  @override
  State<ApertureApp> createState() => _ApertureAppState();
}

class _ApertureAppState extends State<ApertureApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await appState.flush();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppBrightness>(
      listenable: appState.store,
      selector: () => appState.store.brightness,
      builder: (context, brightness) => MaterialApp(
        title: 'Aperture',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(brightness),
        home: AppShell(key: ValueKey(brightness)),
      ),
    );
  }
}
