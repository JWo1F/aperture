import 'package:flutter/material.dart';

import '../../state/app_globals.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Opens the master-passphrase setup modal. Returns true if the user
/// set a passphrase, false if they cancelled.
Future<bool> showMasterPassphraseSetup(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => const _PassphrasePanel(mode: _Mode.setup),
  );
  return ok ?? false;
}

/// Opens the master-passphrase unlock modal. Returns true if the
/// session is now unlocked, false if the user cancelled.
Future<bool> showMasterPassphraseUnlock(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => const _PassphrasePanel(mode: _Mode.unlock),
  );
  return ok ?? false;
}

enum _Mode { setup, unlock }

class _PassphrasePanel extends StatefulWidget {
  const _PassphrasePanel({required this.mode});

  final _Mode mode;

  @override
  State<_PassphrasePanel> createState() => _PassphrasePanelState();
}

class _PassphrasePanelState extends State<_PassphrasePanel> {
  final _first = TextEditingController();
  final _confirm = TextEditingController();
  final _firstFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _firstFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _first.dispose();
    _confirm.dispose();
    _firstFocus.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_first.text.isEmpty) return false;
    if (widget.mode == _Mode.setup) {
      if (_first.text.length < 6) return false;
      if (_first.text != _confirm.text) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = widget.mode == _Mode.setup
        ? await appState.store.setupPassphrase(_first.text)
        : await appState.store.unlockPassphrase(_first.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = widget.mode == _Mode.setup
          ? 'Could not set passphrase. A passphrase may already be configured.'
          : 'Wrong passphrase.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSetup = widget.mode == _Mode.setup;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brLg,
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 48,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: Radii.brLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(isSetup),
                _body(isSetup),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool isSetup) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.accentRing),
            ),
            alignment: Alignment.center,
            child: Icon(
              isSetup ? Icons.lock_outline : Icons.lock_open_outlined,
              size: 16,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isSetup ? 'Set master passphrase' : 'Unlock saved passwords',
            style: AppTheme.ui(
              size: 15,
              weight: FontWeight.w600,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconAction(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  Widget _body(bool isSetup) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isSetup
                ? 'Used to encrypt saved connection passwords. You\'ll be '
                      'asked for it the first time you open an encrypted '
                      'connection in each session. Forgetting it means losing '
                      'access to those passwords.'
                : 'Enter the master passphrase to decrypt saved connection '
                      'passwords for this session.',
            style: AppTheme.ui(size: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          _field(
            label: isSetup ? 'PASSPHRASE' : 'MASTER PASSPHRASE',
            controller: _first,
            focusNode: _firstFocus,
            onSubmitted: (_) => isSetup ? null : _submit(),
          ),
          if (isSetup) ...[
            const SizedBox(height: 12),
            _field(
              label: 'CONFIRM',
              controller: _confirm,
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: AppTheme.ui(size: 12, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.mono(
            size: 10.5,
            color: AppColors.textMuted,
            weight: FontWeight.w500,
          ).copyWith(letterSpacing: 1.1),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: true,
            obscuringCharacter: '•',
            onChanged: (_) => setState(() {}),
            onSubmitted: onSubmitted,
            style: AppTheme.mono(size: 13, color: AppColors.textPrimary),
            cursorColor: AppColors.accent,
            cursorWidth: 1.5,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    final isSetup = widget.mode == _Mode.setup;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (isSetup)
            Text(
              'minimum 6 characters',
              style: AppTheme.mono(size: 11, color: AppColors.textMuted),
            ),
          const Spacer(),
          AppButton(
            label: 'Cancel',
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: isSetup
                ? (_busy ? 'Setting…' : 'Set passphrase')
                : (_busy ? 'Unlocking…' : 'Unlock'),
            icon: isSetup ? Icons.lock_outline : Icons.lock_open_outlined,
            primary: true,
            onPressed: _valid && !_busy ? _submit : null,
          ),
        ],
      ),
    );
  }
}
