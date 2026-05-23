import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'state/app_store.dart';
import 'state/catalog_controller.dart';
import 'state/event_log.dart';
import 'state/navigation_history.dart';
import 'state/session_controller.dart';
import 'state/tabs_controller.dart';
import 'state/workspace_ui.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManipulator.initialize(enableWindowDelegate: true);
  await WindowManipulator.makeTitlebarTransparent();
  await WindowManipulator.enableFullSizeContentView();
  await WindowManipulator.hideTitle();
  final appState = AppState();
  await appState.load();
  runApp(ApertureApp(appState: appState));
}

class ApertureApp extends StatefulWidget {
  const ApertureApp({super.key, required this.appState});

  final AppState appState;

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
        await widget.appState.flush();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    return MultiProvider(
      providers: [
        Provider<AppState>.value(value: appState),
        ChangeNotifierProvider<AppStore>.value(value: appState.store),
        ChangeNotifierProvider<SessionController>.value(value: appState.session),
        ChangeNotifierProvider<CatalogController>.value(value: appState.catalog),
        ChangeNotifierProvider<TabsController>.value(
          value: appState.tabsController,
        ),
        ChangeNotifierProvider<NavigationHistory>.value(value: appState.history),
        ChangeNotifierProvider<WorkspaceUi>.value(value: appState.ui),
        ChangeNotifierProvider<EventLog>.value(value: appState.eventLog),
      ],
      child: Builder(
        builder: (context) {
          final brightness = context.select<AppStore, AppBrightness>(
            (s) => s.brightness,
          );
          return MaterialApp(
            title: 'Aperture',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(brightness),
            home: AppShell(key: ValueKey(brightness)),
          );
        },
      ),
    );
  }
}
