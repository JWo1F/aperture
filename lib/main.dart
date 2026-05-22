import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'state/catalog_controller.dart';
import 'state/connection_registry.dart';
import 'state/event_log.dart';
import 'state/master_passphrase.dart';
import 'state/navigation_history.dart';
import 'state/per_connection_store.dart';
import 'state/preferences_controller.dart';
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
  runApp(const ApertureApp());
}

class ApertureApp extends StatelessWidget {
  const ApertureApp({super.key});

  @override
  Widget build(BuildContext context) {
    // AppState owns and creates the focused controllers and disposes them.
    // The child providers below republish those same instances with
    // `.value`, so widgets can watch the one controller they depend on and
    // rebuild granularly. `.value` providers never dispose what they hold —
    // disposal stays with AppState.
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Builder(
        builder: (context) {
          final appState = context.read<AppState>();
          return MultiProvider(
            providers: [
              ChangeNotifierProvider<PreferencesController>.value(
                value: appState.preferences,
              ),
              ChangeNotifierProvider<MasterPassphrase>.value(
                value: appState.masterPassphrase,
              ),
              ChangeNotifierProvider<ConnectionRegistry>.value(
                value: appState.registry,
              ),
              ChangeNotifierProvider<SessionController>.value(
                value: appState.session,
              ),
              ChangeNotifierProvider<CatalogController>.value(
                value: appState.catalog,
              ),
              ChangeNotifierProvider<PerConnectionStore>.value(
                value: appState.perConnection,
              ),
              ChangeNotifierProvider<TabsController>.value(
                value: appState.tabsController,
              ),
              ChangeNotifierProvider<NavigationHistory>.value(
                value: appState.history,
              ),
              ChangeNotifierProvider<WorkspaceUi>.value(value: appState.ui),
              ChangeNotifierProvider<EventLog>.value(value: appState.eventLog),
            ],
            child: Builder(
              builder: (context) {
                // Subscribe only to the brightness slice so MaterialApp
                // doesn't rebuild on every preference notification (sidebar
                // drags, pane resizes). The theme only depends on brightness;
                // everything else propagates through child widgets that
                // watch their own narrow slices.
                final brightness = context
                    .select<PreferencesController, AppBrightness>(
                      (p) => p.brightness,
                    );
                return MaterialApp(
                  title: 'Aperture',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.build(brightness),
                  // Colours are read through the `AppColors` static shim,
                  // which Flutter's dependency tracking can't see — swapping
                  // the palette wouldn't repaint `const` subtrees or any
                  // branch a parent short-circuits. Keying the shell on
                  // brightness unmounts the whole tree on a theme switch so
                  // every widget rebuilds against the new palette. Workspace
                  // state lives in the controllers (above MaterialApp) and
                  // survives; only transient widget state like scroll offset
                  // is reset.
                  home: AppShell(key: ValueKey(brightness)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
