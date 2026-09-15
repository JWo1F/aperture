import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Asks before an action throws away [pending] un-applied mutations.
/// Returns true to go ahead.
///
/// One prompt for every route that can lose staged work: quitting,
/// closing a tab, disconnecting, and switching to another connection.
/// Only the quit route used to ask, so the other three discarded the same
/// edits without a word.
///
/// [action] completes the sentence "…discards them" — pass a short phrase
/// naming what the user is about to do.
Future<bool> confirmDiscardEdits(
  BuildContext context, {
  required int pending,
  required String title,
  required String action,
  required String proceedLabel,
}) async {
  final keepEditing = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        title,
        style: AppTheme.ui(
          size: 14,
          weight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      content: Text(
        'You have $pending pending edit${pending == 1 ? '' : 's'}. '
        "$action discards them — they aren't on the server yet.",
        style: AppTheme.ui(color: AppColors.textSecondary),
      ),
      actions: [
        AppButton(
          label: 'Keep editing',
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
        AppButton(
          label: proceedLabel,
          danger: true,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ],
    ),
  );
  // A dismissed barrier reads as "don't" — the safe side of a choice whose
  // other branch throws away work.
  return keepEditing == false;
}
