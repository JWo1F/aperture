import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../state/app_state.dart';
import '../../state/app_store.dart';
import 'dialog/connection_dialog.dart';

/// Open the create-connection dialog. On submit, add the new config to the
/// store and connect to it. Returns the new config, or null if the user
/// dismissed the dialog or the [BuildContext] was unmounted by the time the
/// dialog resolved.
Future<ConnectionConfig?> createConnectionFlow(BuildContext context) async {
  final appState = context.read<AppState>();
  final store = context.read<AppStore>();
  final config = await showConnectionDialog(context);
  if (config == null) return null;
  store.addConnection(config);
  await appState.connect(config);
  return config;
}

/// Open the edit-connection dialog seeded with [existing]. On submit, write
/// the changes back through [AppState.updateConnection]. Returns the
/// updated config, or null if dismissed.
Future<ConnectionConfig?> editConnectionFlow(
  BuildContext context,
  ConnectionConfig existing,
) async {
  final appState = context.read<AppState>();
  final updated = await showConnectionDialog(context, existing: existing);
  if (updated == null) return null;
  appState.updateConnection(updated);
  return updated;
}
