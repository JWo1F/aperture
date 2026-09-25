import 'package:flutter/material.dart';

import '../../services/store_database.dart';
import '../../state/app_globals.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'passphrase_widgets.dart';

/// Re-encrypts the settings store under a new passphrase.
Future<void> showChangePassphraseDialog(BuildContext context) async {
  final remembered = await appState.isPassphraseRemembered();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => _ChangePassphraseDialog(remembered: remembered),
  );
}

class _ChangePassphraseDialog extends StatefulWidget {
  const _ChangePassphraseDialog({required this.remembered});

  final bool remembered;

  @override
  State<_ChangePassphraseDialog> createState() =>
      _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState extends State<_ChangePassphraseDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  late bool _remember = widget.remembered;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_next.text.isEmpty) {
      setState(() => _error = 'Enter a new passphrase.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = "The new passphrases don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Checking the current passphrase and re-encrypting both derive keys,
    // which blocks the isolate; let the busy state paint first.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    try {
      await appState.changeStorePassphrase(
        _current.text,
        _next.text,
        remember: _remember,
      );
    } on WrongPassphraseException {
      _fail('The current passphrase is wrong.');
      return;
    } catch (e) {
      _fail("Couldn't change the passphrase: $e");
      return;
    }
    appState.toasts.info('Settings re-encrypted', title: 'Passphrase changed');
    if (mounted) Navigator.of(context).pop();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Change settings passphrase',
                style: AppTheme.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Every connection, password and saved query is re-encrypted '
                'under the new passphrase.',
                style: AppTheme.ui(
                  size: 12,
                  weight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              PassphraseField(
                controller: _current,
                hint: 'Current passphrase',
                autofocus: true,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 8),
              PassphraseField(
                controller: _next,
                hint: 'New passphrase',
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              const SizedBox(height: 8),
              PassphraseField(
                controller: _confirm,
                hint: 'Repeat new passphrase',
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              RememberToggle(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AppTheme.ui(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.error,
                    letterSpacing: 0,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: _busy ? 'Re-encrypting…' : 'Change passphrase',
                    primary: true,
                    onPressed: _busy ? null : _submit,
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
