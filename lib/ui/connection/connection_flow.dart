import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../state/app_state.dart';
import '../../state/connection_registry.dart';
import 'dialog/connection_dialog.dart';

/// Open the create-connection dialog. On submit, add the new config to the
/// registry and connect to it. Returns the new config, or null if the user
/// dismissed the dialog or the [BuildContext] was unmounted by the time the
/// dialog resolved.
///
/// Callers shrink to one line — the registry write + connect sequence is
/// the same at every call site, so duplicating it invited drift whenever
/// post-create behavior had to change.
Future<ConnectionConfig?> createConnectionFlow(BuildContext context) async {
  final appState = context.read<AppState>();
  final registry = context.read<ConnectionRegistry>();
  final config = await showConnectionDialog(context);
  if (config == null) return null;
  registry.add(config);
  await appState.connect(config);
  return config;
}

/// Open the edit-connection dialog seeded with [existing]. On submit, write
/// the changes back through [AppState.updateConnection] (which refreshes
/// the session snapshot if the active connection was edited). Returns the
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
