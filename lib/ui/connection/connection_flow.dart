import 'package:flutter/widgets.dart';

import '../../models/connection_config.dart';
import '../../state/app_globals.dart';
import 'dialog/connection_dialog.dart';

/// Open the create-connection dialog. On submit, add the new config to the
/// store and connect to it. Returns the new config, or null if the user
/// dismissed the dialog or the [BuildContext] was unmounted by the time the
/// dialog resolved.
Future<ConnectionConfig?> createConnectionFlow(BuildContext context) async {
  final config = await showConnectionDialog(context);
  if (config == null) return null;
  appState.store.addConnection(config);
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
  final updated = await showConnectionDialog(context, existing: existing);
  if (updated == null) return null;
  appState.updateConnection(updated);
  return updated;
}
