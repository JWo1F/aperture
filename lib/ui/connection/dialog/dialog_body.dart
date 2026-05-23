import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'connection_form_model.dart';
import 'form_widgets.dart';

const String _credentialPlainHelp = 'Saved as plain text in store.json.';
const String _credentialEncryptedHelp =
    'Encrypted with your master passphrase (AES-GCM).';
const String _credentialOnePasswordHelp =
    'Resolved from the 1Password CLI each time you connect.';

/// The scrollable form body of the connection dialog. Reads and mutates a
/// [ConnectionFormModel]; file-picking and the SSL menu are delegated back
/// to the owning dialog through the [onPickFile], [onCreateFile] and
/// [onOpenSslMenu] callbacks since they need the dialog's render context.
class ConnectionDialogBody extends StatelessWidget {
  const ConnectionDialogBody({
    super.key,
    required this.model,
    required this.onPickFile,
    required this.onCreateFile,
    required this.onOpenSslMenu,
  });

  final ConnectionFormModel model;
  final VoidCallback onPickFile;
  final VoidCallback onCreateFile;
  final VoidCallback onOpenSslMenu;

  @override
  Widget build(BuildContext context) {
    final isSqlite = model.engine == DbEngine.sqlite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EngineToggle(
          value: model.engine,
          onChanged: (v) => model.engine = v,
        ),
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
          _sslField(),
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
            InlineAction(
              icon: Icons.add_rounded,
              label: 'New',
              onTap: onCreateFile,
            ),
            const SizedBox(width: 4),
            InlineAction(
              icon: Icons.folder_open_rounded,
              label: 'Browse',
              onTap: onPickFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField() {
    final isOnePassword = model.credentialMode == CredentialMode.onePassword;
    final helper = switch (model.credentialMode) {
      CredentialMode.plain => _credentialPlainHelp,
      CredentialMode.encrypted => _credentialEncryptedHelp,
      CredentialMode.onePassword => _credentialOnePasswordHelp,
    };
    final keepHint = model.credentialMode == CredentialMode.encrypted &&
        model.hasExistingCipher;

    final Widget input;
    if (isOnePassword) {
      input = BoxedTextInput(
        controller: model.opSecretRef,
        hint: 'op://Vault/Item/password',
      );
    } else {
      input = BoxedTextInput(
        controller: model.password,
        obscure: !model.showPassword,
        hint: keepHint ? 'Leave blank to keep current' : 'Password',
        trailing: GhostIconButton(
          icon: model.showPassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
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
              isOnePassword ? '1Password secret' : 'Password',
              style: fieldLabelStyle,
            ),
            const Spacer(),
            CredentialModeToggle(
              value: model.credentialMode,
              onChanged: (v) => model.credentialMode = v,
            ),
          ],
        ),
        const SizedBox(height: 7),
        input,
        const SizedBox(height: 6),
        Text(helper, style: fieldHintStyle),
      ],
    );
  }

  Widget _sslField() {
    final secure = model.sslMode != 'disable';
    return LabeledField(
      label: 'SSL mode',
      child: BoxedSelect(
        icon: secure ? Icons.lock_rounded : Icons.lock_open_rounded,
        iconColor: secure ? AppColors.accent : AppColors.textMuted,
        label: model.sslMode,
        onTap: onOpenSslMenu,
      ),
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
              model.readOnly ? Icons.shield_rounded : Icons.shield_outlined,
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
