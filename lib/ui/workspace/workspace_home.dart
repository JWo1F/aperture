import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../models/db_object.dart';
import '../../models/saved_query.dart';
import '../../models/time_ago.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import '../widgets/common.dart';
import '../widgets/table_glyph.dart';

/// The connected-but-nothing-open workspace screen. Replaces the old generic
/// "Nothing open" [EmptyState] with a database home: a live overview of the
/// connection (schema/table/view counts, on-disk size), quick-launch tiles,
/// the recent + saved-query lists, and a storage breakdown of the largest
/// relations. Everything is keyboard-reachable and clickable.
class WorkspaceHome extends StatelessWidget {
  const WorkspaceHome({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conn = state.activeConnection;
    final tint = AppColors.connectionTint(conn?.color);

    final relations = [
      for (final s in state.schemas) ...s.tables,
    ];
    final tableCount = relations.where((r) => !r.isView).length;
    final viewCount = relations.where((r) => r.isView).length;
    final sized = [
      for (final r in relations)
        if (r.sizeBytes != null && r.sizeBytes! > 0) r,
    ]..sort((a, b) => b.sizeBytes!.compareTo(a.sizeBytes!));
    final totalSize = sized.fold<int>(0, (sum, r) => sum + r.sizeBytes!);

    final recents = state.recents;
    final frequent = state.frequentTables(limit: 6);
    final jumpBack = recents.isNotEmpty ? recents : frequent;
    final queries = state.savedQueries;

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
                        _Hero(
                          connection: conn,
                          tint: tint,
                          serverVersion: state.serverVersion,
                        ),
                        const SizedBox(height: 26),
                        _StatRibbon(
                          schemas: state.schemas.length,
                          tables: tableCount,
                          views: viewCount,
                          totalSize: totalSize,
                          loading:
                              state.schemas.isEmpty && state.isCatalogLoading,
                        ),
                        const SizedBox(height: 14),
                        _QuickActions(
                          tint: tint,
                          narrow: narrow,
                          onNewQuery: state.newQueryTab,
                          onSearch: () => showCommandPalette(context, state),
                        ),
                        const SizedBox(height: 28),
                        _JumpAndQueries(
                          narrow: narrow,
                          jumpBack: jumpBack,
                          jumpIsFrequent: recents.isEmpty && frequent.isNotEmpty,
                          queries: queries,
                          tint: tint,
                          onOpenTable: state.openTable,
                          onOpenQuery: state.openSavedQuery,
                          onNewQuery: state.newQueryTab,
                        ),
                        if (sized.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _LargestTables(
                            tables: sized.take(6).toList(),
                            tint: tint,
                            onOpen: state.openTable,
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

// ──────────────────────────────────────────────────────────────────────────
// Hero
// ──────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.connection,
    required this.tint,
    required this.serverVersion,
  });

  final ConnectionConfig? connection;
  final Color tint;
  final String? serverVersion;

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Working late';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 22) return 'Good evening';
    return 'Working late';
  }

  @override
  Widget build(BuildContext context) {
    final name = connection?.name ?? 'Database';
    final summary = connection?.summary ?? '';
    final engineLabel = connection?.engine == DbEngine.sqlite
        ? 'SQLite'
        : 'PostgreSQL';
    final connectedAt = connection?.lastConnectedAt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brMd,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: _AnimatedIris(tint: tint),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting().toUpperCase(),
                style: AppTheme.eyebrow(color: tint),
              ),
              const SizedBox(height: 5),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.ui(
                  size: 23,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              if (summary.isNotEmpty)
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _StatusColumn(
          tint: tint,
          engineLabel: engineLabel,
          serverVersion: serverVersion,
          connectedAt: connectedAt,
        ),
      ],
    );
  }
}

/// Right-hand side of the hero: a live "connected" pill plus engine/version
/// metadata, right-aligned so it reads as a status block.
class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.tint,
    required this.engineLabel,
    required this.serverVersion,
    required this.connectedAt,
  });

  final Color tint;
  final String engineLabel;
  final String? serverVersion;
  final DateTime? connectedAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LiveDot(color: AppColors.success),
            const SizedBox(width: 6),
            Text(
              'Connected',
              style: AppTheme.ui(
                size: 11.5,
                weight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            _MetaChip(label: engineLabel, tint: tint),
            if (serverVersion != null && serverVersion!.isNotEmpty)
              _MetaChip(label: serverVersion!, tint: tint),
          ],
        ),
        if (connectedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'session ${timeAgo(connectedAt!)}',
            style: AppTheme.mono(size: 10, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: Radii.brSm,
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 10, color: AppColors.textSecondary),
      ),
    );
  }
}

/// A tiny pulsing dot — signals the connection is live.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 8,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.22 * (1 - _c.value)),
                ),
              ),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Animated aperture iris — the brand mark, breathing.
// ──────────────────────────────────────────────────────────────────────────

class _AnimatedIris extends StatefulWidget {
  const _AnimatedIris({required this.tint});

  final Color tint;

  @override
  State<_AnimatedIris> createState() => _AnimatedIrisState();
}

class _AnimatedIrisState extends State<_AnimatedIris>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _IrisPainter(
            t: _c.value,
            tint: widget.tint,
            dim: AppColors.borderStrong,
          ),
        ),
      ),
    );
  }
}

/// Six shutter blades that rotate slowly while the aperture opening breathes
/// open and shut — a living version of the welcome-screen brand glyph.
class _IrisPainter extends CustomPainter {
  _IrisPainter({required this.t, required this.tint, required this.dim});

  final double t;
  final Color tint;
  final Color dim;

  static const int _blades = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = size.width / 2 - 1;

    // One full slow rotation per loop; the aperture breathes twice as fast.
    final rot = t * 2 * math.pi;
    final breathe = 0.5 - 0.5 * math.cos(t * 4 * math.pi);
    final aperture = r * (0.16 + 0.30 * breathe);

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = dim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );

    final bladeFill = Paint()
      ..color = tint.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final edge = Paint()
      ..color = tint.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final step = 2 * math.pi / _blades;
    for (var i = 0; i < _blades; i++) {
      final a0 = rot + i * step;
      final a1 = a0 + step;
      final outerA = Offset(cx + r * math.cos(a0), cy + r * math.sin(a0));
      final outerB = Offset(cx + r * math.cos(a1), cy + r * math.sin(a1));
      // Leading inner vertex — sits on the aperture circle, twisted off the
      // outer vertex so the blades overlap like a real iris.
      final inner = Offset(
        cx + aperture * math.cos(a1 + 0.55),
        cy + aperture * math.sin(a1 + 0.55),
      );
      final blade = Path()
        ..moveTo(outerA.dx, outerA.dy)
        ..lineTo(outerB.dx, outerB.dy)
        ..lineTo(inner.dx, inner.dy)
        ..close();
      canvas.drawPath(blade, bladeFill);
      canvas.drawLine(outerA, inner, edge);
    }

    // Centre point — pulses with the aperture.
    canvas.drawCircle(
      center,
      1.4 + breathe * 1.6,
      Paint()
        ..color = tint
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_IrisPainter old) =>
      old.t != t || old.tint != tint || old.dim != dim;
}

// ──────────────────────────────────────────────────────────────────────────
// Stat ribbon
// ──────────────────────────────────────────────────────────────────────────

class _StatRibbon extends StatelessWidget {
  const _StatRibbon({
    required this.schemas,
    required this.tables,
    required this.views,
    required this.totalSize,
    required this.loading,
  });

  final int schemas;
  final int tables;
  final int views;
  final int totalSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      _StatCell(
        value: loading ? '—' : '$schemas',
        label: schemas == 1 ? 'schema' : 'schemas',
      ),
      _StatCell(
        value: loading ? '—' : _compactCount(tables),
        label: tables == 1 ? 'table' : 'tables',
      ),
      _StatCell(
        value: loading ? '—' : _compactCount(views),
        label: views == 1 ? 'view' : 'views',
      ),
      _StatCell(
        value: loading || totalSize == 0 ? '—' : _compactBytes(totalSize),
        label: 'on disk',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 30, color: AppColors.border),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTheme.mono(
            size: 19,
            weight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(label.toUpperCase(), style: AppTheme.eyebrow()),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Quick actions
// ──────────────────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.tint,
    required this.narrow,
    required this.onNewQuery,
    required this.onSearch,
  });

  final Color tint;
  final bool narrow;
  final VoidCallback onNewQuery;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final newQuery = _ActionTile(
      icon: Icons.add_rounded,
      title: 'New query',
      subtitle: 'Open a blank SQL editor',
      shortcut: '⌘N',
      tint: tint,
      onTap: onNewQuery,
    );
    final search = _ActionTile(
      icon: Icons.search_rounded,
      title: 'Search everything',
      subtitle: 'Tables, queries & actions',
      shortcut: '⌘K',
      tint: tint,
      onTap: onSearch,
    );

    if (narrow) {
      return Column(
        children: [
          newQuery,
          const SizedBox(height: 10),
          search,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: newQuery),
        const SizedBox(width: 12),
        Expanded(child: search),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.shortcut,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String shortcut;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brMd,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.55) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: hovering ? 0.20 : 0.12),
                borderRadius: Radii.brSm,
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.ui(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.ui(
                      size: 11,
                      weight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            KbdChip(shortcut),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Jump back in + saved queries
// ──────────────────────────────────────────────────────────────────────────

class _JumpAndQueries extends StatelessWidget {
  const _JumpAndQueries({
    required this.narrow,
    required this.jumpBack,
    required this.jumpIsFrequent,
    required this.queries,
    required this.tint,
    required this.onOpenTable,
    required this.onOpenQuery,
    required this.onNewQuery,
  });

  final bool narrow;
  final List<DbTable> jumpBack;
  final bool jumpIsFrequent;
  final List<SavedQuery> queries;
  final Color tint;
  final void Function(DbTable) onOpenTable;
  final void Function(SavedQuery) onOpenQuery;
  final VoidCallback onNewQuery;

  @override
  Widget build(BuildContext context) {
    final jump = _Section(
      title: jumpIsFrequent ? 'Most visited' : 'Jump back in',
      count: jumpBack.length,
      child: jumpBack.isEmpty
          ? const _SectionEmpty(
              icon: Icons.table_chart_outlined,
              message: 'Open a table from the sidebar and it lands here.',
            )
          : Column(
              children: [
                for (final t in jumpBack.take(6))
                  _TableRow(table: t, tint: tint, onTap: () => onOpenTable(t)),
              ],
            ),
    );

    final saved = _Section(
      title: 'Saved queries',
      count: queries.length,
      child: queries.isEmpty
          ? _SectionEmpty(
              icon: Icons.bookmark_border_rounded,
              message: 'Queries you save show up here.',
              action: _TextAction(label: 'New query', onTap: onNewQuery),
            )
          : Column(
              children: [
                for (final q in queries.take(6))
                  _QueryRow(query: q, tint: tint, onTap: () => onOpenQuery(q)),
              ],
            ),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          jump,
          const SizedBox(height: 20),
          saved,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 5, child: jump),
        const SizedBox(width: 18),
        Expanded(flex: 4, child: saved),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Largest tables — storage breakdown
// ──────────────────────────────────────────────────────────────────────────

class _LargestTables extends StatelessWidget {
  const _LargestTables({
    required this.tables,
    required this.tint,
    required this.onOpen,
  });

  final List<DbTable> tables;
  final Color tint;
  final void Function(DbTable) onOpen;

  @override
  Widget build(BuildContext context) {
    final max = tables.first.sizeBytes!.toDouble();
    return _Section(
      title: 'Largest tables',
      count: tables.length,
      child: Column(
        children: [
          for (final t in tables)
            _SizeBar(
              table: t,
              fraction: max <= 0 ? 0 : t.sizeBytes! / max,
              tint: tint,
              onTap: () => onOpen(t),
            ),
        ],
      ),
    );
  }
}

class _SizeBar extends StatelessWidget {
  const _SizeBar({
    required this.table,
    required this.fraction,
    required this.tint,
    required this.onTap,
  });

  final DbTable table;
  final double fraction;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        height: 34,
        margin: const EdgeInsets.only(top: 6),
        child: Stack(
          children: [
            // Proportional fill — the storage bar.
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: Radii.brSm,
                  gradient: LinearGradient(
                    colors: [
                      tint.withValues(alpha: hovering ? 0.32 : 0.22),
                      tint.withValues(alpha: hovering ? 0.14 : 0.08),
                    ],
                  ),
                ),
              ),
            ),
            // Hairline frame + leading accent.
            Container(
              decoration: BoxDecoration(
                borderRadius: Radii.brSm,
                border: Border.all(
                  color: hovering
                      ? tint.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    TableGlyph(
                      size: 12,
                      color: table.isView ? AppColors.tDate : tint,
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        table.qualifiedKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 11.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (table.rowEstimate != null) ...[
                      Text(
                        '${_compactCount(table.rowEstimate!)} rows',
                        style: AppTheme.mono(
                          size: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      _compactBytes(table.sizeBytes!),
                      style: AppTheme.mono(
                        size: 11,
                        weight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Shared section primitives
// ──────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.child,
  });

  final String title;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 9),
          child: Row(
            children: [
              Text(title.toUpperCase(), style: AppTheme.eyebrow()),
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: const BorderRadius.all(Radii.xs),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.mono(size: 9.5, color: AppColors.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.tint,
    required this.onTap,
  });

  final DbTable table;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stat = _tableStat(table);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 38,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            TableGlyph(
              size: 13,
              color: table.isView ? AppColors.tDate : tint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    table.schema,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 9.5,
                      weight: FontWeight.w400,
                      color: AppColors.textMuted,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            if (stat != null)
              Text(
                stat,
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_rounded,
              size: 13,
              color: hovering ? tint : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryRow extends StatelessWidget {
  const _QueryRow({
    required this.query,
    required this.tint,
    required this.onTap,
  });

  final SavedQuery query;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = query.sql
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final updated = query.updatedAt;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: 38,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : AppColors.surface,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? tint.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.code_rounded, size: 14, color: tint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    query.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.ui(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    preview.isEmpty ? 'empty query' : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      size: 9.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (updated != null) ...[
              const SizedBox(width: 8),
              Text(
                timeAgo(updated),
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.text4),
          const SizedBox(height: 9),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_rounded,
            size: 13,
            color: hovering ? AppColors.accentHover : AppColors.accent,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w500,
              color: hovering ? AppColors.accentHover : AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Formatters
// ──────────────────────────────────────────────────────────────────────────

/// Faint "rows / size" suffix for a table row, e.g. `110k / 10GB`.
String? _tableStat(DbTable table) {
  final parts = <String>[
    if (table.rowEstimate != null) _compactCount(table.rowEstimate!),
    if (table.sizeBytes != null) _compactBytes(table.sizeBytes!),
  ];
  return parts.isEmpty ? null : parts.join(' / ');
}

/// Human-friendly row count: `940`, `1.2k`, `110k`, `3.4M`, `2.1B`.
String _compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return k >= 99.95 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
  }
  if (n < 1000000000) {
    final m = n / 1000000;
    return m >= 99.95 ? '${m.round()}M' : '${m.toStringAsFixed(1)}M';
  }
  return '${(n / 1000000000).toStringAsFixed(1)}B';
}

/// Human-friendly byte size: `512B`, `48KB`, `10GB`, `1.4TB`.
String _compactBytes(int bytes) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;
  const tb = gb * 1024;
  if (bytes < kb) return '${bytes}B';
  if (bytes < mb) return '${(bytes / kb).round()}KB';
  if (bytes < gb) {
    final v = bytes / mb;
    return v >= 99.95 ? '${v.round()}MB' : '${v.toStringAsFixed(1)}MB';
  }
  if (bytes < tb) {
    final v = bytes / gb;
    return v >= 99.95 ? '${v.round()}GB' : '${v.toStringAsFixed(1)}GB';
  }
  return '${(bytes / tb).toStringAsFixed(1)}TB';
}
