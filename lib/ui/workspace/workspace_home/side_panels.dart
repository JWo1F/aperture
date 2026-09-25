import 'package:flutter/material.dart';

import '../../../models/count_format.dart';
import '../../../models/db_object.dart';
import '../../../models/query_message.dart';
import '../../../models/saved_query.dart';
import '../../../models/time_ago.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/table_glyph.dart';
import 'panel.dart';

const int _listLimit = 6;

String _oneLine(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();

TextStyle get _metaStyle =>
    AppTheme.mono(size: 10.5, color: AppColors.textMuted);

class JumpBackPanel extends StatelessWidget {
  const JumpBackPanel({
    super.key,
    required this.tables,
    required this.frequent,
    required this.tint,
    required this.onOpen,
  });

  final List<DbTable> tables;

  /// The list is ranked by use count rather than recency.
  final bool frequent;
  final Color tint;
  final void Function(DbTable) onOpen;

  @override
  Widget build(BuildContext context) {
    return HomePanel(
      title: frequent ? 'Most visited' : 'Recent tables',
      count: tables.length,
      child: tables.isEmpty
          ? const HomePanelEmpty(
              icon: Hgi.table01,
              message: 'Tables you open land here.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tables.length && i < _listLimit; i++)
                  _TableRow(
                    table: tables[i],
                    tint: tint,
                    divider: i > 0,
                    onTap: () => onOpen(tables[i]),
                  ),
              ],
            ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.table,
    required this.tint,
    required this.divider,
    required this.onTap,
  });

  final DbTable table;
  final Color tint;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stat = tableStat(table);
    return HomePanelRow(
      onTap: onTap,
      divider: divider,
      child: Row(
        children: [
          TableGlyph(size: 13, color: table.isView ? AppColors.tDate : tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${table.schema}.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(text: table.name),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 12, color: AppColors.textPrimary),
            ),
          ),
          if (stat != null) ...[
            const SizedBox(width: 10),
            Text(stat, style: _metaStyle),
          ],
        ],
      ),
    );
  }
}

class SavedQueriesPanel extends StatelessWidget {
  const SavedQueriesPanel({
    super.key,
    required this.queries,
    required this.onOpen,
    required this.onNew,
  });

  final List<SavedQuery> queries;
  final void Function(SavedQuery) onOpen;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final sorted = [...queries]
      ..sort((a, b) {
        final at = a.updatedAt, bt = b.updatedAt;
        if (at == null) return bt == null ? 0 : 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    return HomePanel(
      title: 'Saved queries',
      count: queries.length,
      trailing: HomeLink(label: 'New', icon: Hgi.add01, onTap: onNew),
      child: sorted.isEmpty
          ? const HomePanelEmpty(
              icon: Hgi.sourceCode,
              message: 'Queries you write are saved here automatically.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sorted.length && i < _listLimit; i++)
                  _QueryRow(
                    query: sorted[i],
                    divider: i > 0,
                    onTap: () => onOpen(sorted[i]),
                  ),
              ],
            ),
    );
  }
}

class _QueryRow extends StatelessWidget {
  const _QueryRow({
    required this.query,
    required this.divider,
    required this.onTap,
  });

  final SavedQuery query;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = _oneLine(query.sql);
    final updated = query.updatedAt;
    return HomePanelRow(
      onTap: onTap,
      divider: divider,
      height: 44,
      child: Row(
        children: [
          Icon(Hgi.sourceCode, size: 14, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  query.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                Text(
                  preview.isEmpty ? 'empty' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _metaStyle,
                ),
              ],
            ),
          ),
          if (updated != null) ...[
            const SizedBox(width: 10),
            Text(timeAgo(updated), style: _metaStyle),
          ],
        ],
      ),
    );
  }
}

/// A run from a query tab's message log, tagged with the saved query that
/// produced it. The log outlives its query: a deleted query's runs survive
/// in the store, so [query] can be null.
typedef HomeRun = ({QueryMessage message, SavedQuery? query});

class RecentRunsPanel extends StatelessWidget {
  const RecentRunsPanel({super.key, required this.runs, required this.onOpen});

  final List<HomeRun> runs;
  final void Function(SavedQuery) onOpen;

  @override
  Widget build(BuildContext context) {
    return HomePanel(
      title: 'Recent runs',
      child: runs.isEmpty
          ? const HomePanelEmpty(
              icon: Hgi.clock01,
              message: 'Statements you run from a query tab show up here.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < runs.length; i++)
                  _RunRow(
                    run: runs[i],
                    divider: i > 0,
                    onTap: runs[i].query == null
                        ? null
                        : () => onOpen(runs[i].query!),
                  ),
              ],
            ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.divider, this.onTap});

  final HomeRun run;
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = run.message;
    final ms = m.elapsedMs;
    final String outcome;
    if (m.isError) {
      outcome = 'failed';
    } else if (m.affectedRows != null) {
      outcome = '${compactCount(m.affectedRows!)} rows';
    } else {
      outcome = 'ok';
    }
    final row = HomePanelRow(
      onTap: onTap,
      divider: divider,
      height: 44,
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.isError ? AppColors.error : AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _oneLine(m.sql),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 11.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  [
                    run.query?.name ?? 'deleted query',
                    outcome,
                    if (ms != null) '${withCommas(ms)} ms',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 10.5,
                    color: m.isError ? AppColors.error : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(timeAgo(m.timestamp), style: _metaStyle),
        ],
      ),
    );
    final error = m.error;
    if (error == null) return row;
    return Tooltip(message: error, child: row);
  }
}
