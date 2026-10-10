import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_window_utils/macos_window_utils.dart';

import 'state/app_globals.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/about/about_dialog.dart';
import 'ui/app_shell/app_shell.dart';
import 'ui/app_shell/confirm_discard.dart';
import 'ui/unlock/unlock_screen.dart';
import 'ui/widgets/value_selector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    await WindowManipulator.initialize(enableWindowDelegate: true);
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.enableFullSizeContentView();
    await WindowManipulator.hideTitle();
  }
  final state = AppState();
  // Seeded before the store opens so a persisted `auto` resolves against
  // the real OS appearance on the very first paint.
  state.store.setSystemBrightness(_systemBrightness());
  appState = state;
  // A passphrase remembered in the Keychain opens the store before the
  // first frame, so the unlock screen never flashes past.
  await state.unlockFromKeychain();
  _installErrorHandlers(state);
  runApp(const ApertureApp());
}

AppBrightness _systemBrightness() =>
    PlatformDispatcher.instance.platformBrightness == Brightness.dark
    ? AppBrightness.dark
    : AppBrightness.light;

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

class _ApertureAppState extends State<ApertureApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  /// The dialog in [_onExitRequested] needs a context below [MaterialApp]'s
  /// navigator; this State sits above it.
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  /// Requests from the native app menu (`AppDelegate.swift`).
  static const _appChannel = MethodChannel('aperture/app');

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addObserver(this);
    _appChannel.setMethodCallHandler(_onAppMenu);
  }

  Future<void> _onAppMenu(MethodCall call) async {
    final context = _navigator.currentContext;
    if (call.method == 'showAbout' && context != null) {
      await showAboutAperture(context);
    }
  }

  /// macOS flipped appearance. The store decides whether that matters —
  /// under any mode but `auto` it is recorded and nothing repaints.
  @override
  void didChangePlatformBrightness() {
    appState.store.setSystemBrightness(_systemBrightness());
  }

  Future<AppExitResponse> _onExitRequested() async {
    final pending = appState.tabsController.unappliedEditCount;
    final context = _navigator.currentContext;
    if (pending > 0 && context != null) {
      final proceed = await confirmDiscardEdits(
        context,
        pending: pending,
        title: 'Quit Aperture?',
        action: 'Quitting now',
        proceedLabel: 'Quit anyway',
      );
      if (!proceed) return AppExitResponse.cancel;
    }
    await appState.flush();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _appChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<(AppBrightness, bool)>(
      listenable: appState.store,
      selector: () => (appState.store.brightness, appState.store.isOpen),
      builder: (context, value) {
        final (brightness, open) = value;
        return MaterialApp(
          title: 'Aperture',
          navigatorKey: _navigator,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(brightness),
          scrollBehavior: const _DesktopScrollBehavior(),
          home: open
              ? AppShell(key: ValueKey(brightness))
              : const UnlockScreen(),
        );
      },
    );
  }
}

/// Clamps every scroll view at its edges. Flutter gives macOS iOS-style
/// elastic overscroll by default, which on a page or dialog barely taller
/// than its viewport reads as the content jumping back.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
