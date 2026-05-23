import 'package:flutter/material.dart';

import '../../state/app_globals.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import 'conn_hero.dart';
import 'connections_list.dart';
import 'schema_tree.dart';
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

  /// The sidebar mirrors persisted state, the session, the catalog, the
  /// open tabs and the schema-tree UI. Listening to just those controllers
  /// — rather than the full set — keeps a navigation-history push or an
  /// event-log append from rebuilding the whole schema list.
  late final Listenable _sidebarListenable = Listenable.merge([
    appState.store,
    appState.session,
    appState.catalog,
    appState.tabsController,
    appState.ui,
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
        final status = appState.session.status;
        final catalog = appState.catalog;
        final connecting = status == ConnectionStatus.connecting;
        final connected = status == ConnectionStatus.connected;
        // Loading covers two distinct gaps the user perceives as one wait:
        // the TCP/auth handshake (status == connecting) and the post-connect
        // window before phase 0 lands. Without this, the sidebar flips from
        // the connections list to an empty schema tree with no signal that
        // introspection is in flight.
        final loadingCatalog =
            connecting ||
            (connected && !catalog.hasSchemas && catalog.lastError == null);

        return Container(
          width: appState.store.sidebarWidth,
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
              const ConnHero(),
              if (loadingCatalog)
                const Expanded(child: _SidebarLoading())
              else if (connected) ...[
                SidebarSearchBar(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                ),
                Expanded(
                  child: SidebarBody(query: _query.trim().toLowerCase()),
                ),
              ] else
                const Expanded(child: AllConnectionsList()),
              const SidebarFooter(),
            ],
          ),
        );
      },
    );
  }
}

/// Centered spinner shown while a connection is opening and its first
/// schema fetch lands. The caption disambiguates the two gaps so the user
/// can tell whether the network round-trip or the catalog read is what's
/// taking time.
class _SidebarLoading extends StatelessWidget {
  const _SidebarLoading();

  @override
  Widget build(BuildContext context) {
    final connecting =
        appState.session.status == ConnectionStatus.connecting;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            connecting ? 'Connecting…' : 'Loading schemas…',
            style: AppTheme.ui(
              size: 11.5,
              color: AppColors.textSecondary,
              weight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
