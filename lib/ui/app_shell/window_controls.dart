import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/hugeicons.dart';
import 'toolbar_widgets.dart';

const _windowChannel = MethodChannel('aperture/window');

/// Minimize, maximize and close for the Linux window, which has no frame
/// of its own — on macOS the OS draws the traffic lights instead.
class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TbIcon(
          icon: Hgi.minusSign,
          tooltip: 'Minimize',
          onPressed: () => _windowChannel.invokeMethod('minimize'),
        ),
        TbIcon(
          icon: Hgi.square,
          tooltip: 'Maximize',
          onPressed: () => _windowChannel.invokeMethod('toggleZoom'),
        ),
        TbIcon(
          icon: Hgi.cancel01,
          tooltip: 'Close',
          onPressed: () => _windowChannel.invokeMethod('close'),
        ),
      ],
    );
  }
}
