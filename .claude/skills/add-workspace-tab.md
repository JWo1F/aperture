---
name: add-workspace-tab
description: Use when introducing a new tab type beyond Query / Table / Schema — e.g. an explain-plan viewer, a pgstats dashboard, a saved-procedure inspector. WorkspaceTab is a sealed class so the compiler will help, but a few non-obvious spots need updating.
---

`lib/state/workspace_tab.dart` defines:

```dart
sealed class WorkspaceTab { … }
class QueryTab extends WorkspaceTab { … }
class TableTab extends WorkspaceTab { … }
class SchemaTab extends WorkspaceTab { … }
```

The `sealed` modifier makes Dart's exhaustive switch work for us. Adding
a new subclass means the compiler will yell at every `switch (tab)`
expression that isn't updated — use that.

## 1. Add the subclass

```dart
class PlanTab extends WorkspaceTab {
  PlanTab(super.id, this.sql, {this.name = 'Plan'});

  final String sql;
  String name;
  PlanResult? result;
  bool loading = false;

  @override
  String get title => name;
}
```

Keep persistent state on the tab (`name`, `sql`, `result`); transient
loading flags on the tab itself; column-width-style preferences in the
inherited `columnWidths` if you'll render a grid.

## 2. Update the workspace switch

`lib/ui/workspace/workspace.dart` → `_content`:

```dart
Widget _content(WorkspaceTab tab) {
  final key = ValueKey(tab.id);
  return switch (tab) {
    QueryTab() => QueryEditor(key: key, tab: tab),
    TableTab() => TableView(key: key, tab: tab),
    SchemaTab() => SchemaView(key: key, tab: tab),
    PlanTab() => PlanView(key: key, tab: tab),
  };
}
```

## 3. Pick a tab strip icon

In `workspace.dart` → `_TabState._tabIcon`:

```dart
IconData get _tabIcon => switch (widget.tab) {
      QueryTab() => Icons.terminal,
      SchemaTab() => Icons.data_object,
      PlanTab() => Icons.account_tree_outlined,
      _ => Icons.table_rows_outlined,
    };
```

## 4. Build the view widget

Mirror the structure of `SchemaView` (for read-only) or `QueryEditor`
(for interactive). All views are:

- A `Column` with a `Container(height: 40-44px)` toolbar at the top.
- The main content in `Expanded`.
- Optionally a bottom status bar (`Container(height: 28-30)`).

Toolbar conventions (see `query_editor.dart`):
- Group actions with `Rail` widgets between logical clusters.
- Primary action as `AppButton(primary: true)`, secondary as
  `AppButton` (no primary), icon-only as `IconAction`.
- Keyboard hints as `KbdChip('⌘↵')` right after the action they
  describe.

## 5. Open / focus from AppState

Add a method that creates or focuses the tab — pattern:

```dart
Future<void> openPlan(String sql) async {
  final tab = PlanTab(_nextId(), sql);
  _tabs.add(tab);
  _selectTab(_tabs.length - 1);
  await loadPlan(tab);  // your async work
}
```

If multiple opens of the same content should reuse the existing tab
(like `openTable` / `openSavedQuery`), key off something identifying
(qualified name, query id, etc.) and `_selectTab(existing)` instead of
creating a new one.

## 6. Navigation history

`_selectTab` pushes a `_NavSnapshot` via `_pushCurrentTab`. For plain
tabs (no per-tab state worth tracking in history), the default
`_NavSnapshot.focus(tab.id)` path is fine — your new tab type is
covered automatically.

If your tab has internal state worth navigating back/forward through
(like TableTab's filter / select / orderBy), extend `_NavSnapshot` and
`_applySnapshot` to handle the new fields.

## 7. Persistence (if applicable)

If the tab's content should survive restarts, store it under
`ConnectionConfig` (see the `persist-connection-field` skill). Tab ids
**match the saved-object ids** by convention so `openX` can focus an
existing tab if already open.

## Checklist

- [ ] New subclass extends `WorkspaceTab` with a `title` getter
- [ ] `Workspace._content` switch updated (compiler enforces this)
- [ ] `_TabState._tabIcon` updated
- [ ] View widget follows the existing toolbar + Expanded + status-bar
       shape, with `Rail` separators and `AppButton` / `IconAction`
       primitives
- [ ] `AppState` exposes `openX(...)` that creates or focuses
- [ ] Persistence wired if applicable
- [ ] `verify-changes` passes
