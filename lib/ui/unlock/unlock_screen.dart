import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/store_database.dart';
import '../../state/app_globals.dart';
import '../../theme/app_theme.dart';
import '../../theme/hugeicons.dart';
import '../widgets/common.dart';
import 'passphrase_widgets.dart';

const _windowChannel = MethodChannel('aperture/window');

/// Shown before anything else while the settings store is sealed: unlock
/// it, or — when there is no store yet — choose the passphrase that will
/// seal it.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();

  /// Null until the store's existence is known.
  bool? _exists;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    appState.storeExists().then((exists) {
      if (mounted) setState(() => _exists = exists);
    });
  }

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final creating = _exists == false;
    final passphrase = _passphrase.text;
    if (passphrase.isEmpty) {
      setState(() => _error = 'Enter a passphrase.');
      return;
    }
    if (creating && passphrase != _confirm.text) {
      setState(() => _error = "The passphrases don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Key derivation blocks the isolate for a few hundred milliseconds;
    // let the busy state paint first.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    try {
      await appState.unlockStore(passphrase, remember: _remember);
    } on WrongPassphraseException {
      _fail('Wrong passphrase.');
    } catch (e) {
      _fail("Couldn't open the settings: $e");
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
    _passphrase.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _passphrase.text.length,
    );
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => const _EraseDialog(),
    );
    if (confirmed != true) return;
    await appState.eraseStore();
    if (!mounted) return;
    setState(() {
      _exists = false;
      _error = null;
      _passphrase.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exists = _exists;
    // The app root rather than a route inside AppShell, so it supplies the
    // Material its text fields need.
    return Material(
      color: AppColors.bg,
      child: Stack(
        children: [
          // The window has no title bar; this strip is where it drags.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 36,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => _windowChannel.invokeMethod('startDrag'),
              onDoubleTap: () => _windowChannel.invokeMethod('toggleZoom'),
            ),
          ),
          if (exists != null)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _form(creating: !exists),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _form({required bool creating}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: Image.asset(
              'assets/brand/app_icon.png',
              width: 72,
              height: 72,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          creating ? 'Protect your settings' : 'Unlock Aperture',
          textAlign: TextAlign.center,
          style: AppTheme.ui(
            size: 20,
            weight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          creating
              ? 'Connections, passwords and saved queries are encrypted with '
                    'this passphrase. It cannot be recovered — if you lose '
                    'it, the settings are gone.'
              : 'Enter the passphrase your settings are encrypted with.',
          textAlign: TextAlign.center,
          style: AppTheme.ui(
            size: 12.5,
            weight: FontWeight.w400,
            color: AppColors.textSecondary,
            letterSpacing: 0,
          ).copyWith(height: 1.45),
        ),
        const SizedBox(height: 22),
        PassphraseField(
          controller: _passphrase,
          hint: creating ? 'New passphrase' : 'Passphrase',
          autofocus: true,
          onSubmitted: (_) =>
              creating ? FocusScope.of(context).nextFocus() : _submit(),
        ),
        if (creating) ...[
          const SizedBox(height: 8),
          PassphraseField(
            controller: _confirm,
            hint: 'Repeat passphrase',
            onSubmitted: (_) => _submit(),
          ),
        ],
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
        const SizedBox(height: 18),
        AppButton(
          label: _busy
              ? (creating ? 'Encrypting…' : 'Unlocking…')
              : (creating ? 'Encrypt settings' : 'Unlock'),
          icon: creating ? Hgi.lockKey : Hgi.lockOpen,
          primary: true,
          onPressed: _busy ? null : _submit,
        ),
        if (!creating) ...[
          const SizedBox(height: 18),
          Center(
            child: Hoverable(
              onTap: _busy ? null : _reset,
              builder: (context, hovering) => Text(
                'Forgot the passphrase?',
                style: AppTheme.ui(
                  size: 11.5,
                  weight: FontWeight.w400,
                  color: hovering ? AppColors.error : AppColors.textMuted,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EraseDialog extends StatelessWidget {
  const _EraseDialog();

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
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Erase all settings?',
                style: AppTheme.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Without the passphrase the settings cannot be decrypted. '
                'Erasing deletes every saved connection, password, query '
                'and preference, and lets you start over with a new '
                'passphrase. Your databases themselves are not touched.',
                style: AppTheme.ui(
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: AppColors.textSecondary,
                  letterSpacing: 0,
                ).copyWith(height: 1.45),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Erase settings',
                    primary: true,
                    danger: true,
                    onPressed: () => Navigator.of(context).pop(true),
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
