import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_window_utils/macos/ns_window_delegate.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../command_palette/command_palette.dart';
import 'connection_pill.dart';
import 'toolbar_actions.dart';
import 'toolbar_widgets.dart';

const _windowChannel = MethodChannel('dbv/window');

/// Width reserved on the left of the top toolbar for the macOS traffic-light
/// buttons, which are drawn by the OS on top of our Flutter content.
const double _trafficLightInset = 78;

/// Top toolbar: window-drag surface, navigation + connection controls on
/// the left, ⌘K search and theme/config affordances on the right.
class Toolbar extends StatefulWidget {
  const Toolbar({super.key});

  @override
  State<Toolbar> createState() => _ToolbarState();
}

/// Bridges AppKit's full-screen transitions into [_ToolbarState] so the
/// toolbar can drop the traffic-light inset — macOS hides the traffic
/// lights in full screen, leaving that reserved width as dead space.
class _FullScreenDelegate extends NSWindowDelegate {
  _FullScreenDelegate(this.onChanged);

  final ValueChanged<bool> onChanged;

  @override
  void windowDidEnterFullScreen() {
    onChanged(true);
    super.windowDidEnterFullScreen();
  }

  @override
  void windowDidExitFullScreen() {
    onChanged(false);
    super.windowDidExitFullScreen();
  }
}

class _ToolbarState extends State<Toolbar> {
  bool _fullScreen = false;
  NSWindowDelegateHandle? _delegateHandle;

  @override
  void initState() {
    super.initState();
    _watchFullScreen();
  }

  Future<void> _watchFullScreen() async {
    _delegateHandle = WindowManipulator.addNSWindowDelegate(
      _FullScreenDelegate(_setFullScreen),
    );
    try {
      _setFullScreen(await WindowManipulator.isWindowFullscreened());
    } on MissingPluginException {
      // Tests / non-macOS hosts — no native window to track.
    }
  }

  void _setFullScreen(bool value) {
    if (!mounted || _fullScreen == value) return;
    setState(() => _fullScreen = value);
  }

  @override
  void dispose() {
    _delegateHandle?.removeFromHandler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Each reactive bit is a separate selector so the toolbar only
    // rebuilds when one of these actually changes. Brightness, history,
    // pending-edit count and the active tab's exportable result are the
    // only fields driving any visible change in here.
    final state = context.read<AppState>();
    final pending = context.select<AppState, int>((s) => s.unappliedEditCount);
    final canGoBack = context.select<AppState, bool>((s) => s.canGoBack);
    final canGoForward = context.select<AppState, bool>((s) => s.canGoForward);
    final brightness = context.select<AppState, AppBrightness>(
      (s) => s.brightness,
    );
    // Export availability tracks the active tab's id + its result
    // existence. Selecting both as a record means switching tabs or
    // running a query updates this; mere width drags don't.
    final exportKey = context.select<AppState, (String?, bool)>((s) {
      final tab = s.activeTab;
      final result = exportableResult(tab);
      return (tab?.id, result != null);
    });
    final canExport = exportKey.$2;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _windowChannel.invokeMethod('startDrag'),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          // Match the design's `var(--toolbar)` (bg at 72% alpha) so the
          // app's radial accent halo bleeds through. backdrop-filter blur is
          // not feasible to layer cheaply per-frame; the alpha is the visual
          // tell here, not the blur.
          color: AppColors.bg.withValues(alpha: 0.72),
          border: Border(
            bottom: BorderSide(color: AppColors.hairline, width: 1),
          ),
        ),
        padding: EdgeInsets.only(
          left: _fullScreen ? 4 : _trafficLightInset,
          right: 4,
        ),
        child: Stack(
          children: [
            // Double-tap-to-zoom lives on a background layer *behind* the
            // button row, never as an ancestor of it. A
            // DoubleTapGestureRecognizer on an ancestor keeps the gesture
            // arena open for kDoubleTapTimeout (300ms) on every tap while it
            // waits for a possible second tap — that delay was making every
            // toolbar button feel sluggish. As a Stack sibling it only sees
            // taps that land on the empty toolbar background.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => _windowChannel.invokeMethod('toggleZoom'),
              ),
            ),
            Row(
              children: [
                TbIcon(
                  icon: Icons.view_sidebar_outlined,
                  tooltip: 'Toggle sidebar',
                  onPressed: state.toggleSidebar,
                ),
                const TbRail(),
                TbIcon(
                  icon: Icons.arrow_back,
                  tooltip: 'Back  ⌘[',
                  onPressed: canGoBack ? state.historyBack : null,
                ),
                TbIcon(
                  icon: Icons.arrow_forward,
                  tooltip: 'Forward  ⌘]',
                  onPressed: canGoForward ? state.historyForward : null,
                ),
                const SizedBox(width: 8),
                const TbGroupRail(),
                const SizedBox(width: 10),
                const ConnectionPill(),
                const SizedBox(width: 8),
                const TbGroupRail(),
                const SizedBox(width: 8),
                TbIcon(
                  icon: Icons.ios_share,
                  tooltip: 'Export…',
                  onPressed: canExport
                      ? () => openExportForActiveTab(
                          context,
                          state,
                          state.activeTab,
                        )
                      : null,
                ),
                const Spacer(),
                if (pending > 0) ...[
                  PendingPill(
                    count: pending,
                    onTap: () => openPendingForActiveTab(context, state),
                  ),
                  const TbRail(),
                ],
                // Fixed-width search pill — making it Flexible would force it
                // to compete with the Spacer above for leftover space, so on a
                // wide window the spacer would collapse to half its slack and
                // the search would drift away from the right edge.
                SizedBox(
                  width: 220,
                  child: TbSearch(
                    onTap: () => showCommandPalette(context, state),
                  ),
                ),
                const TbRail(),
                TbIcon(
                  icon: brightness == AppBrightness.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  tooltip: 'Toggle theme',
                  onPressed: state.toggleBrightness,
                ),
                TbIcon(
                  icon: Icons.folder_outlined,
                  tooltip: 'Reveal config folder in Finder',
                  onPressed: revealConfigFolder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
