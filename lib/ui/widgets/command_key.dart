import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's command modifier: ⌘ on macOS, Ctrl on Linux, where Super
/// belongs to the desktop (Super+L locks the screen, Super alone opens the
/// overview).
final bool _commandIsMeta = Platform.isMacOS;

/// The modifier as one key cap, for a cluster of separate caps.
final String commandCap = _commandIsMeta ? '⌘' : 'Ctrl';

/// [key] behind the modifier as one label: `⌘K`, or `Ctrl+K`.
String commandLabel(String key) => _commandIsMeta ? '⌘$key' : 'Ctrl+$key';

SingleActivator commandActivator(
  LogicalKeyboardKey key, {
  bool shift = false,
}) => SingleActivator(
  key,
  meta: _commandIsMeta,
  control: !_commandIsMeta,
  shift: shift,
);

bool get isCommandPressed => _commandIsMeta
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;
