import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../services/password_command.dart';
import '../../../services/sqlite_service.dart';
import '../../../theme/app_theme.dart';
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
  return showDialog<ConnectionConfig>(
    context: context,
    barrierColor: AppColors.scrim,
    // The form holds a host, port, database, user and password. A stray
    // click on the sidebar behind it used to throw all of that away with
    // no prompt and no way back; the footer's Cancel is the way out.
    barrierDismissible: false,
    builder: (_) => _ConnectionDialog(existing: existing),
  );
}

const _sqliteTypeGroup = XTypeGroup(
  label: 'SQLite database',
  extensions: ['db', 'sqlite', 'sqlite3', 'db3'],
);

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({this.existing});

  final ConnectionConfig? existing;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final ConnectionFormModel _model;
  final PasswordCommand _command = PasswordCommand();
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

  void _submit() {
    if (!_model.valid) return;
    Navigator.of(context).pop(_model.buildConfig());
  }

  Future<void> _testConnection() async {
    if (!_model.valid || _testResult.status == TestStatus.busy) return;
    setState(() => _testResult = const TestResult.busy());
    final result = await runConnectionTest(_model.buildConfig(), _command);
    if (!mounted) return;
    setState(() => _testResult = result);
  }

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [_sqliteTypeGroup]);
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
                      ),
                    ),
                  ),
                  ConnectionDialogFooter(
                    result: _testResult,
                    isEdit: _model.isEdit,
                    onTest:
                        _model.valid && _testResult.status != TestStatus.busy
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
