import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../about/about_dialog.dart';

/// Opens the global command palette. Resolves when it closes.
Future<void> showCommandPalette(BuildContext context, AppState state) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close palette',
    barrierColor: const Color(0x70000000),
    transitionDuration: const Duration(milliseconds: 130),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      return Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, -8 * (1 - anim.value)),
          child: _PaletteScaffold(state: state),
        ),
      );
    },
  );
}

class _PaletteScaffold extends StatelessWidget {
  const _PaletteScaffold({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: Colors.transparent,
        child: _Palette(state: state),
      ),
    );
  }
}

enum _CmdKind { action, connection, table, recent }

class _Cmd {
  _Cmd({
    required this.kind,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.run,
    this.searchTokens = const [],
  });

  final _CmdKind kind;
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback run;
  final List<String> searchTokens;

  bool matches(String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    if (label.toLowerCase().contains(needle)) return true;
    if (subtitle.toLowerCase().contains(needle)) return true;
    for (final t in searchTokens) {
      if (t.toLowerCase().contains(needle)) return true;
    }
    return false;
  }
}

class _Palette extends StatefulWidget {
  const _Palette({required this.state});
  final AppState state;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    // Intercept navigation keys *before* the TextField's own actions get a
    // turn — FocusNode.onKeyEvent runs first in the key event chain.
    _focus.onKeyEvent = _onKey;
    _controller.addListener(() => setState(() => _selected = 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Cmd> _allCommands() {
    final state = widget.state;
    final cmds = <_Cmd>[];

    // Actions
    if (state.status == ConnectionStatus.connected) {
      cmds.add(_Cmd(
        kind: _CmdKind.action,
        label: 'New Query',
        subtitle: 'Open a SQL editor tab',
        icon: Icons.terminal,
        run: state.newQueryTab,
      ));
      cmds.add(_Cmd(
        kind: _CmdKind.action,
        label: 'Refresh Catalog',
        subtitle: 'Re-introspect the database',
        icon: Icons.refresh,
        run: state.refreshCatalog,
      ));
      cmds.add(_Cmd(
        kind: _CmdKind.action,
        label: 'Disconnect',
        subtitle: state.activeConnection?.summary ?? '',
        icon: Icons.power_settings_new,
        run: state.disconnect,
      ));
    }

    cmds.add(_Cmd(
      kind: _CmdKind.action,
      label: 'Activity log',
      subtitle: 'Show / hide  ⌘L',
      icon: Icons.subject,
      run: state.eventLog.toggleVisible,
    ));
    cmds.add(_Cmd(
      kind: _CmdKind.action,
      label: 'About dbv',
      subtitle: 'Version + shortcuts',
      icon: Icons.info_outline,
      run: () => showAboutDbv(context),
    ));

    // Connections
    for (final conn in state.connections) {
      final isActive = state.activeConnection?.id == conn.id;
      cmds.add(_Cmd(
        kind: _CmdKind.connection,
        label: conn.name,
        subtitle: conn.summary,
        icon: isActive ? Icons.lan : Icons.lan_outlined,
        searchTokens: [conn.host, conn.database, conn.username],
        run: () => state.connect(conn),
      ));
    }

    // Recent tables
    for (final t in state.recents) {
      cmds.add(_Cmd(
        kind: _CmdKind.recent,
        label: t.name,
        subtitle: 'Recent · ${t.schema}',
        icon: Icons.history,
        searchTokens: [t.schema, t.qualifiedName],
        run: () => state.openTable(t),
      ));
    }

    // All tables
    for (final s in state.schemas) {
      for (final t in s.tables) {
        cmds.add(_Cmd(
          kind: _CmdKind.table,
          label: t.name,
          subtitle: t.schema,
          icon: t.isView
              ? Icons.visibility_outlined
              : Icons.table_rows_outlined,
          searchTokens: [t.schema, t.qualifiedName],
          run: () => state.openTable(t),
        ));
      }
    }

    return cmds;
  }

  List<_Cmd> _filtered() {
    final q = _controller.text;
    return _allCommands().where((c) => c.matches(q)).toList();
  }

  void _run(_Cmd cmd) {
    Navigator.of(context).pop();
    cmd.run();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final filtered = _filtered();
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected =
          filtered.isEmpty ? 0 : (_selected + 1) % filtered.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = filtered.isEmpty
          ? 0
          : (_selected - 1 + filtered.length) % filtered.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty) _run(filtered[_selected]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    final selected = filtered.isEmpty ? 0 : _selected.clamp(0, filtered.length - 1);

    return Container(
      width: 580,
      constraints: const BoxConstraints(maxHeight: 460),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brLg,
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 40,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SearchInput(controller: _controller, focusNode: _focus),
            Divider(height: 1, color: AppColors.border),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No matches',
                          style: AppTheme.ui(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _Row(
                        cmd: filtered[i],
                        selected: i == selected,
                        onTap: () => _run(filtered[i]),
                        onHover: () => setState(() => _selected = i),
                      ),
                    ),
            ),
            _Footer(count: filtered.length),
          ],
        ),
      );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput({required this.controller, required this.focusNode});
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              cursorColor: AppColors.accent,
              cursorHeight: 16,
              style: AppTheme.ui(size: 15, weight: FontWeight.w400),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Jump to a table, switch connections, run a command…',
                hintStyle: AppTheme.ui(
                  size: 15,
                  color: AppColors.textMuted,
                  weight: FontWeight.w400,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: Radii.brSm,
            ),
            child: Text(
              'esc',
              style: AppTheme.mono(size: 10, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cmd,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final _Cmd cmd;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: [
              Icon(
                cmd.icon,
                size: 15,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cmd.label,
                      style: AppTheme.ui(
                        size: 13,
                        weight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (cmd.subtitle.isNotEmpty)
                      Text(
                        cmd.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              _KindBadge(kind: cmd.kind),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});
  final _CmdKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      _CmdKind.action => ('action', AppColors.accent),
      _CmdKind.connection => ('conn', AppColors.success),
      _CmdKind.table => ('table', AppColors.info),
      _CmdKind.recent => ('recent', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: Radii.brSm,
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 9.5, color: color, weight: FontWeight.w600),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: const BorderRadius.vertical(bottom: Radii.lg),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text(
            '$count result${count == 1 ? '' : 's'}',
            style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          _KeyHint(keys: const ['↑', '↓'], label: 'navigate'),
          const SizedBox(width: 10),
          _KeyHint(keys: const ['↵'], label: 'open'),
        ],
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keys, required this.label});
  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: Radii.brSm,
            ),
            child: Text(
              k,
              style: AppTheme.mono(size: 10, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 3),
        ],
        Text(label,
            style: AppTheme.ui(size: 10.5, color: AppColors.textMuted)),
      ],
    );
  }
}
