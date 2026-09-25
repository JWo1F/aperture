import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';

/// Which credential variant the user has selected in the dialog. Stored
/// as a UI-only enum because both credential text controllers live across
/// both modes — switching back and forth keeps what was typed — and the
/// [Credential] sealed type only gets constructed at submit time.
enum CredentialMode { password, command }

CredentialMode _modeOf(Credential c) => switch (c) {
  PasswordCredential() => CredentialMode.password,
  CommandCredential() => CredentialMode.command,
};

/// Mutable, dialog-scoped form state for the connection dialog. Owns the
/// text controllers and the non-text fields, and notifies listeners on any
/// change so the dialog's header, body and footer re-render together.
///
/// The owning [State] is responsible for calling [dispose].
class ConnectionFormModel extends ChangeNotifier {
  ConnectionFormModel({this.existing}) {
    final e = existing;
    final ec = e?.credential;
    name = TextEditingController(text: e?.name ?? '');
    host = TextEditingController(text: e?.host ?? 'localhost');
    port = TextEditingController(text: (e?.port ?? 5432).toString());
    database = TextEditingController(text: e?.database ?? '');
    username = TextEditingController(text: e?.username ?? 'postgres');
    password = TextEditingController(
      text: ec is PasswordCredential ? ec.password : '',
    );
    command = TextEditingController(
      text: ec is CommandCredential ? ec.command : '',
    );
    filePath = TextEditingController(text: e?.filePath ?? '');
    _engine = e?.engine ?? DbEngine.postgres;
    _sslMode = (e?.useSsl ?? false) ? 'require' : 'disable';
    _color = e?.color != null ? Color(e!.color!) : kConnectionColors.first;
    _readOnly = e?.readOnly ?? false;
    _credentialMode = ec != null ? _modeOf(ec) : CredentialMode.password;
    for (final c in _controllers) {
      c.addListener(notifyListeners);
    }
  }

  /// The connection being edited, or null when creating a new one.
  final ConnectionConfig? existing;

  late final TextEditingController name;
  late final TextEditingController host;
  late final TextEditingController port;
  late final TextEditingController database;
  late final TextEditingController username;
  late final TextEditingController password;
  late final TextEditingController command;
  late final TextEditingController filePath;

  List<TextEditingController> get _controllers => [
    name,
    host,
    port,
    database,
    username,
    password,
    command,
    filePath,
  ];

  late DbEngine _engine;
  DbEngine get engine => _engine;
  set engine(DbEngine v) {
    if (v == _engine) return;
    _engine = v;
    notifyListeners();
  }

  late String _sslMode;
  String get sslMode => _sslMode;
  set sslMode(String v) {
    if (v == _sslMode) return;
    _sslMode = v;
    notifyListeners();
  }

  late Color _color;
  Color get color => _color;
  set color(Color v) {
    if (v.toARGB32() == _color.toARGB32()) return;
    _color = v;
    notifyListeners();
  }

  late bool _readOnly;
  bool get readOnly => _readOnly;
  set readOnly(bool v) {
    if (v == _readOnly) return;
    _readOnly = v;
    notifyListeners();
  }

  late CredentialMode _credentialMode;
  CredentialMode get credentialMode => _credentialMode;
  set credentialMode(CredentialMode v) {
    if (v == _credentialMode) return;
    _credentialMode = v;
    notifyListeners();
  }

  bool _showPassword = false;
  bool get showPassword => _showPassword;
  set showPassword(bool v) {
    if (v == _showPassword) return;
    _showPassword = v;
    notifyListeners();
  }

  bool get isEdit => existing != null;

  /// Whether the current field values are enough to build a usable config.
  bool get valid {
    if (_engine == DbEngine.sqlite) {
      return filePath.text.trim().isNotEmpty;
    }
    final base =
        host.text.trim().isNotEmpty &&
        database.text.trim().isNotEmpty &&
        username.text.trim().isNotEmpty &&
        int.tryParse(port.text.trim()) != null;
    if (!base) return false;
    if (_credentialMode == CredentialMode.command) {
      return command.text.trim().isNotEmpty;
    }
    return true;
  }

  /// Materializes the form into a [ConnectionConfig].
  ///
  /// On edit, only the form-driven fields are replaced — every
  /// per-connection bag ([ConnectionConfig.favoriteTables],
  /// [ConnectionConfig.savedQueries], [ConnectionConfig.recentTables],
  /// [ConnectionConfig.tableUseCounts], [ConnectionConfig.columnWidths],
  /// [ConnectionConfig.queryMessages], [ConnectionConfig.lastConnectedAt])
  /// survives via [ConnectionConfig.copyWith].
  ConnectionConfig buildConfig() {
    final base = existing ??
        ConnectionConfig(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: '',
        );
    if (_engine == DbEngine.sqlite) {
      final path = filePath.text.trim();
      final fileBase = path.isEmpty ? 'database' : path.split('/').last;
      final label = name.text.trim().isEmpty ? fileBase : name.text.trim();
      return base.copyWith(
        name: label,
        engine: DbEngine.sqlite,
        filePath: path,
        // Surfaced as the connection's display label in the sidebar header.
        database: fileBase,
        color: _color.toARGB32(),
        readOnly: _readOnly,
      );
    }
    final h = host.text.trim();
    final db = database.text.trim();
    final label = name.text.trim().isEmpty ? '$db @ $h' : name.text.trim();
    return base.copyWith(
      name: label,
      engine: DbEngine.postgres,
      host: h,
      port: int.parse(port.text.trim()),
      database: db,
      username: username.text.trim(),
      credential: _buildCredential(),
      useSsl: _sslMode != 'disable',
      color: _color.toARGB32(),
      readOnly: _readOnly,
    );
  }

  Credential _buildCredential() => switch (_credentialMode) {
    CredentialMode.password => PasswordCredential(password.text),
    CredentialMode.command => CommandCredential(command.text.trim()),
  };

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}
