import '../../state/app_state.dart';
import '../../state/app_store.dart';
import '../../state/catalog_controller.dart';
import '../../state/event_log.dart';
import '../../state/navigation_history.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';

/// Bundle of controllers the palette pulls from. Each is read once at
/// open-time so the palette's internal builders don't repeat lookups.
class PaletteDeps {
  PaletteDeps({
    required this.appState,
    required this.store,
    required this.session,
    required this.catalog,
    required this.tabs,
    required this.history,
    required this.eventLog,
  });

  final AppState appState;
  final AppStore store;
  final SessionController session;
  final CatalogController catalog;
  final TabsController tabs;
  final NavigationHistory history;
  final EventLog eventLog;
}
