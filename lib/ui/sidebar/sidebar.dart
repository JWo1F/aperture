import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/catalog_controller.dart';
import '../../state/connection_registry.dart';
import '../../state/per_connection_store.dart';
import '../../state/preferences_controller.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';
import '../../state/workspace_ui.dart';
import '../../theme/app_theme.dart';
import 'conn_hero.dart';
import 'connections_list.dart';
import 'schema_tree.dart';
import 'sidebar_deps.dart';
import 'sidebar_footer.dart';

/// Sidebar v4 — Inter-typeset, search-led, pin-forward.
///
/// Layout (top → bottom):
///   1. Connection hero card — database name, server tag, click to open menu.
///   2. Slim filter input — substring filter applied to every list below.
///   3. Scroll body: Pinned · Recent · Queries · Schemas.
///      Schemas auto-expand when filtering. Pin star is an inline toggle.
///   4. Footer status — pulsing dot + plain-text live-state.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  late final SidebarDeps _deps = SidebarDeps(
    appState: context.read<AppState>(),
    preferences: context.read<PreferencesController>(),
    registry: context.read<ConnectionRegistry>(),
    session: context.read<SessionController>(),
    catalog: context.read<CatalogController>(),
    perConnection: context.read<PerConnectionStore>(),
    tabs: context.read<TabsController>(),
    ui: context.read<WorkspaceUi>(),
  );

  /// The sidebar mirrors connections, the session, the catalog, the
  /// per-connection lists, the open tabs and preferences. Listening to just
  /// those controllers — rather than the full set — keeps a navigation-
  /// history push, an event-log append, or a passphrase change from
  /// rebuilding the whole schema list.
  late final Listenable _sidebarListenable = Listenable.merge([
    _deps.preferences,
    _deps.registry,
    _deps.session,
    _deps.catalog,
    _deps.perConnection,
    _deps.tabs,
    _deps.ui,
  ]);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchCtrl.text;
    if (next != _query) setState(() => _query = next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sidebarListenable,
      builder: (context, _) {
        final connected = _deps.session.status == ConnectionStatus.connected;

        return Container(
          width: _deps.preferences.sidebarWidth,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.sidebarTint, AppColors.bgDeep],
              stops: const [0.0, 1.0],
            ),
            border: Border(right: BorderSide(color: AppColors.hairline)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConnHero(deps: _deps),
              if (connected) ...[
                SidebarSearchBar(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                ),
                Expanded(
                  child: SidebarBody(
                    deps: _deps,
                    query: _query.trim().toLowerCase(),
                  ),
                ),
              ] else
                Expanded(child: AllConnectionsList(deps: _deps)),
              SidebarFooter(deps: _deps),
            ],
          ),
        );
      },
    );
  }
}
