import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hugeicons.dart';
import '../../widgets/common.dart';
import '../../widgets/segmented_choice.dart';
import 'connection_form_model.dart';
import 'form_widgets.dart';

const String _credentialPasswordHelp = "Saved with Aperture's settings.";
const String _credentialCommandHelp =
    'Runs in your login shell on every connect; what it prints is the '
    'password.';

/// The scrollable form body of the connection dialog. Reads and mutates a
/// [ConnectionFormModel]; file-picking and the SSL menu are delegated back
/// to the owning dialog through the [onPickFile] and [onCreateFile]
/// callbacks since they need the dialog's render context.
class ConnectionDialogBody extends StatelessWidget {
  const ConnectionDialogBody({
    super.key,
    required this.model,
    required this.onPickFile,
    required this.onCreateFile,
  });

  final ConnectionFormModel model;
  final VoidCallback onPickFile;
  final VoidCallback onCreateFile;

  @override
  Widget build(BuildContext context) {
    final isSqlite = model.engine == DbEngine.sqlite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EngineToggle(value: model.engine, onChanged: (v) => model.engine = v),
        const SizedBox(height: 18),
        LabeledField(
          label: 'Display name',
          child: BoxedTextInput(
            controller: model.name,
            hint: isSqlite ? 'My local database' : 'Production · users',
            autofocus: true,
          ),
        ),
        const SizedBox(height: 14),
        if (isSqlite)
          _fileField()
        else ...[
          _hostPort(),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Database',
            child: BoxedTextInput(controller: model.database, hint: 'postgres'),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'User',
            child: BoxedTextInput(controller: model.username, hint: 'postgres'),
          ),
          const SizedBox(height: 14),
          _passwordField(),
          const SizedBox(height: 14),
          _tlsField(),
        ],
        const SizedBox(height: 18),
        const DividerLabel(label: 'Appearance & access'),
        const SizedBox(height: 14),
        _colorField(),
        const SizedBox(height: 16),
        _readOnlyRow(),
      ],
    );
  }

  Widget _hostPort() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: LabeledField(
            label: 'Host',
            child: BoxedTextInput(controller: model.host, hint: 'localhost'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: LabeledField(
            label: 'Port',
            child: BoxedTextInput(
              controller: model.port,
              hint: '5432',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fileField() {
    return LabeledField(
      label: 'Database file',
      hint: 'SQLite file opened directly — no server needed.',
      child: BoxedTextInput(
        controller: model.filePath,
        hint: '/path/to/database.sqlite',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineAction(icon: Hgi.add01, label: 'New', onTap: onCreateFile),
            const SizedBox(width: 4),
            InlineAction(
              icon: Hgi.folderOpen,
              label: 'Browse',
              onTap: onPickFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField() {
    final isCommand = model.credentialMode == CredentialMode.command;
    final Widget input;
    if (isCommand) {
      input = BoxedTextInput(
        controller: model.command,
        hint: "op read 'op://Vault/Item/password'",
      );
    } else {
      input = BoxedTextInput(
        controller: model.password,
        obscure: !model.showPassword,
        hint: 'Password',
        trailing: GhostIconButton(
          icon: model.showPassword ? Hgi.viewOff : Hgi.view,
          onTap: () => model.showPassword = !model.showPassword,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              isCommand ? 'Password command' : 'Password',
              style: fieldLabelStyle,
            ),
            const Spacer(),
            SegmentedChoice<CredentialMode>(
              value: model.credentialMode,
              onChanged: (v) => model.credentialMode = v,
              options: const [
                (CredentialMode.password, 'Password'),
                (CredentialMode.command, 'Command'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 7),
        input,
        const SizedBox(height: 6),
        Text(
          isCommand ? _credentialCommandHelp : _credentialPasswordHelp,
          style: fieldHintStyle,
        ),
      ],
    );
  }

  Widget _tlsField() {
    final hint = switch (model.tls) {
      TlsMode.off =>
        'Not encrypted: the password crosses the network readable.',
      TlsMode.require => 'Encrypted, but any server certificate is accepted.',
      TlsMode.verify =>
        'Encrypted, and the certificate must be trusted by macOS and match '
            'the host.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('SSL / TLS', style: fieldLabelStyle),
            const Spacer(),
            SegmentedChoice<TlsMode>(
              value: model.tls,
              onChanged: (v) => model.tls = v,
              options: const [
                (TlsMode.off, 'Off'),
                (TlsMode.require, 'Require'),
                (TlsMode.verify, 'Verify'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              model.tls == TlsMode.off ? Hgi.lockOpen : Hgi.lock,
              size: 12,
              color: model.tls == TlsMode.off
                  ? AppColors.warning
                  : AppColors.success,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(hint, style: fieldHintStyle)),
          ],
        ),
      ],
    );
  }

  Widget _colorField() {
    return LabeledField(
      label: 'Connection color',
      hint: 'Tints the sidebar and chips so this database is easy to spot.',
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: 11,
          runSpacing: 10,
          children: [
            for (final c in kConnectionColors)
              ColorSwatchButton(
                color: c,
                selected: c.toARGB32() == model.color.toARGB32(),
                onTap: () => model.color = c,
              ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyRow() {
    return Hoverable(
      onTap: () => model.readOnly = !model.readOnly,
      builder: (_, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceAlt : AppColors.bg,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: model.readOnly ? AppColors.accentRing : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Hgi.shield01,
              size: 16,
              color: model.readOnly ? AppColors.accent : AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Read-only mode',
                    style: AppTheme.ui(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Blocks UPDATE, DELETE and cell edits.',
                    style: fieldHintStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PillToggle(
              value: model.readOnly,
              onChanged: (v) => model.readOnly = v,
            ),
          ],
        ),
      ),
    );
  }
}
