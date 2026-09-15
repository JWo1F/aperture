import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import 'state/app_globals.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell/app_shell.dart';
import 'ui/app_shell/quit_confirm.dart';
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
  _installErrorHandlers(state);
  runApp(const ApertureApp());
}

/// Route failures that escape a framework callback or an unawaited future
/// into the activity log. Flutter's default handler prints to the debug
/// console, which nobody is reading in a release build — a query that dies
/// on a bad cast would otherwise look like a UI that simply stopped.
void _installErrorHandlers(AppState state) {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    presentError?.call(details);
    state.reportUncaught(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    state.reportUncaught(error, stack);
    return true;
  };
}

class ApertureApp extends StatefulWidget {
  const ApertureApp({super.key});

  @override
  State<ApertureApp> createState() => _ApertureAppState();
}

class _ApertureAppState extends State<ApertureApp> {
  late final AppLifecycleListener _lifecycle;

  /// The dialog in [_onExitRequested] needs a context below [MaterialApp]'s
  /// navigator; this State sits above it.
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
  }

  Future<AppExitResponse> _onExitRequested() async {
    final pending = appState.tabsController.unappliedEditCount;
    final context = _navigator.currentContext;
    if (pending > 0 && context != null) {
      if (!await confirmQuitWithPendingEdits(context, pending)) {
        return AppExitResponse.cancel;
      }
    }
    await appState.flush();
    return AppExitResponse.exit;
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
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(brightness),
        home: AppShell(key: ValueKey(brightness)),
      ),
    );
  }
}
