import '../../state/app_state.dart';
import '../../state/catalog_controller.dart';
import '../../state/connection_registry.dart';
import '../../state/event_log.dart';
import '../../state/navigation_history.dart';
import '../../state/per_connection_store.dart';
import '../../state/preferences_controller.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';

/// Bundle of controllers the palette pulls from. Each is read once at
/// open-time so the palette's internal builders don't repeat lookups.
class PaletteDeps {
  PaletteDeps({
    required this.appState,
    required this.preferences,
    required this.session,
    required this.registry,
    required this.catalog,
    required this.perConnection,
    required this.tabs,
    required this.history,
    required this.eventLog,
  });

  final AppState appState;
  final PreferencesController preferences;
  final SessionController session;
  final ConnectionRegistry registry;
  final CatalogController catalog;
  final PerConnectionStore perConnection;
  final TabsController tabs;
  final NavigationHistory history;
  final EventLog eventLog;
}
