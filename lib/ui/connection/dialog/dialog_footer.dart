import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'connection_test.dart';

/// Connection-dialog footer: the test-status pill on the left, the Test and
/// Create/Save actions on the right. A null [onTest] / [onSubmit] renders
/// the corresponding button disabled.
class ConnectionDialogFooter extends StatelessWidget {
  const ConnectionDialogFooter({
    super.key,
    required this.result,
    required this.isEdit,
    required this.onTest,
    required this.onSubmit,
  });

  final TestResult result;
  final bool isEdit;
  final VoidCallback? onTest;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: _TestStatusPill(result: result)),
          const SizedBox(width: 10),
          AppButton(
            label: result.status == TestStatus.busy ? 'Testing…' : 'Test',
            icon: Icons.bolt_rounded,
            onPressed: onTest,
          ),
          const SizedBox(width: 8),
          AppButton(
            label: isEdit ? 'Save' : 'Create',
            icon: isEdit ? Icons.check_rounded : Icons.add_rounded,
            primary: true,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

/// Dot + caption summarizing the most recent [TestResult].
class _TestStatusPill extends StatelessWidget {
  const _TestStatusPill({required this.result});

  final TestResult result;

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String text;
    final Color textColor;
    switch (result.status) {
      case TestStatus.idle:
        dot = AppColors.textMuted;
        text = 'Not tested yet';
        textColor = AppColors.textMuted;
        break;
      case TestStatus.busy:
        dot = AppColors.warning;
        text = 'Testing connection…';
        textColor = AppColors.textSecondary;
        break;
      case TestStatus.ok:
        dot = AppColors.success;
        final ms = result.elapsed?.inMilliseconds ?? 0;
        final v = result.version ?? '';
        text = 'Connected · ${ms}ms${v.isEmpty ? '' : ' · $v'}';
        textColor = AppColors.textSecondary;
        break;
      case TestStatus.fail:
        dot = AppColors.error;
        final m = result.message ?? 'Connection failed';
        text = m.length > 90 ? '${m.substring(0, 90)}…' : m;
        textColor = AppColors.error;
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dot,
            shape: BoxShape.circle,
            boxShadow: result.status == TestStatus.ok
                ? [BoxShadow(color: dot.withValues(alpha: 0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w500,
              color: textColor,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
