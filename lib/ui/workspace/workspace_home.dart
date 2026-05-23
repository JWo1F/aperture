import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/catalog_controller.dart';
import '../../state/per_connection_store.dart';
import '../../state/session_controller.dart';
import '../../state/tabs_controller.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import 'workspace_home/hero.dart';
import 'workspace_home/jump_and_queries.dart';
import 'workspace_home/largest_tables.dart';
import 'workspace_home/quick_actions.dart';
import 'workspace_home/stat_ribbon.dart';

/// The connected-but-nothing-open workspace screen. Replaces the old generic
/// "Nothing open" [EmptyState] with a database home: a live overview of the
/// connection (schema/table/view counts, on-disk size), quick-launch tiles,
/// the recent + saved-query lists, and a storage breakdown of the largest
/// relations. Everything is keyboard-reachable and clickable.
class WorkspaceHome extends StatelessWidget {
  const WorkspaceHome({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final perConnection = context.watch<PerConnectionStore>();
    final tabs = context.read<TabsController>();
    final conn = session.activeConnection;
    final tint = AppColors.connectionTint(conn?.color);

    final relations = [
      for (final s in catalog.schemas) ...s.tables,
    ];
    final tableCount = relations.where((r) => !r.isView).length;
    final viewCount = relations.where((r) => r.isView).length;
    final sized = [
      for (final r in relations)
        if (r.sizeBytes != null && r.sizeBytes! > 0) r,
    ]..sort((a, b) => b.sizeBytes!.compareTo(a.sizeBytes!));
    final totalSize = sized.fold<int>(0, (sum, r) => sum + r.sizeBytes!);

    final recents = perConnection.recents;
    final frequent = perConnection.frequentTables(limit: 6);
    final jumpBack = recents.isNotEmpty ? recents : frequent;
    final queries = perConnection.savedQueries;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bg,
        gradient: RadialGradient(
          center: const Alignment(0, -1.15),
          radius: 1.25,
          colors: [tint.withValues(alpha: 0.07), Colors.transparent],
          stops: const [0, 0.7],
        ),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 44, 40, 48),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 720;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeHero(
                          connection: conn,
                          tint: tint,
                          serverVersion: session.serverVersion,
                        ),
                        const SizedBox(height: 26),
                        StatRibbon(
                          schemas: catalog.schemas.length,
                          tables: tableCount,
                          views: viewCount,
                          totalSize: totalSize,
                          loading: catalog.schemas.isEmpty &&
                              catalog.isPhase1Loading,
                        ),
                        const SizedBox(height: 14),
                        QuickActions(
                          tint: tint,
                          narrow: narrow,
                          onNewQuery: tabs.newQueryTab,
                          onSearch: () => showCommandPalette(context),
                        ),
                        const SizedBox(height: 28),
                        JumpAndQueries(
                          narrow: narrow,
                          jumpBack: jumpBack,
                          jumpIsFrequent: recents.isEmpty && frequent.isNotEmpty,
                          queries: queries,
                          tint: tint,
                          onOpenTable: tabs.openTable,
                          onOpenQuery: tabs.openSavedQuery,
                          onNewQuery: tabs.newQueryTab,
                        ),
                        if (sized.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          LargestTables(
                            tables: sized.take(6).toList(),
                            tint: tint,
                            onOpen: tabs.openTable,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
