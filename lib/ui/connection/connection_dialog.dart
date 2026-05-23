// Public entry point for the connection dialog. The implementation lives
// in `dialog/` — split into focused modules (form model, test runner,
// header / body / footer, shared form widgets).
export 'connection_flow.dart' show createConnectionFlow, editConnectionFlow;
export 'dialog/connection_dialog.dart' show showConnectionDialog;
