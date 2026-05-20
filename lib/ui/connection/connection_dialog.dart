import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/connection_config.dart';
import '../../services/postgres_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';

/// Modal form for creating or editing a saved connection. Resolves to the
/// resulting [ConnectionConfig], or null if dismissed.
Future<ConnectionConfig?> showConnectionDialog(
  BuildContext context, {
  ConnectionConfig? existing,
}) {
  return showDialog<ConnectionConfig>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _ConnectionDialog(existing: existing),
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

/// Indigo first (default), then a muted Aperture-palette set. The accent
/// stays in the position the screenshot uses.
const List<Color> _tagColors = [
  Color(0xFF5B7CFA),
  Color(0xFF7AAC8F),
  Color(0xFFC28A5C),
  Color(0xFFB59BD8),
  Color(0xFFC9B86E),
  Color(0xFFCB6F6F),
];

enum _TestStatus { idle, busy, ok, fail }

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({this.existing});

  final ConnectionConfig? existing;

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

  late String _sslMode;
  late Color _tagColor;
  bool _savePassword = true;
  bool _readOnly = false;
  bool _showPassword = false;
  int _activeTab = 0; // 0 = manual, 1 = connection string

  _TestStatus _testStatus = _TestStatus.idle;
  String? _testMessage;
  Duration? _testElapsed;
  String? _serverVersion;

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
    _sslMode = (e?.useSsl ?? false) ? 'require' : 'disable';
    _tagColor = _tagColors.first;

    for (final c in [_name, _host, _port, _database, _username, _password]) {
      c.addListener(_onAnyFieldChanged);
    }
  }

  void _onAnyFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _database, _username, _password]) {
      c.removeListener(_onAnyFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _host.text.trim().isNotEmpty &&
      _database.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      int.tryParse(_port.text.trim()) != null;

  ConnectionConfig _buildConfig() {
    final host = _host.text.trim();
    final db = _database.text.trim();
    final name = _name.text.trim().isEmpty ? '$db @ $host' : _name.text.trim();
    return ConnectionConfig(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      host: host,
      port: int.parse(_port.text.trim()),
      database: db,
      username: _username.text.trim(),
      password: _password.text,
      useSsl: _sslMode != 'disable',
    );
  }

  void _submit() {
    if (!_valid) return;
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
    final cfg = _buildConfig();
    final svc = PostgresService(cfg);
    final watch = Stopwatch()..start();
    try {
      await svc.connect();
      final r = await svc.execute('SHOW server_version');
      watch.stop();
      final raw = r.isNotEmpty ? r.first.first?.toString() ?? '' : '';
      // Trim trailing build metadata: "16.2 (Debian 16.2-1)" → "16.2"
      final v = raw.split(RegExp(r'\s+')).first;
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: Radii.brLg,
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 48,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: Radii.brLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                _buildTabStrip(),
                _buildRow(
                  label: 'NAME',
                  child: _PlainInput(controller: _name, hint: 'connection name'),
                  trailing: const _Chip(text: 'display'),
                ),
                _buildHostPortRow(),
                _buildRow(
                  label: 'DATABASE',
                  child: _PlainInput(controller: _database, hint: 'postgres'),
                ),
                _buildRow(
                  label: 'USER',
                  child: _PlainInput(controller: _username),
                ),
                _buildPasswordRow(),
                _buildSslRow(),
                _buildTagColorRow(),
                _buildOptionsRow(),
                _buildJdbcPreview(),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- header --------------------------------------------------

  Widget _buildHeader() {
    final isEdit = widget.existing != null;
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
            child: Icon(Icons.storage_rounded, size: 16, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Text(
            isEdit ? 'Edit connection' : 'New connection',
            style: AppTheme.ui(
              size: 16,
              weight: FontWeight.w600,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'postgres · v9 — v16',
            style: AppTheme.mono(size: 11.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          IconAction(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ---------- tab strip -----------------------------------------------

  Widget _buildTabStrip() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _TabLabel(
            text: 'MANUAL',
            active: _activeTab == 0,
            onTap: () => setState(() => _activeTab = 0),
          ),
          const SizedBox(width: 18),
          _TabLabel(
            text: 'CONNECTION STRING',
            active: _activeTab == 1,
            onTap: () => setState(() => _activeTab = 1),
          ),
          const Spacer(),
          Text(
            'POSTGRES',
            style: GoogleMonoEyebrow.style(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ---------- generic row ---------------------------------------------

  Widget _buildRow({
    required String label,
    required Widget child,
    Widget? trailing,
    Widget? labelOverride,
    EdgeInsets padding =
        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              child: labelOverride ??
                  Text(
                    label,
                    style: GoogleMonoEyebrow.style(
                      color: AppColors.textMuted,
                    ),
                  ),
            ),
            const SizedBox(width: 12),
            Expanded(child: child),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  // ---------- host + port ---------------------------------------------

  Widget _buildHostPortRow() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              'HOST',
              style: GoogleMonoEyebrow.style(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: _PlainInput(controller: _host, hint: 'localhost'),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 22, color: AppColors.border),
          const SizedBox(width: 16),
          SizedBox(
            width: 56,
            child: Text(
              'PORT',
              style: GoogleMonoEyebrow.style(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _PlainInput(
              controller: _port,
              hint: '5432',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- password row --------------------------------------------

  Widget _buildPasswordRow() {
    return _buildRow(
      label: 'PASSWORD',
      child: _PlainInput(
        controller: _password,
        obscure: !_showPassword,
        hint: '••••••',
      ),
      trailing: Hoverable(
        onTap: () => setState(() => _showPassword = !_showPassword),
        builder: (_, hovering) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 14,
              color: hovering ? AppColors.textPrimary : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              _showPassword ? 'hide' : 'show',
              style: AppTheme.ui(
                size: 12,
                weight: FontWeight.w500,
                color: hovering ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- ssl row -------------------------------------------------

  Widget _buildSslRow() {
    return _buildRow(
      label: 'SSL MODE',
      child: Hoverable(
        onTap: _openSslMenu,
        builder: (context, hovering) {
          return Row(
            children: [
              Icon(
                _sslMode == 'disable'
                    ? Icons.lock_open
                    : Icons.lock_outline,
                size: 14,
                color: _sslMode == 'disable'
                    ? AppColors.textMuted
                    : AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                _sslMode,
                style: AppTheme.mono(
                  size: 12.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.expand_more,
                size: 16,
                color:
                    hovering ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ],
          );
        },
      ),
      trailing: _Chip(
        text: _sslMode == 'disable' ? 'plain' : 'tls 1.3',
        tone: _sslMode == 'disable' ? _ChipTone.muted : _ChipTone.accent,
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
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  m == _sslMode ? Icons.check : Icons.circle,
                  size: m == _sslMode ? 14 : 4,
                  color: m == _sslMode
                      ? AppColors.accent
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  m,
                  style: AppTheme.mono(
                    size: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (picked != null && mounted) setState(() => _sslMode = picked);
  }

  // ---------- tag color row -------------------------------------------

  Widget _buildTagColorRow() {
    final hex =
        '#${_tagColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return _buildRow(
      label: 'TAG COLOR',
      child: Row(
        children: [
          for (final c in _tagColors) ...[
            _ColorDot(
              color: c,
              selected: c == _tagColor,
              onTap: () => setState(() => _tagColor = c),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
      trailing: _Chip(
        text: hex,
        tone: _ChipTone.mono,
      ),
    );
  }

  // ---------- options row ---------------------------------------------

  Widget _buildOptionsRow() {
    return _buildRow(
      label: 'OPTIONS',
      child: Row(
        children: [
          _Toggle(
            value: _savePassword,
            onChanged: (v) => setState(() => _savePassword = v),
          ),
          const SizedBox(width: 10),
          Text(
            'Save password in keychain',
            style: AppTheme.ui(
              size: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 32),
          _Toggle(
            value: _readOnly,
            onChanged: (v) => setState(() => _readOnly = v),
          ),
          const SizedBox(width: 10),
          Text(
            'Read-only mode',
            style: AppTheme.ui(
              size: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      trailing: _readOnly
          ? Text(
              'blocks UPDATE / DELETE',
              style: AppTheme.mono(
                size: 11,
                color: AppColors.textMuted,
              ),
            )
          : Text(
              'blocks UPDATE / DELETE',
              style: AppTheme.mono(
                size: 11,
                color: AppColors.text4,
              ),
            ),
    );
  }

  // ---------- jdbc preview --------------------------------------------

  Widget _buildJdbcPreview() {
    final host = _host.text.trim().isEmpty ? 'localhost' : _host.text.trim();
    final port = _port.text.trim().isEmpty ? '5432' : _port.text.trim();
    final db = _database.text.trim().isEmpty ? 'postgres' : _database.text.trim();
    final user = _username.text.trim().isEmpty
        ? 'postgres'
        : _username.text.trim();

    final pwd = _password.text.isEmpty
        ? ''
        : (_showPassword ? _password.text : '••••');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              'JDBC',
              style: GoogleMonoEyebrow.style(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                style: AppTheme.mono(size: 12.5, color: AppColors.textPrimary),
                children: [
                  TextSpan(
                    text: 'postgres://',
                    style: TextStyle(color: AppColors.sqlKeyword),
                  ),
                  TextSpan(text: user),
                  if (pwd.isNotEmpty) ...[
                    TextSpan(
                      text: ':',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    TextSpan(
                      text: pwd,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                  TextSpan(
                    text: '@',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(text: host),
                  TextSpan(
                    text: ':',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(
                    text: port,
                    style: TextStyle(color: AppColors.sqlNumber),
                  ),
                  TextSpan(
                    text: '/',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(
                    text: db,
                    style: TextStyle(color: AppColors.sqlString),
                  ),
                  TextSpan(
                    text: '?sslmode=',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(
                    text: _sslMode,
                    style: TextStyle(color: AppColors.sqlString),
                  ),
                  TextSpan(
                    text: ' &application_name=',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  TextSpan(
                    text: 'dbv',
                    style: TextStyle(color: AppColors.sqlString),
                  ),
                ],
              ),
              style: AppTheme.mono(size: 12.5, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          IconAction(
            icon: Icons.copy_outlined,
            tooltip: 'Copy connection string',
            onPressed: () => _copyJdbc(host, port, db, user),
          ),
        ],
      ),
    );
  }

  void _copyJdbc(String host, String port, String db, String user) {
    final url = 'postgres://$user@$host:$port/$db?sslmode=$_sslMode';
    Clipboard.setData(ClipboardData(text: url));
  }

  // ---------- footer --------------------------------------------------

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          _StatusPill(
            status: _testStatus,
            message: _testMessage,
            elapsed: _testElapsed,
            version: _serverVersion,
          ),
          const Spacer(),
          AppButton(
            label: 'Test connection',
            icon: Icons.bolt_outlined,
            onPressed: _valid && _testStatus != _TestStatus.busy
                ? _testConnection
                : null,
          ),
          const SizedBox(width: 8),
          AppButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          AppButton(
            label: widget.existing == null
                ? 'Create connection'
                : 'Save changes',
            icon: Icons.add,
            primary: true,
            onPressed: _valid ? _submit : null,
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// Helper widgets
// ====================================================================

/// Tiny mono uppercase label, used for row labels and section eyebrows. We
/// can't lean on [AppTheme.eyebrow] directly because that one is Inter — the
/// screenshot uses JetBrains Mono so labels visually align with values.
class GoogleMonoEyebrow {
  static TextStyle style({Color? color}) =>
      AppTheme.mono(size: 10.5, color: color, weight: FontWeight.w500)
          .copyWith(letterSpacing: 1.1);
}

class _PlainInput extends StatelessWidget {
  const _PlainInput({
    required this.controller,
    this.hint,
    this.obscure = false,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      obscuringCharacter: '•',
      inputFormatters: inputFormatters,
      style: AppTheme.mono(size: 13, color: AppColors.textPrimary),
      cursorColor: AppColors.accent,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: AppTheme.mono(size: 13, color: AppColors.text4),
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.text,
    required this.active,
    required this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (_, hovering) {
        final color = active
            ? AppColors.textPrimary
            : (hovering ? AppColors.textSecondary : AppColors.textMuted);
        return SizedBox(
          height: 38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Text(
                text,
                style: GoogleMonoEyebrow.style(color: color)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                height: 2,
                width: text.length * 7.0,
                decoration: BoxDecoration(
                  color: active ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _ChipTone { muted, accent, mono }

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.tone = _ChipTone.muted});

  final String text;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    Color fg;
    Color bg;
    Color border;
    switch (tone) {
      case _ChipTone.accent:
        fg = AppColors.accent;
        bg = AppColors.accentSoft;
        border = AppColors.accentRing;
        break;
      case _ChipTone.mono:
        fg = AppColors.textSecondary;
        bg = AppColors.surfaceAlt;
        border = AppColors.border;
        break;
      case _ChipTone.muted:
        fg = AppColors.textMuted;
        bg = AppColors.surfaceAlt;
        border = AppColors.border;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: AppTheme.mono(size: 10.5, color: fg),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
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
      builder: (_, hovering) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? AppColors.textPrimary
                : (hovering ? AppColors.borderStrong : Colors.transparent),
            width: selected ? 2 : 1,
          ),
        ),
        child: Container(
          margin: EdgeInsets.all(selected ? 2.5 : 1),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

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
          width: 30,
          height: 17,
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
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12,
              height: 12,
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
        text = 'Not tested';
        textColor = AppColors.textMuted;
        break;
      case _TestStatus.busy:
        dot = AppColors.warning;
        text = 'Testing…';
        textColor = AppColors.textSecondary;
        break;
      case _TestStatus.ok:
        dot = AppColors.success;
        final ms = elapsed?.inMilliseconds ?? 0;
        final v = version ?? '';
        text = 'Connection ok · ${ms}ms${v.isEmpty ? '' : ' · pg $v'}';
        textColor = AppColors.textSecondary;
        break;
      case _TestStatus.fail:
        dot = AppColors.error;
        final m = message ?? 'connection failed';
        final trimmed = m.length > 70 ? '${m.substring(0, 70)}…' : m;
        text = trimmed;
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
                ? [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.mono(size: 12, color: textColor),
          ),
        ),
      ],
    );
  }
}
