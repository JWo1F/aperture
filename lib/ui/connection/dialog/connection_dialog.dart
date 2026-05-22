import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/connection_config.dart';
import '../../../services/one_password_client.dart';
import '../../../services/sqlite_service.dart';
import '../../../state/master_passphrase.dart';
import '../../../theme/app_theme.dart';
import '../master_passphrase_setup.dart';
import 'connection_form_model.dart';
import 'connection_test.dart';
import 'dialog_body.dart';
import 'dialog_footer.dart';
import 'dialog_header.dart';

/// Modal form for creating or editing a saved connection. Resolves to the
/// resulting [ConnectionConfig], or null if dismissed.
Future<ConnectionConfig?> showConnectionDialog(
  BuildContext context, {
  ConnectionConfig? existing,
}) {
  final masterPassphrase = context.read<MasterPassphrase>();
  return showDialog<ConnectionConfig>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => _ConnectionDialog(
      existing: existing,
      masterPassphrase: masterPassphrase,
    ),
  );
}

const List<String> _sslModes = [
  'disable',
  'allow',
  'prefer',
  'require',
  'verify-ca',
  'verify-full',
];

const _sqliteTypeGroup = XTypeGroup(
  label: 'SQLite database',
  extensions: ['db', 'sqlite', 'sqlite3', 'db3'],
);

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({this.existing, required this.masterPassphrase});

  final ConnectionConfig? existing;
  final MasterPassphrase masterPassphrase;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final ConnectionFormModel _model;
  final OnePasswordClient _op = OnePasswordClient();
  TestResult _testResult = const TestResult.idle();

  @override
  void initState() {
    super.initState();
    _model = ConnectionFormModel(existing: widget.existing);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_model.valid) return;
    if (_model.credentialSource == CredentialSource.encrypted) {
      // First-time encrypted save: make sure a master passphrase is set
      // up. The setup modal both creates the verifier and leaves the
      // session unlocked, so we can encrypt immediately afterwards.
      if (!widget.masterPassphrase.isConfigured) {
        final ok = await showMasterPassphraseSetup(
          context,
          widget.masterPassphrase,
        );
        if (!ok) return;
      } else if (!widget.masterPassphrase.isUnlocked) {
        final ok = await showMasterPassphraseUnlock(
          context,
          widget.masterPassphrase,
        );
        if (!ok) return;
      }
      // A typed password is encrypted now; an empty field keeps whatever
      // cipher the connection already had.
      final cipher = _model.password.text.isNotEmpty
          ? widget.masterPassphrase.encrypt(_model.password.text)
          : widget.existing?.passwordCipher;
      if (!mounted) return;
      Navigator.of(context).pop(_model.buildConfig(overrideCipher: cipher));
      return;
    }
    Navigator.of(context).pop(_model.buildConfig());
  }

  Future<void> _testConnection() async {
    if (!_model.valid || _testResult.status == TestStatus.busy) return;
    setState(() => _testResult = const TestResult.busy());
    final result = await runConnectionTest(_model.buildConfig(), _op);
    if (!mounted) return;
    setState(() => _testResult = result);
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [_sqliteTypeGroup],
    );
    if (file != null && mounted) _model.filePath.text = file.path;
  }

  Future<void> _createFile() async {
    final location = await getSaveLocation(
      suggestedName: 'database.sqlite',
      acceptedTypeGroups: const [_sqliteTypeGroup],
    );
    if (location == null || !mounted) return;
    try {
      SqliteService.createDatabaseFile(location.path);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _testResult = TestResult(
          status: TestStatus.fail,
          message: 'Could not create database: $err',
        );
      });
      return;
    }
    _model.filePath.text = location.path;
  }

  Future<void> _openSslMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final picked = await showMenu<String>(
      context: context,
      color: AppColors.surfaceAlt,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.brSm,
        side: BorderSide(color: AppColors.borderStrong),
      ),
      position: RelativeRect.fromLTRB(
        box.size.width / 2 - 100,
        box.size.height / 2,
        box.size.width / 2 + 100,
        box.size.height / 2 + 200,
      ),
      items: [
        for (final m in _sslModes)
          PopupMenuItem<String>(
            value: m,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  m == _model.sslMode ? Icons.check_rounded : Icons.circle,
                  size: m == _model.sslMode ? 14 : 4,
                  color: m == _model.sslMode
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  m,
                  style: AppTheme.ui(
                    size: 12.5,
                    color: AppColors.textPrimary,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (picked != null && mounted) _model.sslMode = picked;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brLg,
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 48,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: Radii.brLg,
            child: AnimatedBuilder(
              animation: _model,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConnectionDialogHeader(
                    isEdit: _model.isEdit,
                    engine: _model.engine,
                    tint: _model.color,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      child: ConnectionDialogBody(
                        model: _model,
                        onPickFile: _pickFile,
                        onCreateFile: _createFile,
                        onOpenSslMenu: _openSslMenu,
                      ),
                    ),
                  ),
                  ConnectionDialogFooter(
                    result: _testResult,
                    isEdit: _model.isEdit,
                    onTest:
                        _model.valid &&
                            _testResult.status != TestStatus.busy
                        ? _testConnection
                        : null,
                    onSubmit: _model.valid ? _submit : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
