import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';

import '../../theme/app_theme.dart';
import '../../theme/code_theme.dart';
import '../widgets/common.dart';
import '../../theme/hugeicons.dart';

/// Inspector-style review surface for pending row mutations. Built on
/// [showGeneralDialog] so the backdrop is ours: a real Gaussian blur of
/// whatever's behind the modal plus a soft scrim, not Material's default
/// flat black wash. The panel itself is a code-review card — eyebrow,
/// kind-broken-down stats, per-statement cards with a left status stripe,
/// and a sticky action bar pinned to the bottom. ⌘↵ applies, Esc dismisses.
Future<void> showPendingEditsModal(
  BuildContext context, {
  required List<String> statements,
  Future<void> Function()? onApply,
  VoidCallback? onRevert,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss pending edits',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (_, animation, _, _) => _PendingEditsRoute(
      animation: animation,
      statements: statements,
      onApply: onApply,
      onRevert: onRevert,
    ),
  );
}

/// Hand-rolled transition. Wrapping the whole stack in a [FadeTransition]
/// makes the [BackdropFilter] punt blur work until it's near-opaque
/// (Opacity+saveLayer skip the costly filter pass while ramping up), so
/// the user sees a sharp scene that snaps to blurred at the end of the
/// animation. We instead drive the blur sigma directly from the route
/// animation — the filter runs every frame at the right intensity, the
/// scrim alpha ramps with it, and the panel does its own fade+scale.
class _PendingEditsRoute extends StatefulWidget {
  const _PendingEditsRoute({
    required this.animation,
    required this.statements,
    required this.onApply,
    required this.onRevert,
  });

  final Animation<double> animation;
  final List<String> statements;
  final Future<void> Function()? onApply;
  final VoidCallback? onRevert;

  @override
  State<_PendingEditsRoute> createState() => _PendingEditsRouteState();
}

class _PendingEditsRouteState extends State<_PendingEditsRoute> {
  /// Shared with the panel so the backdrop honours the same in-flight
  /// guard the Close and Revert buttons do. Without it a backdrop tap
  /// dismissed the modal mid-transaction, dropping the "Applying…" state
  /// the other three paths deliberately protect.
  final ValueNotifier<bool> _applying = ValueNotifier(false);

  @override
  void dispose() {
    _applying.dispose();
    super.dispose();
  }

  static const double _maxBlur = 14;
  static const double _scrimNear = 0.55;
  static const double _scrimFar = 0.78;
  static const double _panelStartScale = 0.97;

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final panel = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: _PendingPanel(
        statements: widget.statements,
        onApply: widget.onApply,
        onRevert: widget.onRevert,
        applying: _applying,
      ),
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        final t = curve.value.clamp(0.0, 1.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_applying.value) return;
                  Navigator.of(context).pop();
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _maxBlur * t,
                    sigmaY: _maxBlur * t,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.2,
                        colors: [
                          AppColors.scrim.withValues(alpha: _scrimNear * t),
                          AppColors.scrim.withValues(alpha: _scrimFar * t),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: _panelStartScale + (1 - _panelStartScale) * t,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: panel,
    );
  }
}

class _PendingPanel extends StatefulWidget {
  const _PendingPanel({
    required this.statements,
    required this.onApply,
    required this.onRevert,
    required this.applying,
  });

  final List<String> statements;
  final Future<void> Function()? onApply;
  final VoidCallback? onRevert;

  /// Owned by the route so its backdrop can refuse to dismiss mid-apply.
  final ValueNotifier<bool> applying;

  @override
  State<_PendingPanel> createState() => _PendingPanelState();
}

class _PendingPanelState extends State<_PendingPanel> {
  bool get _applying => widget.applying.value;

  set _applying(bool value) => widget.applying.value = value;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_applying || widget.onApply == null || widget.statements.isEmpty) return;
    final nav = Navigator.of(context);
    setState(() => _applying = true);
    try {
      await widget.onApply!();
      if (mounted) nav.pop();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _revert() {
    if (_applying) return;
    final cb = widget.onRevert;
    if (cb == null) return;
    cb();
    Navigator.of(context).pop();
  }

  void _close() {
    if (_applying) return;
    Navigator.of(context).pop();
  }

  void _copyAll() {
    final joined = widget.statements.map((s) => '$s;').join('\n\n');
    Clipboard.setData(ClipboardData(text: joined));
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): _apply,
      const SingleActivator(LogicalKeyboardKey.escape): _close,
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        // Tight box: the body needs a bounded height so the ListView can
        // render. Material ancestor gives SelectionArea / text-selection
        // toolbars somewhere to mount.
        child: SizedBox(
          width: 760,
          height: 640,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: Radii.brLg,
                border: Border.all(color: AppColors.borderStrong),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 48,
                    spreadRadius: 0,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: Radii.brLg,
                child: Column(
                  children: [
                    _Header(
                      statements: widget.statements,
                      onCopyAll: widget.statements.isEmpty ? null : _copyAll,
                      onClose: _close,
                    ),
                    Expanded(
                      child: widget.statements.isEmpty
                          ? const _EmptyBody()
                          : _StatementList(statements: widget.statements),
                    ),
                    _Footer(
                      statementCount: widget.statements.length,
                      applying: _applying,
                      onRevert: widget.onRevert == null ? null : _revert,
                      onClose: _close,
                      onApply: widget.onApply == null ? null : _apply,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header band: eyebrow + title row, then a breakdown chip row that names
/// the count by mutation kind so a glance tells you what's about to land.
class _Header extends StatelessWidget {
  const _Header({
    required this.statements,
    required this.onCopyAll,
    required this.onClose,
  });

  final List<String> statements;
  final VoidCallback? onCopyAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final breakdown = _kindBreakdown(statements);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 12, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            AppColors.bgDeep,
          ],
        ),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REVIEW',
                      style: AppTheme.eyebrow(color: AppColors.accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pending changes',
                      style: AppTheme.ui(
                        size: 16,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _HeaderIcon(
                icon: Hgi.copy01,
                tooltip: 'Copy all statements',
                onTap: onCopyAll,
              ),
              const SizedBox(width: 2),
              _HeaderIcon(
                icon: Hgi.cancel01,
                tooltip: 'Close (Esc)',
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _SummaryChip(
                count: statements.length,
                label: statements.length == 1 ? 'statement' : 'statements',
                color: AppColors.textPrimary,
                bold: true,
              ),
              const SizedBox(width: 12),
              if (breakdown.updates > 0) ...[
                _KindStat(
                  kind: _Kind.update,
                  count: breakdown.updates,
                ),
                const SizedBox(width: 10),
              ],
              if (breakdown.inserts > 0) ...[
                _KindStat(
                  kind: _Kind.insert,
                  count: breakdown.inserts,
                ),
                const SizedBox(width: 10),
              ],
              if (breakdown.deletes > 0) ...[
                _KindStat(
                  kind: _Kind.delete,
                  count: breakdown.deletes,
                ),
                const SizedBox(width: 10),
              ],
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hovering) {
          final fg = enabled
              ? (hovering ? AppColors.textPrimary : AppColors.textMuted)
              : AppColors.textMuted.withValues(alpha: 0.4);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovering && enabled
                  ? AppColors.surfaceHover
                  : AppColors.surfaceHover.withValues(alpha: 0),
              borderRadius: Radii.brSm,
            ),
            child: Icon(icon, size: 14, color: fg),
          );
        },
      ),
    );
  }
}

/// Generic count + label chip. Used for the leading total and any custom
/// "X tables" overflow tags. The kind-stat row below uses [_KindStat]
/// which adds the kind dot.
class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.count,
    required this.label,
    required this.color,
    this.bold = false,
  });

  final int count;
  final String label;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: AppTheme.mono(
            size: 13,
            color: color,
            weight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTheme.ui(
            size: 11.5,
            color: AppColors.textSecondary,
            weight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _KindStat extends StatelessWidget {
  const _KindStat({required this.kind, required this.count});

  final _Kind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: kind.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: AppTheme.mono(
            size: 11.5,
            color: AppColors.textPrimary,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          kind.label,
          style: AppTheme.ui(
            size: 11,
            color: AppColors.textMuted,
            weight: FontWeight.w500,
          ).copyWith(letterSpacing: 0.04 * 11),
        ),
      ],
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: const EmptyState(
        icon: Hgi.checkmarkCircle02,
        title: 'No pending changes',
        message:
            'Cell edits, deletes, and inserts will show up here for review '
            'before they hit the database.',
      ),
    );
  }
}

class _StatementList extends StatelessWidget {
  const _StatementList({required this.statements});

  final List<String> statements;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        itemCount: statements.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _StatementCard(index: i + 1, sql: statements[i]),
      ),
    );
  }
}

/// One pending mutation, rendered as a card with a left status stripe
/// keyed to the operation kind. The metadata row carries an ordinal chip
/// (so the user can refer to "#3 failed" in copy), the relation name in
/// mono, an optional row identifier, and an inline copy affordance.
class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.index, required this.sql});

  final int index;
  final String sql;

  static final _relRe = RegExp(
    r'(?:UPDATE|DELETE\s+FROM|INSERT\s+INTO)\s+("?[\w.]+"?\."?[\w.]+"?|"?[\w.]+"?)',
    caseSensitive: false,
  );
  static final _ctidRe = RegExp(
    r"ctid\s*=\s*'\(([\d,]+)\)'",
    caseSensitive: false,
  );
  static final _rowidRe = RegExp(
    r'rowid\s*=\s*(\d+)',
    caseSensitive: false,
  );
  static final _kindRe = RegExp(
    r'^\s*(UPDATE|DELETE|INSERT)\b',
    caseSensitive: false,
  );

  _Kind _kind() {
    final raw = _kindRe.firstMatch(sql)?.group(1)?.toUpperCase();
    return switch (raw) {
      'DELETE' => _Kind.delete,
      'INSERT' => _Kind.insert,
      _ => _Kind.update,
    };
  }

  String? _row() {
    final c = _ctidRe.firstMatch(sql)?.group(1);
    if (c != null) return 'ctid ($c)';
    final r = _rowidRe.firstMatch(sql)?.group(1);
    if (r != null) return 'rowid $r';
    return null;
  }

  void _copy() => Clipboard.setData(ClipboardData(text: sql));

  @override
  Widget build(BuildContext context) {
    final kind = _kind();
    final relation = _relRe.firstMatch(sql)?.group(1) ?? 'unknown';
    final row = _row();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: Radii.brSm,
        // IntrinsicHeight gives the cross-axis-stretch Row a tight height
        // equal to the tallest child's natural height; without it, in an
        // unbounded-height context (ListView item) the stripe Container
        // has no height to stretch into and renders 0px tall.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: kind.color),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatementMeta(
                      index: index,
                      kind: kind,
                      relation: relation,
                      row: row,
                    ),
                    Container(
                      height: 1,
                      color: AppColors.border.withValues(alpha: 0.55),
                    ),
                    _CodeBlock(sql: sql, onCopy: _copy),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementMeta extends StatelessWidget {
  const _StatementMeta({
    required this.index,
    required this.kind,
    required this.relation,
    required this.row,
  });

  final int index;
  final _Kind kind;
  final String relation;
  final String? row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        children: [
          _OrdinalChip(index: index),
          const SizedBox(width: 10),
          _KindBadge(kind: kind),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              relation,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                size: 12,
                color: AppColors.textPrimary,
                weight: FontWeight.w600,
              ),
            ),
          ),
          if (row != null) ...[
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 12,
              color: AppColors.border,
            ),
            const SizedBox(width: 10),
            Text(
              row!,
              style: AppTheme.mono(
                size: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrdinalChip extends StatelessWidget {
  const _OrdinalChip({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$index',
        style: AppTheme.mono(
          size: 10,
          color: AppColors.textMuted,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final _Kind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: kind.color.withValues(alpha: 0.32)),
      ),
      child: Text(
        kind.label,
        style: AppTheme.mono(
          size: 9.5,
          color: kind.color,
          weight: FontWeight.w700,
        ).copyWith(letterSpacing: 0.06 * 9.5),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.sql, required this.onCopy});

  final String sql;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    // `flutter_highlight` wraps RichText in a Container whose color is
    // `theme['root'].backgroundColor ?? Color(0xffffffff)` — pure white.
    // Setting backgroundColor to null falls through to that default; we
    // need an explicit `Colors.transparent` so the outer `bgDeep`
    // Container shows through the entire code area instead of being
    // covered by a white text-sized rectangle.
    final theme = {
      ...apertureCodeStyles,
      'root': TextStyle(
        color: AppColors.textPrimary,
        backgroundColor: Colors.transparent,
      ),
    };
    return Container(
      width: double.infinity,
      color: AppColors.bgDeep,
      child: Stack(
        children: [
          Padding(
            // Right padding leaves room for the floating copy button so a
            // long single-line statement doesn't collide with the chip.
            padding: const EdgeInsets.fromLTRB(14, 10, 40, 11),
            child: SelectionArea(
              child: HighlightView(
                sql,
                language: 'pgsql',
                theme: theme,
                textStyle:
                    AppTheme.mono(size: 11.5, color: AppColors.textPrimary),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _CodeCopyButton(onTap: onCopy),
          ),
        ],
      ),
    );
  }
}

/// Floating copy chip pinned to the top-right of a code block. Mirrors
/// the GitHub-gist convention so the user's hand lands on it instinctively
/// when they want to grab the statement for their own console.
class _CodeCopyButton extends StatelessWidget {
  const _CodeCopyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Copy statement',
      waitDuration: const Duration(milliseconds: 350),
      child: Hoverable(
        cursor: SystemMouseCursors.click,
        onTap: onTap,
        builder: (context, hovering) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : AppColors.surface,
            border: Border.all(
              color: hovering ? AppColors.borderStrong : AppColors.border,
            ),
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            Hgi.copy01,
            size: 12,
            color: hovering ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.statementCount,
    required this.applying,
    required this.onRevert,
    required this.onClose,
    required this.onApply,
  });

  final int statementCount;
  final bool applying;
  final VoidCallback? onRevert;
  final VoidCallback onClose;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final canApply = !applying && statementCount > 0 && onApply != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(
            Hgi.shield01,
            size: 13,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            'Runs in a single transaction',
            style: AppTheme.ui(
              size: 11.5,
              color: AppColors.textMuted,
              weight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (onRevert != null) ...[
            AppButton(
              label: 'Revert all',
              danger: true,
              onPressed: applying ? null : onRevert,
            ),
            const SizedBox(width: 8),
          ],
          AppButton(label: 'Close', onPressed: applying ? null : onClose),
          const SizedBox(width: 8),
          _ApplyButton(
            applying: applying,
            onPressed: canApply ? onApply : null,
          ),
        ],
      ),
    );
  }
}

/// Primary Apply button with an inline ⌘↵ kbd hint and a busy state that
/// swaps the icon for a spinner without changing the button width.
class _ApplyButton extends StatelessWidget {
  const _ApplyButton({required this.applying, required this.onPressed});

  final bool applying;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onPressed,
      builder: (context, hovering) {
        final Color bg = !enabled
            ? AppColors.accent.withValues(alpha: 0.35)
            : (hovering ? AppColors.accentHover : AppColors.accent);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          padding: const EdgeInsets.only(left: 10, right: 7),
          decoration: BoxDecoration(color: bg, borderRadius: Radii.brSm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: applying
                    ? const CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: Colors.white,
                      )
                    : const Icon(Hgi.tick02, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 7),
              Text(
                applying ? 'Applying…' : 'Apply',
                style: AppTheme.ui(
                  size: 12.5,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 9),
              _InlineKbd(parts: const ['⌘', '↵']),
            ],
          ),
        );
      },
    );
  }
}

class _InlineKbd extends StatelessWidget {
  const _InlineKbd({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            height: 16,
            constraints: const BoxConstraints(minWidth: 16),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              parts[i],
              textAlign: TextAlign.center,
              style: AppTheme.mono(
                size: 10,
                color: Colors.white.withValues(alpha: 0.92),
                weight: FontWeight.w500,
              ).copyWith(height: 1.0),
            ),
          ),
        ],
      ],
    );
  }
}

/// Mutation kind taxonomy: drives the left stripe color, the badge, the
/// header breakdown chip, and the relation-row icon.
enum _Kind {
  update,
  insert,
  delete,
}

extension _KindStyle on _Kind {
  String get label => switch (this) {
    _Kind.update => 'UPDATE',
    _Kind.insert => 'INSERT',
    _Kind.delete => 'DELETE',
  };

  Color get color => switch (this) {
    _Kind.update => AppColors.accent,
    _Kind.insert => AppColors.success,
    _Kind.delete => AppColors.error,
  };
}

({int updates, int inserts, int deletes}) _kindBreakdown(
  List<String> statements,
) {
  var u = 0, i = 0, d = 0;
  final re = RegExp(r'^\s*(UPDATE|DELETE|INSERT)\b', caseSensitive: false);
  for (final s in statements) {
    final m = re.firstMatch(s)?.group(1)?.toUpperCase();
    switch (m) {
      case 'UPDATE':
        u++;
        break;
      case 'INSERT':
        i++;
        break;
      case 'DELETE':
        d++;
        break;
    }
  }
  return (updates: u, inserts: i, deletes: d);
}
