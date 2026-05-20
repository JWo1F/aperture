import 'package:flutter/material.dart';

import '../../models/connection_config.dart';
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
  late bool _useSsl;

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
    _useSsl = e?.useSsl ?? false;
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _database, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _host.text.trim().isNotEmpty &&
      _database.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      int.tryParse(_port.text.trim()) != null;

  void _submit() {
    if (!_valid) return;
    final host = _host.text.trim();
    final db = _database.text.trim();
    final name = _name.text.trim().isEmpty
        ? '$db @ $host'
        : _name.text.trim();
    Navigator.of(context).pop(
      ConnectionConfig(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        host: host,
        port: int.parse(_port.text.trim()),
        database: db,
        username: _username.text.trim(),
        password: _password.text,
        useSsl: _useSsl,
      ),
    );
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
      child: Container(
        decoration: const BoxDecoration(
          borderRadius: Radii.brLg,
          boxShadow: [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 40,
              offset: Offset(0, 12),
            ),
          ],
        ),
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null
                    ? 'New Connection'
                    : 'Edit Connection',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Connect to a PostgreSQL database.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: Insets.xl),
              _Field(label: 'Display name', controller: _name, hint: 'Optional'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _Field(label: 'Host', controller: _host),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: _Field(
                      label: 'Port',
                      controller: _port,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              _Field(
                label: 'Database',
                controller: _database,
                onChanged: (_) => setState(() {}),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Field(
                      label: 'Username',
                      controller: _username,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: _Field(
                      label: 'Password',
                      controller: _password,
                      obscure: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              _SslToggle(
                value: _useSsl,
                onChanged: (v) => setState(() => _useSsl = v),
              ),
              const SizedBox(height: Insets.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: Insets.sm),
                  AppButton(
                    label: 'Save & Connect',
                    icon: Icons.bolt,
                    primary: true,
                    onPressed: _valid ? _submit : null,
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTheme.eyebrow()),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            obscureText: obscure,
            onChanged: onChanged,
            style: AppTheme.mono(size: 13),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppTheme.mono(size: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SslToggle extends StatelessWidget {
  const _SslToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? AppColors.accent : AppColors.bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: value ? AppColors.accent : AppColors.borderStrong,
              ),
            ),
            child: value
                ? Icon(Icons.check, size: 13, color: AppColors.bg)
                : null,
          ),
          const SizedBox(width: Insets.sm),
          Text(
            'Use SSL connection',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
