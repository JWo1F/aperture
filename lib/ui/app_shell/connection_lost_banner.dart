import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/session_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Slim banner shown above the workspace while a live connection has
/// dropped — surfaces the error and a Reconnect action.
class ConnectionLostBanner extends StatefulWidget {
  const ConnectionLostBanner({super.key});

  @override
  State<ConnectionLostBanner> createState() => _ConnectionLostBannerState();
}

class _ConnectionLostBannerState extends State<ConnectionLostBanner> {
  bool _reconnecting = false;

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      await context.read<AppState>().reconnect();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = context.read<SessionController>().error;
    return Container(
      color: AppColors.accent.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.link_off, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error == null
                  ? 'Connection lost. Your workspace is preserved.'
                  : 'Connection lost: $error',
              style: AppTheme.ui(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: _reconnecting ? 'Reconnecting…' : 'Reconnect',
            onPressed: _reconnecting ? null : _reconnect,
            primary: true,
          ),
        ],
      ),
    );
  }
}
