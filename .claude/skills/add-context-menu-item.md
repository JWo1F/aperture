---
name: add-context-menu-item
description: Use when adding a right-click action anywhere — cells, table rows in the sidebar, tabs, saved queries, connections. Surfaces the shared menu primitive and conventions for icon / label / shortcut / danger styling.
---

Every right-click menu in the app goes through one primitive:
`showContextMenu` in `lib/ui/widgets/context_menu.dart`. Items are a
sealed `CmEntry` — either `CmItem` or `CmDivider`.

## Trigger pattern

Wrap the clickable region with `GestureDetector(onSecondaryTapDown: …)`
to get the global position for the menu anchor:

```dart
GestureDetector(
  onTap: openIt,
  onSecondaryTapDown: (d) => _openMenu(d.globalPosition),
  child: …,
)
```

For mouse users who prefer a button: also surface a `more_horiz` icon
on hover (see `_TableRow` in the sidebar for the pattern):

```dart
if (_hover && !widget.active)
  GestureDetector(
    onTapDown: (d) => _openMenu(d.globalPosition),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.more_horiz, size: 13, color: AppColors.textMuted),
    ),
  ),
```

## Building the menu

```dart
void _openMenu(Offset position) {
  showContextMenu(
    context,
    globalPosition: position,
    entries: [
      CmItem(
        icon: Icons.north_east,
        label: 'Open',
        onTap: () => state.doOpen(item),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.label_outline,
        label: 'Copy name',
        onTap: () => Clipboard.setData(ClipboardData(text: item.name)),
      ),
      const CmDivider(),
      CmItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        danger: true,
        onTap: () => state.delete(item),
      ),
    ],
  );
}
```

## Item conventions

- **Order**: primary action first → destructive last (with a `CmDivider`
  separating destructive items).
- **Icons**: always set one. Outline variants (`*_outlined`) for neutral
  actions, filled for destructive / "danger" ones. Look up existing items
  in `results_grid.dart` / `sidebar.dart` / `connection_menu.dart` for
  precedent before inventing a new icon.
- **`shortcut`**: pass the visible key hint (`'⌘C'`, `'⏎'`, `'⌘⌫'`) for
  items that have a global keyboard shortcut. Don't fabricate shortcuts
  that aren't wired anywhere.
- **`enabled: false`**: use when the item makes sense in this context but
  isn't applicable to *this* row (e.g. "Set NULL" on a NOT NULL column).
  Combine with a label that explains why ("Set NULL (column is NOT NULL)")
  so the user understands the disabled state.
- **`danger: true`**: only on destructive actions (Delete, Drop, Close
  all). Renders with the error colour.
- **No "Cancel" / "Close" item**: clicking outside dismisses
  automatically. Don't add one.

## Conditional sections

`showContextMenu` accepts `List<CmEntry>` — build with spread + ifs:

```dart
entries: [
  CmItem(icon: …, label: 'Open', onTap: …),
  if (canEdit) ...[
    CmItem(icon: …, label: 'Edit', onTap: …),
    const CmDivider(),
  ],
  if (canDelete)
    CmItem(icon: …, label: 'Delete', danger: true, onTap: …),
],
```

Pre-compute optional dependencies above the entries list so the menu
doesn't render an awkward orphan divider when nothing follows it (see
how `_openCellMenu` computes `findOwner` before building entries).

## Position

The menu anchors at the click point (`globalPosition` from the tap
detail) and auto-clamps to the viewport. Don't try to compute screen
edges yourself.

## Checklist

- [ ] `GestureDetector.onSecondaryTapDown` captures the position
- [ ] Mouse-only users can reach the menu via a hover `more_horiz` icon
- [ ] Every item has an `icon`
- [ ] Destructive items use `danger: true` and sit last
- [ ] Disabled items use `enabled: false` + a label that explains why
- [ ] `showContextMenu` is the only menu primitive used (no
       `PopupMenuButton` or `showMenu` from Material)
