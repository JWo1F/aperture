import 'package:flutter/material.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManipulator.initialize();
  await WindowManipulator.makeTitlebarTransparent();
  await WindowManipulator.enableFullSizeContentView();
  await WindowManipulator.hideTitle();
  runApp(const DbvApp());
}

class DbvApp extends StatelessWidget {
  const DbvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'DBV',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: const AppShell(),
      ),
    );
  }
}
