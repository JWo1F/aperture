import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'common.dart';
import 'context_menu.dart';

/// Shared visual primitives for the workspace's bottom status strip.
///
/// The table view's row-paginator and the query view's run-summary both
/// render the same hairline-topped 28px footer with three-segment stats
/// separated by middle dots. These widgets are the only thing the two
/// callers share; the surrounding row content (chevrons, refresh menu,
/// pending-edits chip) stays specific to each view.

const double pagebarHeight = 28;

/// Middle-dot separator between stat segments.
class PbDot extends StatelessWidget {
  const PbDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '·',
        style: AppTheme.mono(size: 10.5, color: AppColors.text4),
      ),
    );
  }
}

/// A three-part stat segment: optional [head] (the design's bold prefix),
/// optional [mid] (always emphasised), optional [tail] (always muted).
/// Set [headHighlight] to render [head] in primary text weight.
class PbStat extends StatelessWidget {
  const PbStat({
    super.key,
    this.head,
    this.mid,
    this.tail,
    this.headHighlight = false,
  });

  final String? head;
  final String? mid;
  final String? tail;
  final bool headHighlight;

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.mono(size: 10.5, color: AppColors.textMuted);
    final emph = AppTheme.mono(
      size: 10.5,
      color: AppColors.textPrimary,
      weight: FontWeight.w600,
    );
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          if (head != null)
            TextSpan(text: head!, style: headHighlight ? emph : base),
          if (mid != null) TextSpan(text: mid!, style: emph),
          if (tail != null) TextSpan(text: tail!),
        ],
      ),
    );
  }
}

/// Square 22px chevron button used for page navigation. Greys out when
/// [onPressed] is null.
class PbChev extends StatelessWidget {
  const PbChev({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Hoverable(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onPressed,
        builder: (context, hovering) {
          final fg = enabled
              ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
              : AppColors.textMuted.withValues(alpha: 0.4);
          return Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovering && enabled
                  ? AppColors.surfaceHover
                  : Colors.transparent,
              borderRadius: Radii.brSm,
            ),
            child: Icon(icon, size: 14, color: fg),
          );
        },
      ),
    );
  }
}

/// `12,345`-style grouping for the row-count stats.
String withCommas(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// `HH:MM:SS` clock used by "refreshed" stamps.
String formatPagebarClock(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

/// Standard cadence options surfaced in the refresh dropdowns. Shared so
/// table and query footers offer the same picks.
const List<(String, Duration?)> refreshIntervalOptions = [
  ('manual', null),
  ('5 s', Duration(seconds: 5)),
  ('15 s', Duration(seconds: 15)),
  ('30 s', Duration(seconds: 30)),
  ('1 m', Duration(minutes: 1)),
  ('5 m', Duration(minutes: 5)),
];

/// Manual refresh button + `auto · interval` pill that opens a dropdown
/// to pick an auto-refresh cadence.
///
/// The widget is driven by callbacks so both [TableTab] and [QueryTab]
/// pagebars can reuse it without sharing any tab type.
class RefreshDropdown extends StatelessWidget {
  const RefreshDropdown({
    super.key,
    required this.interval,
    required this.busy,
    required this.canRefresh,
    required this.onManualRefresh,
    required this.onSetInterval,
    this.options = refreshIntervalOptions,
  });

  /// Current auto-refresh cadence. `null` means manual.
  final Duration? interval;

  /// True while a refresh is in flight; renders the spinner.
  final bool busy;

  /// Whether the manual refresh action is currently available.
  final bool canRefresh;

  final VoidCallback onManualRefresh;
  final ValueChanged<Duration?> onSetInterval;
  final List<(String, Duration?)> options;

  String _label() {
    if (interval == null) return 'manual';
    for (final (label, opt) in options) {
      if (opt == interval) return label;
    }
    return 'custom';
  }

  void _openMenu(BuildContext context, Offset position) {
    showContextMenu(
      context,
      globalPosition: position,
      entries: [
        for (final (label, opt) in options)
          CmItem(
            icon: opt == interval ? Icons.check : Icons.access_time,
            label: opt == null ? 'Manual (off)' : 'Every $label',
            onTap: () => onSetInterval(opt),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final autoOn = interval != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Refresh',
          child: Hoverable(
            cursor: canRefresh
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onTap: canRefresh ? onManualRefresh : null,
            builder: (context, hovering) {
              final fg = canRefresh
                  ? (hovering
                      ? AppColors.textPrimary
                      : (autoOn ? AppColors.accent : AppColors.textMuted))
                  : AppColors.textMuted.withValues(alpha: 0.4);
              return Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovering && canRefresh
                      ? AppColors.surfaceHover
                      : Colors.transparent,
                  borderRadius: Radii.brSm,
                ),
                child: busy
                    ? SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: AppColors.accent,
                        ),
                      )
                    : Icon(Icons.refresh, size: 13, color: fg),
              );
            },
          ),
        ),
        const SizedBox(width: 2),
        Builder(
          builder: (anchorContext) => Hoverable(
            cursor: SystemMouseCursors.click,
            onTap: () {
              final box = anchorContext.findRenderObject() as RenderBox?;
              if (box == null) return;
              final origin = box.localToGlobal(Offset.zero);
              _openMenu(
                context,
                Offset(origin.dx, origin.dy + box.size.height + 2),
              );
            },
            builder: (context, hovering) {
              final Color fg =
                  autoOn ? AppColors.accent : AppColors.textSecondary;
              final Color hoverFg = hovering
                  ? (autoOn ? AppColors.accent : AppColors.textPrimary)
                  : fg;
              return Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovering
                      ? AppColors.surfaceHover
                      : Colors.transparent,
                  borderRadius: Radii.brSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label(),
                      style: AppTheme.mono(
                        size: 10.5,
                        color: hoverFg,
                        weight: autoOn ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.expand_more, size: 11, color: hoverFg),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
