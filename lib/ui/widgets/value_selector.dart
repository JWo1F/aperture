import 'package:flutter/widgets.dart';

/// Subscribes to [listenable] and rebuilds [builder] only when the value
/// produced by [selector] changes (compared by `==`).
///
/// The replacement for provider's `context.select<X, Y>(...)`: we no
/// longer need to walk the element tree to find the listenable (every
/// controller is reachable via `appState`), but we still want the gated
/// rebuild so that a high-frequency notifier (e.g. [TabsController]
/// fanning out every cell-edit) doesn't repaint the toolbar / pill /
/// shell on every tick.
class Selector<T> extends StatefulWidget {
  const Selector({
    super.key,
    required this.listenable,
    required this.selector,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() selector;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<Selector<T>> createState() => _SelectorState<T>();
}

class _SelectorState<T> extends State<Selector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.selector();
    widget.listenable.addListener(_onChanged);
  }

  void _onChanged() {
    final next = widget.selector();
    if (next != _value) {
      setState(() => _value = next);
    }
  }

  @override
  void didUpdateWidget(Selector<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
    _value = widget.selector();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
