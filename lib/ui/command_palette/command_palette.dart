import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/db_object.dart';
import '../../state/app_state.dart';
import '../../state/workspace_tab.dart';
import '../../theme/app_theme.dart';
import '../about/about_dialog.dart';

/// Opens the global command palette (⌘K). Resolves when it closes.
Future<void> showCommandPalette(BuildContext context, AppState state) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close palette',
    barrierColor: const Color(0x88060708),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = Curves.easeOutCubic.transform(anim.value);
      return Opacity(
        opacity: curved,
        child: Transform.translate(
          offset: Offset(0, -10 * (1 - curved)),
          child: Transform.scale(
            scale: 0.985 + 0.015 * curved,
            child: _PaletteScaffold(state: state),
          ),
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
      alignment: const Alignment(0, -0.5),
      child: Material(
        color: Colors.transparent,
        child: _Palette(state: state),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item model
// ---------------------------------------------------------------------------

/// What a palette row represents. The ordering of the enum is also the
/// section ordering of the idle (empty-query) view and the tie-break order
/// when two search hits score equally.
enum _Kind { openTab, command, recent, favorite, savedQuery, connection, table }

extension on _Kind {
  /// Uppercase eyebrow shown above each group in the idle view.
  String get section => switch (this) {
    _Kind.openTab => 'Open tabs',
    _Kind.command => 'Commands',
    _Kind.recent => 'Recent',
    _Kind.favorite => 'Pinned',
    _Kind.savedQuery => 'Saved queries',
    _Kind.connection => 'Connections',
    _Kind.table => 'Tables',
  };

  /// (label, tint) for the trailing chip.
  (String, Color) get chip => switch (this) {
    _Kind.openTab => ('tab', AppColors.accent),
    _Kind.command => ('action', AppColors.accent),
    _Kind.recent => ('recent', AppColors.warning),
    _Kind.favorite => ('pinned', AppColors.warning),
    _Kind.savedQuery => ('query', AppColors.tJson),
    _Kind.connection => ('conn', AppColors.success),
    _Kind.table => ('table', AppColors.info),
  };

  /// A small constant added to a hit's score so that, on a near-tie, the
  /// more actionable kinds (a command, a tab to jump to) sort above a raw
  /// table name. Kept far below the magnitude of a real fuzzy match so it
  /// only ever breaks ties.
  double get bias => switch (this) {
    _Kind.command => 8,
    _Kind.openTab => 6,
    _Kind.recent => 5,
    _Kind.favorite => 5,
    _Kind.savedQuery => 3,
    _Kind.connection => 2,
    _Kind.table => 0,
  };
}

class _Item {
  _Item({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.run,
    this.tokens = '',
    this.accent = false,
  });

  final _Kind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback run;

  /// Extra hidden text folded into the search index — host names, fully
  /// qualified identifiers, command synonyms. Never displayed.
  final String tokens;

  /// When true the row's icon tile carries the accent tint even when not
  /// selected (used for the live connection / active tab).
  final bool accent;

  String get _haystack => '$subtitle $tokens';
}

/// A search hit: the item plus its score and the matched character offsets
/// inside [Item.title] (used to highlight the run).
class _Hit {
  _Hit(this.item, this.score, this.highlight);

  final _Item item;
  final double score;
  final List<int> highlight;
}

// ---------------------------------------------------------------------------
// Fuzzy matcher
// ---------------------------------------------------------------------------

class _Match {
  const _Match(this.score, this.indices);

  final int score;
  final List<int> indices;
}

/// Word-boundary-aware fuzzy subsequence matcher.
///
/// Finds the best-scoring way to match every character of [query] against
/// [text] in order. Returns null when [query] is not a subsequence of
/// [text]. A match that lands on word starts (`users` in `app_users`) and
/// runs contiguously outscores one whose characters are scattered, so the
/// ranking promotes the result a human would point at.
_Match? _fuzzy(String query, String text) {
  if (query.isEmpty) return const _Match(0, <int>[]);
  final q = query.toLowerCase();
  final t = text.toLowerCase();
  if (q.length > t.length) return null;

  bool boundary(int i) {
    if (i == 0) return true;
    final prev = text.codeUnitAt(i - 1);
    // Separators that begin a new word.
    if (prev == 0x20 || prev == 0x5F || prev == 0x2E ||
        prev == 0x2D || prev == 0x2F) {
      return true;
    }
    // camelCase / digit→letter boundary.
    final cur = text.codeUnitAt(i);
    final prevWord = (prev >= 0x61 && prev <= 0x7A) ||
        (prev >= 0x30 && prev <= 0x39);
    final curUpper = cur >= 0x41 && cur <= 0x5A;
    return prevWord && curUpper;
  }

  final stride = t.length + 1;
  final memo = <int, _Match?>{};

  // Best match of q[qi..] against t[ti..]. Memoised on (qi, ti) so the
  // branch-and-explore stays linear in the size of the DP table.
  _Match? solve(int qi, int ti) {
    if (qi == q.length) return const _Match(0, <int>[]);
    if (ti >= t.length) return null;
    final key = qi * stride + ti;
    if (memo.containsKey(key)) return memo[key];

    _Match? best;
    for (var i = ti; i < t.length; i++) {
      if (t.codeUnitAt(i) != q.codeUnitAt(qi)) continue;
      final rest = solve(qi + 1, i + 1);
      if (rest == null) continue;
      var gain = 1;
      if (boundary(i)) gain += 12;
      if (i == 0) gain += 8;
      if (rest.indices.isNotEmpty && rest.indices.first == i + 1) gain += 10;
      // Penalise characters skipped before the very first match.
      if (qi == 0 && i > 0) gain -= i > 6 ? 6 : i;
      final score = gain + rest.score;
      if (best == null || score > best.score) {
        best = _Match(score, <int>[i, ...rest.indices]);
      }
    }
    memo[key] = best;
    return best;
  }

  return solve(0, 0);
}

/// Scores [item] against [query]. A title hit always beats a hit found only
/// in the hidden haystack, which keeps "users" ranking the `users` table
/// above a table whose comment merely mentions users.
///
/// On top of the raw fuzzy score, three bonuses keep the obvious answer on
/// top: an exact name match wins outright, a prefix match is strongly
/// promoted, and a coverage term rewards matching a large fraction of the
/// name — so the short `users` outranks the long `user_notification_settings`
/// even though the latter's characters happen to land on word boundaries.
_Hit? _score(_Item item, String query) {
  final q = query.toLowerCase();
  final title = _fuzzy(query, item.title);
  if (title != null) {
    var score = title.score + item.kind.bias;
    final name = item.title.toLowerCase();
    if (name == q) {
      score += 120;
    } else if (name.startsWith(q)) {
      score += 45;
    }
    score += 20 * (q.length / item.title.length);
    return _Hit(item, score, title.indices);
  }
  final aux = _fuzzy(query, item._haystack);
  if (aux != null) {
    return _Hit(item, aux.score * 0.45 + item.kind.bias, const []);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------

sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.kind, this.count);

  final _Kind kind;
  final int count;
}

class _ItemRow extends _Row {
  _ItemRow(this.item, this.highlight);

  final _Item item;
  final List<int> highlight;

  /// Position in the flat selectable list — assigned during [_build] so the
  /// list builder doesn't have to scan to recover it.
  int index = 0;
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
  final _scroll = ScrollController();
  final _selectedKey = GlobalKey();

  int _selected = 0;

  /// Flat list of selectable rows from the most recent build — read by the
  /// key handler so arrow keys and ↵ act on exactly what's painted.
  List<_ItemRow> _items = const [];

  @override
  void initState() {
    super.initState();
    // Intercept navigation keys before the TextField's own actions — a
    // FocusNode's onKeyEvent runs first in the key event chain.
    _focus.onKeyEvent = _onKey;
    _controller.addListener(() => setState(() => _selected = 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // --- Item sources --------------------------------------------------------

  List<_Item> _commands() {
    final state = widget.state;
    final connected = state.status == ConnectionStatus.connected;
    final out = <_Item>[];

    if (connected) {
      out.add(_Item(
        kind: _Kind.command,
        title: 'New query',
        subtitle: 'Open a blank SQL editor tab',
        icon: Icons.terminal_rounded,
        tokens: 'sql editor scratch run',
        run: state.newQueryTab,
      ));
      final active = state.activeTab;
      if (active is TableTab) {
        out.add(_Item(
          kind: _Kind.command,
          title: 'Refresh this table',
          subtitle: 'Re-fetch the current page of ${active.table.name}',
          icon: Icons.sync_rounded,
          tokens: 'reload requery',
          run: () => state.refreshTable(active),
        ));
      }
      out.add(_Item(
        kind: _Kind.command,
        title: 'Refresh catalog',
        subtitle: 'Re-introspect schemas, tables and types',
        icon: Icons.refresh_rounded,
        tokens: 'reload schema introspect',
        run: state.refreshCatalog,
      ));
      if (state.canGoBack) {
        out.add(_Item(
          kind: _Kind.command,
          title: 'Go back',
          subtitle: 'Step back through tab and filter history  ⌘[',
          icon: Icons.arrow_back_rounded,
          tokens: 'history previous navigate',
          run: state.historyBack,
        ));
      }
      if (state.canGoForward) {
        out.add(_Item(
          kind: _Kind.command,
          title: 'Go forward',
          subtitle: 'Step forward through history  ⌘]',
          icon: Icons.arrow_forward_rounded,
          tokens: 'history next navigate',
          run: state.historyForward,
        ));
      }
    }

    out.add(_Item(
      kind: _Kind.command,
      title: 'Toggle sidebar',
      subtitle: 'Show or hide the schema browser',
      icon: Icons.view_sidebar_outlined,
      tokens: 'panel tree tables hide',
      run: state.toggleSidebar,
    ));
    out.add(_Item(
      kind: _Kind.command,
      title: 'Activity log',
      subtitle: 'Show or hide the SQL event log  ⌘L',
      icon: Icons.receipt_long_outlined,
      tokens: 'events console history queries',
      run: state.eventLog.toggleVisible,
    ));
    final dark = state.brightness == AppBrightness.dark;
    out.add(_Item(
      kind: _Kind.command,
      title: dark ? 'Switch to light theme' : 'Switch to dark theme',
      subtitle: 'Flip the workspace between Aperture dark and light',
      icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tokens: 'appearance dark light mode color',
      run: state.toggleBrightness,
    ));

    if (connected) {
      out.add(_Item(
        kind: _Kind.command,
        title: 'Disconnect',
        subtitle: state.activeConnection?.summary ?? 'Close the session',
        icon: Icons.power_settings_new_rounded,
        tokens: 'close session logout end',
        run: state.disconnect,
      ));
    }
    out.add(_Item(
      kind: _Kind.command,
      title: 'About dbv',
      subtitle: 'Version, keyboard shortcuts and credits',
      icon: Icons.info_outline_rounded,
      tokens: 'help shortcuts version',
      run: () => showAboutDbv(context),
    ));
    return out;
  }

  List<_Item> _openTabs() {
    final state = widget.state;
    final activeId = state.activeTab?.id;
    final out = <_Item>[];
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      final isActive = tab.id == activeId;
      final (label, icon) = switch (tab) {
        QueryTab() => ('SQL query', Icons.terminal_rounded),
        TableTab() => ('Table view', Icons.grid_on_rounded),
        SchemaTab() => ('Schema', Icons.schema_outlined),
      };
      out.add(_Item(
        kind: _Kind.openTab,
        title: tab.title,
        subtitle: isActive ? '$label · in view now' : label,
        icon: icon,
        accent: isActive,
        run: () => state.selectTab(i),
      ));
    }
    return out;
  }

  List<_Item> _savedQueries() {
    final state = widget.state;
    return [
      for (final q in state.savedQueries)
        _Item(
          kind: _Kind.savedQuery,
          title: q.name,
          subtitle: _sqlPreview(q.sql),
          icon: Icons.bookmark_outline_rounded,
          tokens: q.sql,
          run: () => state.openSavedQuery(q),
        ),
    ];
  }

  List<_Item> _connections() {
    final state = widget.state;
    final activeId = state.activeConnection?.id;
    return [
      for (final c in state.connections)
        _Item(
          kind: _Kind.connection,
          title: c.name,
          subtitle: c.id == activeId ? '${c.summary} · connected' : c.summary,
          icon: c.id == activeId ? Icons.lan_rounded : Icons.lan_outlined,
          accent: c.id == activeId,
          tokens: '${c.host} ${c.database} ${c.username}',
          run: () => state.connect(c),
        ),
    ];
  }

  _Item _tableItem(DbTable t, _Kind kind, String subtitle) {
    return _Item(
      kind: kind,
      title: t.name,
      subtitle: subtitle,
      icon: t.isView ? Icons.visibility_outlined : Icons.table_rows_outlined,
      tokens: '${t.schema} ${t.qualifiedName}',
      run: () => widget.state.openTable(t),
    );
  }

  List<_Item> _allTables() {
    final out = <_Item>[];
    for (final s in widget.state.schemas) {
      for (final t in s.tables) {
        out.add(_tableItem(
          t,
          _Kind.table,
          t.isView ? '${t.schema} · view' : t.schema,
        ));
      }
    }
    return out;
  }

  /// The full searchable index used while the user is typing.
  List<_Item> _searchPool() => [
        ..._commands(),
        ..._openTabs(),
        ..._savedQueries(),
        ..._connections(),
        ..._allTables(),
      ];

  // --- Row assembly --------------------------------------------------------

  /// Builds the painted rows plus the flat list of selectable items.
  (List<_Row>, List<_ItemRow>) _build() {
    final query = _controller.text.trim();
    final rows = <_Row>[];
    final items = <_ItemRow>[];

    if (query.isEmpty) {
      // Idle view: a curated, grouped snapshot — not every table in the
      // database — so ⌘K is useful before the first keystroke.
      final state = widget.state;
      final groups = <_Kind, List<_Item>>{
        _Kind.openTab: _openTabs(),
        _Kind.recent: [
          for (final t in state.recents.take(6))
            _tableItem(t, _Kind.recent, 'in ${t.schema}'),
        ],
        _Kind.favorite: [
          for (final t in state.favoriteTables.take(5))
            _tableItem(t, _Kind.favorite, 'in ${t.schema}'),
        ],
        _Kind.savedQuery: _savedQueries().take(5).toList(),
        _Kind.connection:
            state.status == ConnectionStatus.connected ? const [] : _connections(),
        _Kind.command: _commands(),
      };
      for (final entry in groups.entries) {
        if (entry.value.isEmpty) continue;
        rows.add(_HeaderRow(entry.key, entry.value.length));
        for (final item in entry.value) {
          final row = _ItemRow(item, const [])..index = items.length;
          rows.add(row);
          items.add(row);
        }
      }
    } else {
      // Search view: one globally-ranked list, best match first.
      final hits = <_Hit>[];
      for (final item in _searchPool()) {
        final hit = _score(item, query);
        if (hit != null) hits.add(hit);
      }
      hits.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byKind = a.item.kind.index.compareTo(b.item.kind.index);
        if (byKind != 0) return byKind;
        final byLen = a.item.title.length.compareTo(b.item.title.length);
        if (byLen != 0) return byLen;
        return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
      });
      for (final hit in hits) {
        final row = _ItemRow(hit.item, hit.highlight)..index = items.length;
        rows.add(row);
        items.add(row);
      }
    }
    return (rows, items);
  }

  // --- Interaction ---------------------------------------------------------

  void _run(_Item item) {
    Navigator.of(context).pop();
    item.run();
  }

  void _move(int delta) {
    if (_items.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % _items.length;
      if (_selected < 0) _selected += _items.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
        );
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (_items.isNotEmpty) {
          _run(_items[_selected.clamp(0, _items.length - 1)].item);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final (rows, items) = _build();
    _items = items;
    final selected = items.isEmpty ? 0 : _selected.clamp(0, items.length - 1);
    final query = _controller.text.trim();

    return Container(
      width: 600,
      constraints: const BoxConstraints(maxHeight: 484),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: Radii.brLg,
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 48, offset: Offset(0, 16)),
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: Radii.brLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SearchField(
              controller: _controller,
              focusNode: _focus,
              onClear: () {
                _controller.clear();
                _focus.requestFocus();
              },
            ),
            Divider(height: 1, color: AppColors.hairline),
            Flexible(
              child: items.isEmpty
                  ? _EmptyState(query: query)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        if (row is _HeaderRow) {
                          return _GroupHeader(kind: row.kind, count: row.count);
                        }
                        row as _ItemRow;
                        final index = row.index;
                        final isSelected = index == selected;
                        return _ResultRow(
                          key: isSelected ? _selectedKey : null,
                          item: row.item,
                          highlight: row.highlight,
                          selected: isSelected,
                          onTap: () => _run(row.item),
                          onHover: () {
                            if (_selected != index) {
                              setState(() => _selected = index);
                            }
                          },
                        );
                      },
                    ),
            ),
            _Footer(query: query, count: items.length),
          ],
        ),
      ),
    );
  }
}

String _sqlPreview(String sql) {
  final flat = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return 'Empty query';
  return flat.length > 96 ? '${flat.substring(0, 96)}…' : flat;
}

// ---------------------------------------------------------------------------
// Search field
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 19, color: AppColors.textSecondary),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              cursorColor: AppColors.accent,
              cursorWidth: 1.6,
              cursorHeight: 17,
              style: AppTheme.ui(size: 15, weight: FontWeight.w400),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search tables, run a command, jump to a tab…',
                hintStyle: AppTheme.ui(
                  size: 15,
                  color: AppColors.textMuted,
                  weight: FontWeight.w400,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) {
                return const _KeyCap(label: 'esc');
              }
              return _ClearButton(onTap: onClear);
            },
          ),
        ],
      ),
    );
  }
}

class _ClearButton extends StatefulWidget {
  const _ClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ClearButton> createState() => _ClearButtonState();
}

class _ClearButtonState extends State<_ClearButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceHover : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Icon(
            Icons.close_rounded,
            size: 14,
            color: _hover ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.kind, required this.count});

  final _Kind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 5),
      child: Row(
        children: [
          Text(kind.section.toUpperCase(), style: AppTheme.eyebrow()),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: AppTheme.eyebrow(color: AppColors.text4),
          ),
          const SizedBox(width: 9),
          Expanded(child: Container(height: 1, color: AppColors.hairline)),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.item,
    required this.highlight,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final _Item item;
  final List<int> highlight;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final (chipLabel, chipColor) = item.kind.chip;
    final tileAccent = selected || item.accent;
    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: Radii.brSm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 3,
                child: selected
                    ? Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 7),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tileAccent
                      ? AppColors.accent.withValues(alpha: 0.16)
                      : AppColors.surface2,
                  borderRadius: Radii.brSm,
                  border: Border.all(
                    color: tileAccent
                        ? AppColors.accent.withValues(alpha: 0.30)
                        : AppColors.border,
                  ),
                ),
                child: Icon(
                  item.icon,
                  size: 15,
                  color: tileAccent ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: item.title,
                      highlight: highlight,
                      style: AppTheme.mono(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      matchColor: AppColors.accentHover,
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.ui(
                          size: 11,
                          weight: FontWeight.w400,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _KindChip(label: chipLabel, color: chipColor),
              SizedBox(
                width: 30,
                child: selected
                    ? Center(
                        child: Icon(
                          Icons.keyboard_return_rounded,
                          size: 13,
                          color: AppColors.accent,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.highlight,
    required this.style,
    required this.matchColor,
  });

  final String text;
  final List<int> highlight;
  final TextStyle style;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    if (highlight.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final hit = List<bool>.filled(text.length, false);
    for (final i in highlight) {
      if (i >= 0 && i < text.length) hit[i] = true;
    }
    final matchStyle = style.copyWith(
      color: matchColor,
      fontWeight: FontWeight.w700,
    );
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final on = hit[i];
      var j = i;
      while (j < text.length && hit[j] == on) {
        j++;
      }
      spans.add(TextSpan(text: text.substring(i, j), style: on ? matchStyle : style));
      i = j;
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.brSm,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: AppTheme.mono(size: 9.5, color: color, weight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state + footer
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 44, 32, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.bolt_outlined,
            size: 30,
            color: AppColors.text4,
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'No matches for "$query"' : 'Nothing to jump to yet',
            style: AppTheme.ui(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            searching
                ? 'Try a table name, a connection, or a command like "theme".'
                : 'Connect to a database to search its tables and queries.',
            textAlign: TextAlign.center,
            style: AppTheme.ui(
              size: 11.5,
              weight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.query, required this.count});

  final String query;
  final int count;

  @override
  Widget build(BuildContext context) {
    final left = query.isEmpty
        ? 'Quick access'
        : '$count match${count == 1 ? '' : 'es'}';
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.bgDeep,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text(
            left,
            style: AppTheme.mono(size: 10.5, color: AppColors.textMuted),
          ),
          const Spacer(),
          _Hint(keys: const ['↑', '↓'], label: 'Navigate'),
          const SizedBox(width: 12),
          _Hint(keys: const ['↵'], label: 'Open'),
          const SizedBox(width: 12),
          _Hint(keys: const ['esc'], label: 'Close'),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.label});

  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys) ...[
          _KeyCap(label: k),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: AppTheme.ui(size: 10.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        // height: 1.0 collapses the mono font's 1.4 line box so the glyph
        // sits centred in the 18px cap instead of riding its top edge.
        style: AppTheme.mono(
          size: 10,
          color: AppColors.textMuted,
          weight: FontWeight.w500,
        ).copyWith(height: 1.0),
      ),
    );
  }
}
