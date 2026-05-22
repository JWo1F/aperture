import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/connection_config.dart';
import '../../services/db_service.dart';
import '../../services/one_password_client.dart';
import '../../services/sqlite_service.dart';
import '../../state/app_state.dart';
import '../../state/master_passphrase.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'master_passphrase_setup.dart';

/// Modal form for creating or editing a saved connection. Resolves to the
/// resulting [ConnectionConfig], or null if dismissed.
Future<ConnectionConfig?> showConnectionDialog(
  BuildContext context, {
  ConnectionConfig? existing,
}) {
  final state = context.read<AppState>();
  return showDialog<ConnectionConfig>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _ConnectionDialog(
      existing: existing,
      masterPassphrase: state.masterPassphrase,
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

enum _TestStatus { idle, busy, ok, fail }

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({
    this.existing,
    required this.masterPassphrase,
  });

  final ConnectionConfig? existing;
  final MasterPassphrase masterPassphrase;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _database;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _opSecretRef;
  late final TextEditingController _filePath;

  late DbEngine _engine;
  late String _sslMode;
  late Color _color;
  late bool _readOnly;
  bool _showPassword = false;
  late CredentialSource _credentialSource;

  _TestStatus _testStatus = _TestStatus.idle;
  String? _testMessage;
  Duration? _testElapsed;
  String? _serverVersion;

  final OnePasswordClient _op = OnePasswordClient();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? 'localhost');
    _port = TextEditingController(text: (e?.port ?? 5432).toString());
    _database = TextEditingController(text: e?.database ?? '');
    _username = TextEditingController(text: e?.username ?? 'postgres');
    _password = TextEditingController(text: e?.password ?? '');
    _opSecretRef = TextEditingController(text: e?.opSecretRef ?? '');
    _filePath = TextEditingController(text: e?.filePath ?? '');
    _engine = e?.engine ?? DbEngine.postgres;
    _sslMode = (e?.useSsl ?? false) ? 'require' : 'disable';
    _color = e?.color != null ? Color(e!.color!) : kConnectionColors.first;
    _readOnly = e?.readOnly ?? false;
    _credentialSource = e?.credentialSource ?? CredentialSource.plain;

    for (final c in [
      _name,
      _host,
      _port,
      _database,
      _username,
      _password,
      _opSecretRef,
      _filePath,
    ]) {
      c.addListener(_onAnyFieldChanged);
    }
  }

  void _onAnyFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _database,
      _username,
      _password,
      _opSecretRef,
      _filePath,
    ]) {
      c.removeListener(_onAnyFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    if (_engine == DbEngine.sqlite) {
      return _filePath.text.trim().isNotEmpty;
    }
    final base =
        _host.text.trim().isNotEmpty &&
        _database.text.trim().isNotEmpty &&
        _username.text.trim().isNotEmpty &&
        int.tryParse(_port.text.trim()) != null;
    if (!base) return false;
    if (_credentialSource == CredentialSource.onePassword) {
      return _opSecretRef.text.trim().startsWith('op://');
    }
    return true;
  }

  ConnectionConfig _buildConfig({String? overrideCipher}) {
    if (_engine == DbEngine.sqlite) {
      final path = _filePath.text.trim();
      final base = path.isEmpty ? 'database' : path.split('/').last;
      final name = _name.text.trim().isEmpty ? base : _name.text.trim();
      return ConnectionConfig(
        id:
            widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        engine: DbEngine.sqlite,
        filePath: path,
        // Surfaced as the connection's display label in the sidebar header.
        database: base,
        color: _color.toARGB32(),
        readOnly: _readOnly,
      );
    }
    final host = _host.text.trim();
    final db = _database.text.trim();
    final name = _name.text.trim().isEmpty ? '$db @ $host' : _name.text.trim();
    final ref = _opSecretRef.text.trim();
    final isEncrypted = _credentialSource == CredentialSource.encrypted;
    final isOnePassword = _credentialSource == CredentialSource.onePassword;
    return ConnectionConfig(
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      host: host,
      port: int.parse(_port.text.trim()),
      database: db,
      username: _username.text.trim(),
      // Plain holds the password inline; encrypted moves it to
      // passwordCipher; 1Password keeps neither field populated.
      password: _credentialSource == CredentialSource.plain
          ? _password.text
          : '',
      useSsl: _sslMode != 'disable',
      color: _color.toARGB32(),
      readOnly: _readOnly,
      credentialSource: _credentialSource,
      passwordCipher: isEncrypted
          ? (overrideCipher ?? widget.existing?.passwordCipher)
          : null,
      opSecretRef: isOnePassword && ref.isNotEmpty ? ref : null,
    );
  }

  Future<void> _submit() async {
    if (!_valid) return;
    if (_credentialSource == CredentialSource.encrypted) {
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
      String? cipher;
      if (_password.text.isNotEmpty) {
        cipher = widget.masterPassphrase.encrypt(_password.text);
      } else {
        // No new password typed — keep whatever cipher we had before.
        cipher = widget.existing?.passwordCipher;
      }
      if (!mounted) return;
      Navigator.of(context).pop(_buildConfig(overrideCipher: cipher));
      return;
    }
    Navigator.of(context).pop(_buildConfig());
  }

  Future<void> _testConnection() async {
    if (!_valid || _testStatus == _TestStatus.busy) return;
    setState(() {
      _testStatus = _TestStatus.busy;
      _testMessage = null;
      _testElapsed = null;
      _serverVersion = null;
    });
    var cfg = _buildConfig();
    if (cfg.credentialSource == CredentialSource.onePassword) {
      final r = await _op.read(cfg.opSecretRef ?? '');
      switch (r) {
        case OpSuccess(value: final v):
          cfg = cfg.copyWith(password: v);
        case OpMissing():
          if (!mounted) return;
          setState(() {
            _testStatus = _TestStatus.fail;
            _testMessage =
                'op CLI not installed (brew install 1password-cli)';
          });
          return;
        case OpFailure(message: final m):
          if (!mounted) return;
          setState(() {
            _testStatus = _TestStatus.fail;
            _testMessage = '1Password: $m';
          });
          return;
      }
    }
    final svc = createDbService(cfg);
    final watch = Stopwatch()..start();
    try {
      await svc.connect();
      final tag = await svc.fetchVersionTag();
      watch.stop();
      final v = tag ?? '';
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.ok;
        _testElapsed = watch.elapsed;
        _serverVersion = v;
      });
    } catch (err) {
      watch.stop();
      if (!mounted) return;
      setState(() {
        _testStatus = _TestStatus.fail;
        _testElapsed = watch.elapsed;
        _testMessage = err.toString().replaceFirst(
          RegExp(r'^[A-Za-z]+Exception:\s*'),
          '',
        );
      });
    } finally {
      try {
        await svc.close();
      } catch (_) {}
    }
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
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 48,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: Radii.brLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(
                  isEdit: widget.existing != null,
                  engine: _engine,
                  tint: _color,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                    child: _buildBody(),
                  ),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- body ----------------------------------------------------

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EngineToggle(
          value: _engine,
          onChanged: (v) => setState(() => _engine = v),
        ),
        const SizedBox(height: 18),
        _Field(
          label: 'Display name',
          child: _TextInput(
            controller: _name,
            hint: _engine == DbEngine.sqlite
                ? 'My local database'
                : 'Production · users',
            autofocus: true,
          ),
        ),
        const SizedBox(height: 14),
        if (_engine == DbEngine.sqlite)
          _buildFileField()
        else ...[
          _buildHostPort(),
          const SizedBox(height: 14),
          _Field(
            label: 'Database',
            child: _TextInput(controller: _database, hint: 'postgres'),
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'User',
            child: _TextInput(controller: _username, hint: 'postgres'),
          ),
          const SizedBox(height: 14),
          _buildPasswordField(),
          const SizedBox(height: 14),
          _buildSslField(),
        ],
        const SizedBox(height: 18),
        _DividerLabel(label: 'Appearance & access'),
        const SizedBox(height: 14),
        _buildColorField(),
        const SizedBox(height: 16),
        _buildReadOnlyRow(),
      ],
    );
  }

  // ---------- host + port ---------------------------------------------

  Widget _buildHostPort() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: _Field(
            label: 'Host',
            child: _TextInput(controller: _host, hint: 'localhost'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _Field(
            label: 'Port',
            child: _TextInput(
              controller: _port,
              hint: '5432',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- sqlite file ---------------------------------------------

  Widget _buildFileField() {
    return _Field(
      label: 'Database file',
      hint: 'SQLite file opened directly — no server needed.',
      child: _TextInput(
        controller: _filePath,
        hint: '/path/to/database.sqlite',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _InlineAction(icon: Icons.add_rounded, label: 'New', onTap: _createFile),
            const SizedBox(width: 4),
            _InlineAction(
              icon: Icons.folder_open_rounded,
              label: 'Browse',
              onTap: _pickFile,
            ),
          ],
        ),
      ),
    );
  }

  static const _sqliteTypeGroup = XTypeGroup(
    label: 'SQLite database',
    extensions: ['db', 'sqlite', 'sqlite3', 'db3'],
  );

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [_sqliteTypeGroup],
    );
    if (file != null && mounted) {
      _filePath.text = file.path;
    }
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
        _testStatus = _TestStatus.fail;
        _testMessage = 'Could not create database: $err';
      });
      return;
    }
    _filePath.text = location.path;
  }

  // ---------- password / secret ---------------------------------------

  Widget _buildPasswordField() {
    final isOnePassword = _credentialSource == CredentialSource.onePassword;
    final helper = switch (_credentialSource) {
      CredentialSource.plain => 'Saved as plain text in connections.json.',
      CredentialSource.encrypted =>
        'Encrypted with your master passphrase (AES-GCM).',
      CredentialSource.onePassword =>
        'Resolved from the 1Password CLI each time you connect.',
    };
    final keepHint = _credentialSource == CredentialSource.encrypted &&
        widget.existing != null &&
        (widget.existing!.passwordCipher?.isNotEmpty ?? false);

    final Widget input;
    if (isOnePassword) {
      input = _TextInput(
        controller: _opSecretRef,
        hint: 'op://Vault/Item/password',
      );
    } else {
      input = _TextInput(
        controller: _password,
        obscure: !_showPassword,
        hint: keepHint ? 'Leave blank to keep current' : 'Password',
        trailing: _GhostIcon(
          icon: _showPassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onTap: () => setState(() => _showPassword = !_showPassword),
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
              style: _labelStyle,
            ),
            const Spacer(),
            _SourceSegmented(
              value: _credentialSource,
              onChanged: (v) => setState(() => _credentialSource = v),
            ),
          ],
        ),
        const SizedBox(height: 7),
        input,
        const SizedBox(height: 6),
        Text(helper, style: _hintStyle),
      ],
    );
  }

  // ---------- ssl -----------------------------------------------------

  Widget _buildSslField() {
    final secure = _sslMode != 'disable';
    return _Field(
      label: 'SSL mode',
      child: _SelectInput(
        icon: secure ? Icons.lock_rounded : Icons.lock_open_rounded,
        iconColor: secure ? AppColors.accent : AppColors.textMuted,
        label: _sslMode,
        onTap: _openSslMenu,
      ),
    );
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
                  m == _sslMode ? Icons.check_rounded : Icons.circle,
                  size: m == _sslMode ? 14 : 4,
                  color: m == _sslMode ? AppColors.accent : AppColors.textMuted,
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
    if (picked != null && mounted) setState(() => _sslMode = picked);
  }

  // ---------- color ---------------------------------------------------

  Widget _buildColorField() {
    return _Field(
      label: 'Connection color',
      hint: 'Tints the sidebar and chips so this database is easy to spot.',
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: 11,
          runSpacing: 10,
          children: [
            for (final c in kConnectionColors)
              _ColorSwatch(
                color: c,
                selected: c.toARGB32() == _color.toARGB32(),
                onTap: () => setState(() => _color = c),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- read-only ------------------------------------------------

  Widget _buildReadOnlyRow() {
    return Hoverable(
      onTap: () => setState(() => _readOnly = !_readOnly),
      builder: (_, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceAlt : AppColors.bg,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: _readOnly ? AppColors.accentRing : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _readOnly
                  ? Icons.shield_rounded
                  : Icons.shield_outlined,
              size: 16,
              color: _readOnly ? AppColors.accent : AppColors.textMuted,
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
                    style: _hintStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Toggle(
              value: _readOnly,
              onChanged: (v) => setState(() => _readOnly = v),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- footer --------------------------------------------------

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatusPill(
              status: _testStatus,
              message: _testMessage,
              elapsed: _testElapsed,
              version: _serverVersion,
            ),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: _testStatus == _TestStatus.busy ? 'Testing…' : 'Test',
            icon: Icons.bolt_rounded,
            onPressed: _valid && _testStatus != _TestStatus.busy
                ? _testConnection
                : null,
          ),
          const SizedBox(width: 8),
          AppButton(
            label: widget.existing == null ? 'Create' : 'Save',
            icon: widget.existing == null
                ? Icons.add_rounded
                : Icons.check_rounded,
            primary: true,
            onPressed: _valid ? _submit : null,
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// Shared text styles
// ====================================================================

TextStyle get _labelStyle => AppTheme.ui(
  size: 11,
  weight: FontWeight.w600,
  color: AppColors.textSecondary,
  letterSpacing: 0,
);

TextStyle get _hintStyle => AppTheme.ui(
  size: 10.5,
  weight: FontWeight.w400,
  color: AppColors.textMuted,
  letterSpacing: 0,
);

// ====================================================================
// Header
// ====================================================================

class _Header extends StatelessWidget {
  const _Header({
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
          colors: [
            tint.withValues(alpha: 0.10),
            AppColors.surface,
          ],
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
                  ? Icons.insert_drive_file_rounded
                  : Icons.dns_rounded,
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
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// Field scaffolding
// ====================================================================

/// Label above, control below, optional helper line — the standard form
/// row used throughout the dialog.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: 7),
        child,
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: _hintStyle),
        ],
      ],
    );
  }
}

/// Faint hairline with a centered caption — separates the connection's
/// network details from its presentation settings.
class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: AppTheme.ui(
            size: 10,
            weight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: AppColors.hairline)),
      ],
    );
  }
}

/// Boxed text input with an Inter typeface and an accent focus ring. The
/// optional [trailing] sits inside the box (used for the show-password
/// toggle and the SQLite browse actions).
class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.controller,
    this.hint,
    this.obscure = false,
    this.inputFormatters,
    this.autofocus = false,
    this.trailing,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final Widget? trailing;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 36,
      padding: const EdgeInsets.only(left: 11, right: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brSm,
        border: Border.all(
          color: focused ? AppColors.accent : AppColors.border,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.accentSoft,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              obscureText: widget.obscure,
              obscuringCharacter: '•',
              inputFormatters: widget.inputFormatters,
              cursorColor: AppColors.accent,
              cursorWidth: 1.5,
              cursorHeight: 14,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTheme.ui(
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: AppColors.text4,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// Read-only boxed control that opens a menu on tap — visually matches
/// [_TextInput] so the SSL row sits flush with the text fields.
class _SelectInput extends StatelessWidget {
  const _SelectInput({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: Radii.brSm,
          border: Border.all(
            color: hovering ? AppColors.borderStrong : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 9),
            Text(
              label,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w500,
                color: AppColors.textPrimary,
                letterSpacing: 0,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.unfold_more_rounded,
              size: 15,
              color: hovering ? AppColors.textSecondary : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small icon-only affordance that lives inside a [_TextInput] (the
/// show/hide-password eye).
class _GhostIcon extends StatelessWidget {
  const _GhostIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: Radii.brSm,
        ),
        child: Icon(
          icon,
          size: 14,
          color: hovering ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Compact icon + label action used inside the SQLite file input.
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: hovering ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: Radii.brSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: hovering ? AppColors.textPrimary : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTheme.ui(
                size: 11.5,
                weight: FontWeight.w500,
                color: hovering ? AppColors.textPrimary : AppColors.textMuted,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Engine toggle
// ====================================================================

class _EngineToggle extends StatelessWidget {
  const _EngineToggle({required this.value, required this.onChanged});

  final DbEngine value;
  final ValueChanged<DbEngine> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              DbEngine.postgres,
              Icons.dns_rounded,
              'PostgreSQL',
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _segment(
              DbEngine.sqlite,
              Icons.insert_drive_file_rounded,
              'SQLite',
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(DbEngine engine, IconData icon, String label) {
    final selected = engine == value;
    return Hoverable(
      onTap: () => onChanged(engine),
      builder: (_, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : (hovering ? AppColors.surfaceHover : Colors.transparent),
          borderRadius: Radii.brSm,
          border: Border.all(
            color: selected ? AppColors.accentRing : Colors.transparent,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? AppColors.accent
                  : (hovering
                        ? AppColors.textSecondary
                        : AppColors.textMuted),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.ui(
                size: 12.5,
                weight: FontWeight.w600,
                letterSpacing: -0.1,
                color: selected
                    ? AppColors.accent
                    : (hovering
                          ? AppColors.textPrimary
                          : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Credential source segmented
// ====================================================================

class _SourceSegmented extends StatelessWidget {
  const _SourceSegmented({required this.value, required this.onChanged});

  final CredentialSource value;
  final ValueChanged<CredentialSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: Radii.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(CredentialSource.plain, 'Plain'),
          _segment(CredentialSource.encrypted, 'Encrypted'),
          _segment(CredentialSource.onePassword, '1Password'),
        ],
      ),
    );
  }

  Widget _segment(CredentialSource source, String label) {
    final selected = source == value;
    return Hoverable(
      onTap: () => onChanged(source),
      builder: (_, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: AppTheme.ui(
            size: 10.5,
            weight: FontWeight.w600,
            letterSpacing: 0,
            color: selected
                ? Colors.white
                : (hovering
                      ? AppColors.textPrimary
                      : AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// Color swatch
// ====================================================================

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 1 : (hovering ? 0.9 : 0.8)),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? AppColors.textPrimary
                : color.withValues(alpha: 0.0),
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 9,
                    spreadRadius: -1,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

// ====================================================================
// Read-only toggle
// ====================================================================

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => onChanged(!value),
      builder: (_, hovering) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 32,
          height: 18,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: value
                ? AppColors.accent
                : (hovering ? AppColors.surfaceHover : AppColors.surfaceAlt),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: value ? AppColors.accent : AppColors.borderStrong,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: value ? Colors.white : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ====================================================================
// Test status pill
// ====================================================================

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    this.message,
    this.elapsed,
    this.version,
  });

  final _TestStatus status;
  final String? message;
  final Duration? elapsed;
  final String? version;

  @override
  Widget build(BuildContext context) {
    final Color dot;
    final String text;
    final Color textColor;
    switch (status) {
      case _TestStatus.idle:
        dot = AppColors.textMuted;
        text = 'Not tested yet';
        textColor = AppColors.textMuted;
        break;
      case _TestStatus.busy:
        dot = AppColors.warning;
        text = 'Testing connection…';
        textColor = AppColors.textSecondary;
        break;
      case _TestStatus.ok:
        dot = AppColors.success;
        final ms = elapsed?.inMilliseconds ?? 0;
        final v = version ?? '';
        text = 'Connected · ${ms}ms${v.isEmpty ? '' : ' · $v'}';
        textColor = AppColors.textSecondary;
        break;
      case _TestStatus.fail:
        dot = AppColors.error;
        final m = message ?? 'Connection failed';
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
            boxShadow: status == _TestStatus.ok
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
