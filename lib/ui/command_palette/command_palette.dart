import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/app_store.dart';
import '../../state/catalog_controller.dart';
import '../../state/event_log.dart';
import '../../state/navigation_history.dart';
import '../../state/session_controller.dart';
import '../../state/connection_views.dart';
import '../../state/tabs_controller.dart';
import '../../theme/app_theme.dart';
import 'fuzzy_matcher.dart';
import 'item_model.dart';
import 'item_sources.dart';
import 'palette_deps.dart';
import 'widgets/empty_state.dart';
import 'widgets/footer.dart';
import 'widgets/group_header.dart';
import 'widgets/result_row.dart';
import 'widgets/search_field.dart';

/// Opens the global command palette (⌘K). Resolves when it closes.
///
/// Captures every controller the palette needs at the call site so the
/// dialog's own [BuildContext] (which sits below an Overlay and therefore
/// outside the provider scope of the caller) never has to look them up.
Future<void> showCommandPalette(BuildContext context) {
  final deps = PaletteDeps(
    appState: context.read<AppState>(),
    store: context.read<AppStore>(),
    session: context.read<SessionController>(),
    catalog: context.read<CatalogController>(),
    tabs: context.read<TabsController>(),
    history: context.read<NavigationHistory>(),
    eventLog: context.read<EventLog>(),
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close palette',
    barrierColor: AppColors.scrim,
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
            child: _PaletteScaffold(deps: deps),
          ),
        ),
      );
    },
  );
}

class _PaletteScaffold extends StatelessWidget {
  const _PaletteScaffold({required this.deps});

  final PaletteDeps deps;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.5),
      child: Material(
        color: Colors.transparent,
        child: _Palette(deps: deps),
      ),
    );
  }
}

sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.kind, this.count);

  final PaletteKind kind;
  final int count;
}

class _ItemRow extends _Row {
  _ItemRow(this.item, this.highlight);

  final PaletteItem item;
  final List<int> highlight;

  /// Position in the flat selectable list — assigned during [_PaletteState._build]
  /// so the list builder doesn't have to scan to recover it.
  int index = 0;
}

class _Palette extends StatefulWidget {
  const _Palette({required this.deps});

  final PaletteDeps deps;

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

  late final PaletteItemSource _source;

  /// Union of every searchable item — commands, open tabs, saved queries,
  /// connections, every table in the catalog. Built once at open-time
  /// because [PaletteDeps] captures its controllers when the palette is
  /// shown and the palette never subscribes to mid-session updates: closing
  /// and reopening ⌘K is the only way to pick up fresh data. Keeps each
  /// keystroke down to re-scoring this list instead of reallocating a
  /// [PaletteItem] per table.
  late final List<PaletteItem> _pool;

  @override
  void initState() {
    super.initState();
    // Intercept navigation keys before the TextField's own actions — a
    // FocusNode's onKeyEvent runs first in the key event chain.
    _focus.onKeyEvent = _onKey;
    _controller.addListener(() => setState(() => _selected = 0));
    _source = PaletteItemSource(deps: widget.deps, context: context);
    _pool = [
      ..._source.commands(),
      ..._source.openTabs(),
      ..._source.savedQueries(),
      ..._source.connections(),
      ..._source.allTables(),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // --- Row assembly --------------------------------------------------------

  /// Builds the painted rows plus the flat list of selectable items.
  (List<_Row>, List<_ItemRow>) _build() {
    final query = _controller.text.trim();
    final rows = <_Row>[];
    final items = <_ItemRow>[];

    if (query.isEmpty) {
      // Idle view: a curated, grouped snapshot — not every table in the
      // database — so ⌘K is useful before the first keystroke.
      final deps = widget.deps;
      final activeConn = deps.session.activeConnection;
      final recents = recentTablesView(activeConn, deps.catalog);
      final favorites = favoriteTablesView(activeConn, deps.catalog);
      final groups = <PaletteKind, List<PaletteItem>>{
        PaletteKind.openTab: _source.openTabs(),
        PaletteKind.recent: [
          for (final t in recents.take(6))
            _source.tableItem(t, PaletteKind.recent, 'in ${t.schema}'),
        ],
        PaletteKind.favorite: [
          for (final t in favorites.take(5))
            _source.tableItem(t, PaletteKind.favorite, 'in ${t.schema}'),
        ],
        PaletteKind.savedQuery: _source.savedQueries().take(5).toList(),
        PaletteKind.connection: deps.session.status == ConnectionStatus.connected
            ? const []
            : _source.connections(),
        PaletteKind.command: _source.commands(),
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
      // Search view: one globally-ranked list, best match first. Iterates
      // the pool cached at open-time so each keystroke is pure scoring with
      // no [PaletteItem] reallocation.
      final hits = <PaletteHit>[];
      for (final item in _pool) {
        final hit = scoreItem(item, query);
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

  void _run(PaletteItem item) {
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
        boxShadow: [
          BoxShadow(color: AppColors.shadow, blurRadius: 48, offset: const Offset(0, 16)),
          BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: Radii.brLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaletteSearchField(
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
                  ? PaletteEmptyState(query: query)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final row = rows[i];
                        if (row is _HeaderRow) {
                          return PaletteGroupHeader(kind: row.kind, count: row.count);
                        }
                        row as _ItemRow;
                        final index = row.index;
                        final isSelected = index == selected;
                        return PaletteResultRow(
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
            PaletteFooter(query: query, count: items.length),
          ],
        ),
      ),
    );
  }
}
