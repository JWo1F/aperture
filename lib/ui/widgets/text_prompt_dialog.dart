import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import 'common.dart';

/// Show a small modal with one labelled text field plus Cancel / action
/// buttons. Resolves to the entered string (caller decides what to do with
/// empty / whitespace input) or null if dismissed.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String initial,
  String actionLabel = 'OK',
  IconData? actionIcon = Hgi.tick02,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      initial: initial,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    required this.actionLabel,
    required this.actionIcon,
  });

  final String title;
  final String initial;
  final String actionLabel;
  final IconData? actionIcon;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

/// Owns the [TextEditingController]. Keeping it in a [State.dispose] frees
/// it after Flutter has fully torn down the dialog's subtree — disposing
/// it inline after [showDialog] returned would race the closing animation's
/// last `didUpdateWidget` pass and trip "used after being disposed".
class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.brLg,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: AppTheme.ui(size: 13.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _controller,
                autofocus: true,
                cursorColor: AppColors.accent,
                style: AppTheme.ui(size: 13),
                onSubmitted: (v) => Navigator.of(context).pop(v),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: Radii.brSm,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: Radii.brSm,
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: Insets.sm),
                  AppButton(
                    label: widget.actionLabel,
                    icon: widget.actionIcon,
                    primary: true,
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
