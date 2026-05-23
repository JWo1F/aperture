import '../../state/app_state.dart';
import '../../state/app_store.dart';
import '../../state/catalog_controller.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_ui.dart';

/// Bundle of the controllers the sidebar widgets pull from. Captured once
/// in `_SidebarState` so subwidgets don't repeat `context.read` lookups for
/// the same handles, and so the field-threading reads naturally.
class SidebarDeps {
  SidebarDeps({
    required this.appState,
    required this.store,
    required this.session,
    required this.catalog,
    required this.tabs,
    required this.ui,
  });

  final AppState appState;
  final AppStore store;
  final SessionController session;
  final CatalogController catalog;
  final TabsController tabs;
  final WorkspaceUi ui;
}
