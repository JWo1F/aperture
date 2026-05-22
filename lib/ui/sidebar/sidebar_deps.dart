import '../../state/app_state.dart';
import '../../state/catalog_controller.dart';
import '../../state/connection_registry.dart';
import '../../state/per_connection_store.dart';
import '../../state/preferences_controller.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_ui.dart';

/// Bundle of the controllers the sidebar widgets pull from. Captured once
/// in `_SidebarState` so subwidgets don't repeat `context.read` lookups for
/// the same handles, and so the field-threading reads naturally.
class SidebarDeps {
  SidebarDeps({
    required this.appState,
    required this.preferences,
    required this.registry,
    required this.session,
    required this.catalog,
    required this.perConnection,
    required this.tabs,
    required this.ui,
  });

  final AppState appState;
  final PreferencesController preferences;
  final ConnectionRegistry registry;
  final SessionController session;
  final CatalogController catalog;
  final PerConnectionStore perConnection;
  final TabsController tabs;
  final WorkspaceUi ui;
}
