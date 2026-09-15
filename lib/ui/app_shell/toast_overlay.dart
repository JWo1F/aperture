import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/app_globals.dart';
import '../../state/toast_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../../theme/hugeicons.dart';

/// Floating-toast layer for the app shell. Anchors bottom-right, stacks
/// newest closest to the corner, and never blocks pointer events outside
/// its own cards.
///
/// Intended to be dropped into a [Stack] alongside the main shell tree —
/// the [Align] sizes itself to the full stack and positions its content
/// in the bottom-right; the [IgnorePointer]-style hit-test only matches
/// the cards themselves because the wrapping column has no painted
/// surface.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ListenableBuilder(
          listenable: appState.toasts,
          builder: (context, _) {
            final list = appState.toasts.toasts;
            if (list.isEmpty) return const SizedBox.shrink();
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final toast in list)
                    _ToastCard(
                      key: ValueKey(toast.id),
                      toast: toast,
                      onDismiss: () => appState.toasts.dismiss(toast.id),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({super.key, required this.toast, required this.onDismiss});

  final Toast toast;
  final VoidCallback onDismiss;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _curve;
  late final Animation<Offset> _slide;
  Timer? _autoDismiss;
  bool _exiting = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.18, 0),
      end: Offset.zero,
    ).animate(_curve);
    _ctrl.forward();
    _scheduleAutoDismiss();
  }

  void _scheduleAutoDismiss() {
    _autoDismiss?.cancel();
    final d = widget.toast.duration;
    if (d == null) return;
    _autoDismiss = Timer(d, _close);
  }

  Future<void> _close() async {
    if (_exiting || !mounted) return;
    _exiting = true;
    _autoDismiss?.cancel();
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  void _onEnter() {
    if (_hovering) return;
    setState(() => _hovering = true);
    _autoDismiss?.cancel();
  }

  void _onExit() {
    if (!_hovering) return;
    setState(() => _hovering = false);
    if (!_exiting) _scheduleAutoDismiss();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.bottomCenter,
      child: FadeTransition(
        opacity: _curve,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SlideTransition(
            position: _slide,
            child: MouseRegion(
              onEnter: (_) => _onEnter(),
              onExit: (_) => _onExit(),
              child: _Card(
                toast: widget.toast,
                hovering: _hovering,
                onClose: _close,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.toast,
    required this.hovering,
    required this.onClose,
  });

  final Toast toast;
  final bool hovering;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tint = _severityColor(toast.severity);
    final icon = _severityIcon(toast.severity);
    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 380),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brMd,
        border: Border.all(
          color: hovering ? AppColors.borderStrong : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: Radii.brMd,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: tint),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(icon, size: 15, color: tint),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (toast.title != null) ...[
                              Text(
                                toast.title!,
                                style: AppTheme.ui(
                                  size: 12.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                            ],
                            Text(
                              toast.message,
                              style: AppTheme.ui(
                                size: 12,
                                weight: FontWeight.w400,
                                color: toast.title != null
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _CloseButton(onTap: onClose),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
      builder: (ctx, hovering) {
        return Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering ? AppColors.surfaceHover : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            Hgi.cancel01,
            size: 13,
            color: hovering ? AppColors.textPrimary : AppColors.textMuted,
          ),
        );
      },
    );
  }
}

Color _severityColor(ToastSeverity s) => switch (s) {
  ToastSeverity.info => AppColors.info,
  ToastSeverity.success => AppColors.success,
  ToastSeverity.warning => AppColors.warning,
  ToastSeverity.error => AppColors.error,
};

IconData _severityIcon(ToastSeverity s) => switch (s) {
  ToastSeverity.info => Hgi.informationCircle,
  ToastSeverity.success => Hgi.checkmarkCircle02,
  ToastSeverity.warning => Hgi.alert02,
  ToastSeverity.error => Hgi.alertCircle,
};
