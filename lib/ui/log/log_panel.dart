import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/pgsql.dart';
import 'package:provider/provider.dart';

import '../../models/log_event.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';

/// Slide-out pane that shows the in-memory event log (queries, edits,
/// connection lifecycle, errors). Bound to ⌘L from the app shell.
class LogPanel extends StatelessWidget {
  const LogPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final log = state.eventLog;
    if (!log.isVisible) return const SizedBox.shrink();

    return Container(
      width: state.preferences.logPanelWidth,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: Insets.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.subject, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('Activity log', style: AppTheme.eyebrow()),
                const Spacer(),
                Text(
                  '${log.events.length} event${log.events.length == 1 ? '' : 's'}',
                  style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                ),
                const SizedBox(width: 8),
                _CloseButton(onTap: () => log.setVisible(false)),
              ],
            ),
          ),
          Expanded(
            child: log.events.isEmpty
                ? Center(
                    child: Text(
                      'No events yet.',
                      style: AppTheme.mono(
                        size: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                    itemCount: log.events.length,
                    itemBuilder: (context, i) {
                      final e = log.events[log.events.length - 1 - i];
                      return _LogRow(event: e);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: Radii.brSm,
        ),
        child: Icon(
          Icons.close,
          size: 12,
          color: hovering ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Lazily registers the `pgsql` grammar with the global [highlight]
/// instance so SQL bodies in the activity log are tokenised the same way
/// as in the editor and DDL viewer.
bool _pgsqlRegistered = false;

void _ensurePgsqlRegistered() {
  if (_pgsqlRegistered) return;
  highlight.registerLanguage('pgsql', pgsql);
  _pgsqlRegistered = true;
}

/// Past this many lines (or characters), a SQL body collapses to
/// [_collapsedMaxLines] with a "Show more" toggle. Tuned so a typical
/// catalog query (1-3 lines) never gets the toggle, and any wrapped
/// `UPDATE … SET …` does.
const int _collapseLineThreshold = 4;
const int _collapseCharThreshold = 240;
const int _collapsedMaxLines = 4;

class _LogRow extends StatefulWidget {
  const _LogRow({required this.event});

  final LogEvent event;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _expanded = false;

  Color _kindColor() {
    switch (widget.event.kind) {
      case LogEventKind.connect:
        return AppColors.success;
      case LogEventKind.disconnect:
        return AppColors.textMuted;
      case LogEventKind.lost:
        return AppColors.warning;
      case LogEventKind.error:
        return AppColors.error;
      case LogEventKind.query:
        return AppColors.accent;
      case LogEventKind.edit:
        return AppColors.accent;
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  /// The body text shown in the row. For SQL rows this is the SQL itself;
  /// for lifecycle rows it's a short verb summary.
  String _bodyText() {
    final e = widget.event;
    switch (e.kind) {
      case LogEventKind.connect:
        return 'connect ${e.connectionName ?? ''}';
      case LogEventKind.disconnect:
        return 'disconnect ${e.connectionName ?? ''}';
      case LogEventKind.lost:
        return 'lost ${e.connectionName ?? ''}';
      case LogEventKind.error:
        return e.sql ?? 'error';
      case LogEventKind.query:
      case LogEventKind.edit:
        return e.sql ?? '';
    }
  }

  /// True when this row carries a real SQL body that should be tokenised
  /// with the `pgsql` grammar. Edit-summary rows ("3 UPDATE statement(s)")
  /// stay as plain text.
  bool get _isSqlBody {
    final e = widget.event;
    if (e.kind != LogEventKind.query) return false;
    final sql = e.sql;
    return sql != null && sql.trim().isNotEmpty;
  }

  bool _overflows(String body) {
    if (body.length > _collapseCharThreshold) return true;
    var lines = 1;
    for (var i = 0; i < body.length; i++) {
      if (body.codeUnitAt(i) == 0x0A) lines++;
      if (lines > _collapseLineThreshold) return true;
    }
    return false;
  }

  TextSpan _highlightedSpan(String sql, TextStyle base) {
    _ensurePgsqlRegistered();
    final parsed = highlight.parse(sql, language: 'pgsql');
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final body = _bodyText();
    final overflows = _overflows(body);
    final maxLines = _expanded || !overflows ? null : _collapsedMaxLines;

    final bodyStyle = AppTheme.mono(size: 11.5, color: AppColors.textPrimary);

    // Collapsed `SelectableText` (maxLines != null) would still allow the
    // hidden tail to scroll into view via drag/wheel inside the widget,
    // which makes the "Show more" toggle pointless. Lock the inner scroll
    // while collapsed; the expanded form has no overflow to scroll.
    const collapsedPhysics = NeverScrollableScrollPhysics();
    Widget bodyWidget;
    if (body.isEmpty) {
      bodyWidget = const SizedBox.shrink();
    } else if (_isSqlBody) {
      bodyWidget = SelectableText.rich(
        _highlightedSpan(body, bodyStyle),
        maxLines: maxLines,
        style: bodyStyle,
        scrollPhysics: maxLines == null ? null : collapsedPhysics,
      );
    } else {
      bodyWidget = SelectableText(
        body,
        maxLines: maxLines,
        style: bodyStyle,
        scrollPhysics: maxLines == null ? null : collapsedPhysics,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _kindColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _time(event.timestamp),
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              if (event.elapsed != null)
                Text(
                  '${event.elapsed!.inMilliseconds}ms',
                  style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                ),
              const Spacer(),
              if (event.affectedRows != null)
                Text(
                  '${event.affectedRows} row${event.affectedRows == 1 ? '' : 's'}',
                  style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                ),
              if (event.sql != null && event.sql!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _CopyButton(text: event.sql!),
              ],
            ],
          ),
          if (body.isNotEmpty) ...[const SizedBox(height: 2), bodyWidget],
          if (overflows) ...[
            const SizedBox(height: 2),
            _ExpandToggle(
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ],
          if (event.error != null) ...[
            const SizedBox(height: 2),
            SelectableText(
              event.error!,
              style: AppTheme.mono(size: 11, color: AppColors.error),
              maxLines: _expanded ? null : 3,
              scrollPhysics: _expanded ? null : collapsedPhysics,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovering) {
        final color = hovering ? AppColors.textPrimary : AppColors.textMuted;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded ? Icons.unfold_less : Icons.unfold_more,
                size: 11,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                expanded ? 'Show less' : 'Show more',
                style: AppTheme.mono(size: 10, color: color),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: _copy,
      builder: (context, hovering) => Icon(
        _copied ? Icons.check : Icons.content_copy,
        size: 11,
        color: _copied
            ? AppColors.success
            : (hovering ? AppColors.textPrimary : AppColors.textMuted),
      ),
    );
  }
}
