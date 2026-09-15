import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Asks whether to quit with [pending] un-applied mutations still staged.
/// Returns true to go ahead and quit.
///
/// Called from `AppLifecycleListener.onExitRequested`, which is the one
/// chokepoint every quit passes through — ⌘Q, the app menu, the Dock, and a
/// logout all arrive there. Guarding the ⌘Q keystroke alone left every other
/// route discarding staged edits without a word.
Future<bool> confirmQuitWithPendingEdits(
  BuildContext context,
  int pending,
) async {
  final keepEditing = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Quit Aperture?',
        style: AppTheme.ui(
          size: 14,
          weight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: Text(
        'You have $pending pending edit${pending == 1 ? '' : 's'}. '
        "Quitting now discards them — they aren't on the server yet.",
        style: AppTheme.ui(color: AppColors.textSecondary),
      ),
      actions: [
        AppButton(
          label: 'Keep editing',
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        AppButton(
          label: 'Quit anyway',
          danger: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ],
    ),
  );
  // A dismissed barrier reads as "don't quit" — the safe side of a choice
  // whose other branch throws away work.
  return keepEditing == false;
}
