import 'app_state.dart';

/// The one [AppState] for the running app. Set once in `main()` after
/// `AppState.load()` completes, and read from anywhere thereafter.
///
/// Aperture is a single-user, single-instance desktop app: every
/// controller lives for the entire process. The element tree had no
/// scoping work to do, so widgets reach the controllers directly via
/// `appState.store`, `appState.session`, etc. instead of bouncing
/// through `Provider`. Rebuild subscription that used to come from
/// `context.watch<X>()` / `context.select<X, Y>(...)` is provided by
/// `ListenableBuilder` and `Selector` (`lib/ui/widgets/value_selector.dart`).
late final AppState appState;
