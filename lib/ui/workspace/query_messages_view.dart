import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/pgsql.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';

/// Per-query message log. Renders every SQL the tab has run, newest
/// first, with highlighted SQL, elapsed time, affected rows, and any
/// error. Each entry is selectable and copyable.
class QueryMessagesView extends StatelessWidget {
  const QueryMessagesView({super.key, required this.tab});

  final QueryTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.messages.isEmpty) {
      return const EmptyState(
        icon: Icons.subject,
        title: 'No messages',
        message:
            'Every SQL this tab runs lands here — successes, failures, '
            'and timings, persisted across restarts.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(tab: tab),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: tab.messages.length,
            itemBuilder: (context, i) {
              final msg = tab.messages[tab.messages.length - 1 - i];
              return _MessageRow(message: msg);
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tab});

  final QueryTab tab;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            '${tab.messages.length} message'
            '${tab.messages.length == 1 ? '' : 's'}',
            style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          Hoverable(
            cursor: SystemMouseCursors.click,
            onTap: () => context.read<AppState>().clearQueryMessages(tab),
            builder: (context, hovering) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Clear',
                style: AppTheme.mono(
                  size: 10.5,
                  color: hovering ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _pgsqlRegistered = false;

void _ensurePgsqlRegistered() {
  if (_pgsqlRegistered) return;
  highlight.registerLanguage('pgsql', pgsql);
  _pgsqlRegistered = true;
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({required this.message});

  final QueryMessage message;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool _expanded = false;

  static const int _collapsedMaxLines = 3;
  static const int _collapseLineThreshold = 3;
  static const int _collapseCharThreshold = 180;

  bool _overflows(String body) {
    if (body.length > _collapseCharThreshold) return true;
    var lines = 1;
    for (var i = 0; i < body.length; i++) {
      if (body.codeUnitAt(i) == 0x0A) lines++;
      if (lines > _collapseLineThreshold) return true;
    }
    return false;
  }

  TextSpan _highlight(String sql, TextStyle base) {
    _ensurePgsqlRegistered();
    final parsed = highlight.parse(sql, language: 'pgsql');
    return TextSpan(
      style: base,
      children: highlightNodesToSpans(parsed.nodes, base, apertureCodeStyles),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _time(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final overflows = _overflows(m.sql);
    final maxLines = _expanded || !overflows ? null : _collapsedMaxLines;
    final bodyStyle = AppTheme.mono(size: 11.5, color: AppColors.textPrimary);
    final dotColor = m.isError ? AppColors.error : AppColors.accent;

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
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _time(m.timestamp),
                style: AppTheme.mono(size: 10, color: AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              if (m.elapsedMs != null)
                Text(
                  '${m.elapsedMs}ms',
                  style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                ),
              const Spacer(),
              if (m.affectedRows != null)
                Text(
                  '${m.affectedRows} row${m.affectedRows == 1 ? '' : 's'}',
                  style: AppTheme.mono(size: 10, color: AppColors.textMuted),
                ),
              const SizedBox(width: 8),
              _CopyButton(text: m.sql),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText.rich(
            _highlight(m.sql, bodyStyle),
            maxLines: maxLines,
            style: bodyStyle,
            scrollPhysics: maxLines == null
                ? null
                : const NeverScrollableScrollPhysics(),
          ),
          if (overflows) ...[
            const SizedBox(height: 2),
            Hoverable(
              cursor: SystemMouseCursors.click,
              onTap: () => setState(() => _expanded = !_expanded),
              builder: (context, hovering) {
                final color = hovering
                    ? AppColors.textPrimary
                    : AppColors.textMuted;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _expanded ? Icons.unfold_less : Icons.unfold_more,
                      size: 11,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded ? 'Show less' : 'Show more',
                      style: AppTheme.mono(size: 10, color: color),
                    ),
                  ],
                );
              },
            ),
          ],
          if (m.error != null) ...[
            const SizedBox(height: 2),
            SelectableText(
              m.error!,
              style: AppTheme.mono(size: 11, color: AppColors.error),
              maxLines: _expanded ? null : 3,
              scrollPhysics: _expanded
                  ? null
                  : const NeverScrollableScrollPhysics(),
            ),
          ],
        ],
      ),
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
