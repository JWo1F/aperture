import 'package:flutter/material.dart';

import '../../../models/connection_config.dart';
import '../../../theme/app_theme.dart';

/// Mutable, dialog-scoped form state for the connection dialog. Owns the
/// text controllers and the non-text fields, and notifies listeners on any
/// change so the dialog's header, body and footer re-render together.
///
/// The owning [State] is responsible for calling [dispose].
class ConnectionFormModel extends ChangeNotifier {
  ConnectionFormModel({this.existing}) {
    final e = existing;
    name = TextEditingController(text: e?.name ?? '');
    host = TextEditingController(text: e?.host ?? 'localhost');
    port = TextEditingController(text: (e?.port ?? 5432).toString());
    database = TextEditingController(text: e?.database ?? '');
    username = TextEditingController(text: e?.username ?? 'postgres');
    password = TextEditingController(text: e?.password ?? '');
    opSecretRef = TextEditingController(text: e?.opSecretRef ?? '');
    filePath = TextEditingController(text: e?.filePath ?? '');
    _engine = e?.engine ?? DbEngine.postgres;
    _sslMode = (e?.useSsl ?? false) ? 'require' : 'disable';
    _color = e?.color != null ? Color(e!.color!) : kConnectionColors.first;
    _readOnly = e?.readOnly ?? false;
    _credentialSource = e?.credentialSource ?? CredentialSource.plain;
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
  late final TextEditingController opSecretRef;
  late final TextEditingController filePath;

  List<TextEditingController> get _controllers => [
    name,
    host,
    port,
    database,
    username,
    password,
    opSecretRef,
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

  late CredentialSource _credentialSource;
  CredentialSource get credentialSource => _credentialSource;
  set credentialSource(CredentialSource v) {
    if (v == _credentialSource) return;
    _credentialSource = v;
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
    if (_credentialSource == CredentialSource.onePassword) {
      return opSecretRef.text.trim().startsWith('op://');
    }
    return true;
  }

  /// Materializes the form into a [ConnectionConfig]. [overrideCipher] is
  /// supplied by the encrypted-credential save path once the plaintext
  /// password has been encrypted against the master passphrase.
  ConnectionConfig buildConfig({String? overrideCipher}) {
    final id =
        existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    if (_engine == DbEngine.sqlite) {
      final path = filePath.text.trim();
      final base = path.isEmpty ? 'database' : path.split('/').last;
      final label = name.text.trim().isEmpty ? base : name.text.trim();
      return ConnectionConfig(
        id: id,
        name: label,
        engine: DbEngine.sqlite,
        filePath: path,
        // Surfaced as the connection's display label in the sidebar header.
        database: base,
        color: _color.toARGB32(),
        readOnly: _readOnly,
      );
    }
    final h = host.text.trim();
    final db = database.text.trim();
    final label = name.text.trim().isEmpty ? '$db @ $h' : name.text.trim();
    final ref = opSecretRef.text.trim();
    final isEncrypted = _credentialSource == CredentialSource.encrypted;
    final isOnePassword = _credentialSource == CredentialSource.onePassword;
    return ConnectionConfig(
      id: id,
      name: label,
      host: h,
      port: int.parse(port.text.trim()),
      database: db,
      username: username.text.trim(),
      // Plain holds the password inline; encrypted moves it to
      // passwordCipher; 1Password keeps neither field populated.
      password: _credentialSource == CredentialSource.plain
          ? password.text
          : '',
      useSsl: _sslMode != 'disable',
      color: _color.toARGB32(),
      readOnly: _readOnly,
      credentialSource: _credentialSource,
      passwordCipher: isEncrypted
          ? (overrideCipher ?? existing?.passwordCipher)
          : null,
      opSecretRef: isOnePassword && ref.isNotEmpty ? ref : null,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}
