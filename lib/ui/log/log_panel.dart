import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/log_event.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

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
      width: 380,
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
                Text(
                  'Activity log',
                  style: AppTheme.eyebrow(),
                ),
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

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHover : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            Icons.close,
            size: 12,
            color: _hover ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.event});
  final LogEvent event;

  Color _kindColor() {
    switch (event.kind) {
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

  String _summary() {
    switch (event.kind) {
      case LogEventKind.connect:
        return 'connect ${event.connectionName ?? ''}';
      case LogEventKind.disconnect:
        return 'disconnect ${event.connectionName ?? ''}';
      case LogEventKind.lost:
        return 'lost ${event.connectionName ?? ''}';
      case LogEventKind.error:
        return 'error';
      case LogEventKind.query:
        return event.sql ?? '';
      case LogEventKind.edit:
        return event.sql ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(
            ClipboardData(text: event.sql ?? event.error ?? ''),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: 6,
          ),
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
                    style: AppTheme.mono(
                      size: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (event.elapsed != null)
                    Text(
                      '${event.elapsed!.inMilliseconds}ms',
                      style: AppTheme.mono(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  const Spacer(),
                  if (event.affectedRows != null)
                    Text(
                      '${event.affectedRows} row${event.affectedRows == 1 ? '' : 's'}',
                      style: AppTheme.mono(
                        size: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _summary(),
                style: AppTheme.mono(
                  size: 11.5,
                  color: AppColors.textPrimary,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (event.error != null) ...[
                const SizedBox(height: 2),
                Text(
                  event.error!,
                  style: AppTheme.mono(size: 11, color: AppColors.error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
