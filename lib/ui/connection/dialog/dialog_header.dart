import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';

/// Connection-dialog header: a tinted glyph that previews the chosen
/// connection color, the title, the engine subtitle, and a close button.
class ConnectionDialogHeader extends StatelessWidget {
  const ConnectionDialogHeader({
    super.key,
    required this.isEdit,
    required this.engine,
    required this.tint,
    required this.onClose,
  });

  final bool isEdit;
  final DbEngine engine;
  final Color tint;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.10), AppColors.surface],
          stops: const [0.0, 0.7],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.16),
              borderRadius: Radii.brSm,
              border: Border.all(color: tint.withValues(alpha: 0.55)),
            ),
            alignment: Alignment.center,
            child: Icon(
              engine == DbEngine.sqlite
                  ? Hgi.file01
                  : Hgi.serverStack01,
              size: 17,
              color: tint,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEdit ? 'Edit connection' : 'New connection',
                style: AppTheme.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                engine == DbEngine.sqlite
                    ? 'Local SQLite file'
                    : 'PostgreSQL server',
                style: AppTheme.ui(
                  size: 11,
                  weight: FontWeight.w400,
                  color: AppColors.textMuted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconAction(
            icon: Hgi.cancel01,
            tooltip: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
