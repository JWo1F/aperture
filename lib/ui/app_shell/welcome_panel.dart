import 'package:flutter/material.dart';

import '../../models/connection_config.dart';
import '../../state/app_globals.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import '../about/about_dialog.dart';
import '../command_palette/command_palette.dart';
import '../connection/connection_dialog.dart';
import '../widgets/filter_field.dart';
import 'welcome/connection_cards.dart';
import 'welcome/hero.dart';
import 'welcome/states.dart';

/// Shown in place of the workspace — and of the sidebar — until a live
/// connection exists: the brand header, the last-used connection as a
/// one-click resume, and every other saved connection as a card grid, each
/// with the edit / delete the sidebar's connection list used to offer. Static — nothing on it animates
/// except the connect spinner.
class WelcomePanel extends StatefulWidget {
  const WelcomePanel({super.key});

  @override
  State<WelcomePanel> createState() => _WelcomePanelState();
}

class _WelcomePanelState extends State<WelcomePanel> {
  /// The grid grows a filter above this many cards.
  static const _filterThreshold = 6;

  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        appState.store,
        appState.session,
        appState.catalog,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final session = appState.session;
    final catalog = appState.catalog;
    final status = session.status;
    final connecting = status == ConnectionStatus.connecting;
    // The same loader covers the network handshake and the post-connect
    // wait for phase 0. The shell keeps the welcome panel mounted across
    // both gaps so the workspace doesn't pop in with empty data.
    final preparing =
        connecting ||
        (status == ConnectionStatus.connected &&
            !catalog.hasSchemas &&
            catalog.lastError == null);

    final ordered = _byRecency(appState.store.connections);
    final resume = ordered.isNotEmpty && ordered.first.lastConnectedAt != null
        ? ordered.first
        : null;
    final others = resume == null ? ordered : ordered.sublist(1);
    final query = _filter.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? others
        : [
            for (final c in others)
              if (c.name.toLowerCase().contains(query) ||
                  c.summary.toLowerCase().contains(query))
                c,
          ];

    void newConnection() => createConnectionFlow(context);
    void edit(ConnectionConfig c) => editConnectionFlow(context, c);
    void delete(ConnectionConfig c) => appState.store.removeConnection(c.id);

    return ColoredBox(
      color: AppColors.bg,
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 56, 36, 40),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 820 ? 3 : (width >= 520 ? 2 : 1);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WelcomeHero(
                        onSearch: () => showCommandPalette(context),
                        onNew: newConnection,
                        stacked: width < 640,
                      ),
                      const SizedBox(height: 36),
                      if (status == ConnectionStatus.error &&
                          session.error != null) ...[
                        WelcomeError(message: session.error!),
                        const SizedBox(height: 16),
                      ],
                      if (preparing)
                        WelcomePreparing(
                          connecting: connecting,
                          connectionName: session.activeConnection?.name,
                        )
                      else if (ordered.isEmpty)
                        WelcomeEmpty(onNew: newConnection)
                      else ...[
                        if (resume != null) ...[
                          ResumeCard(
                            config: resume,
                            onConnect: () => appState.connect(resume),
                            onEdit: () => edit(resume),
                            onDelete: () => delete(resume),
                            compact: width < 560,
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (others.isNotEmpty) ...[
                          _GridHeader(
                            title: resume == null
                                ? 'Connections'
                                : 'Other connections',
                            count: others.length,
                            filter: others.length > _filterThreshold
                                ? _filter
                                : null,
                          ),
                          const SizedBox(height: 12),
                          _Grid(
                            columns: columns,
                            children: [
                              for (final c in shown)
                                ConnectionCard(
                                  config: c,
                                  onConnect: () => appState.connect(c),
                                  onEdit: () => edit(c),
                                  onDelete: () => delete(c),
                                ),
                            ],
                          ),
                          if (shown.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No connection matches the filter.',
                                style: AppTheme.ui(
                                  size: 12,
                                  weight: FontWeight.w400,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                        ],
                      ],
                      const SizedBox(height: 40),
                      WelcomeFooter(onAbout: () => showAboutAperture(context)),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Most recently used first; never-opened connections after them by name.
  static List<ConnectionConfig> _byRecency(List<ConnectionConfig> all) =>
      [...all]..sort((a, b) {
        final at = a.lastConnectedAt, bt = b.lastConnectedAt;
        if (at == null && bt == null) {
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
}

class _GridHeader extends StatelessWidget {
  const _GridHeader({
    required this.title,
    required this.count,
    required this.filter,
  });

  final String title;
  final int count;
  final TextEditingController? filter;

  @override
  Widget build(BuildContext context) {
    final controller = filter;
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Text(title.toUpperCase(), style: AppTheme.eyebrow()),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          if (controller != null)
            SizedBox(
              width: 220,
              child: FilterField(
                controller: controller,
                hint: 'Filter connections…',
              ),
            ),
        ],
      ),
    );
  }
}

/// Equal-width rows of [columns] cells.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i += columns) ...[
          if (i > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: _gap),
                Expanded(
                  child: i + j < children.length
                      ? children[i + j]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
