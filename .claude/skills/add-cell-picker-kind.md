---
name: add-cell-picker-kind
description: Use when adding support for a new Postgres column type in the cell editor overlay (UUID, interval, enum, inet, money, …). Walks through every place that needs to know about the new kind.
---

The cell picker lives in `lib/ui/cell_picker/cell_picker.dart`. Adding a
new editor kind touches five spots in a predictable order.

## 1. The `_KindId` enum + a `_Kind` constant

Top of the file:

```dart
enum _KindId { text, bool, json, date, time, datetime /* , uuid */ }
```

Below the existing `_kBool` / `_kJson` / etc. add the constant — pick a
size that fits the input UI you intend to render. Use `Size(252, 126)`
as the baseline compact size; bump if there's a calendar or a multi-line
body. If your kind reuses the text body, set `id: _KindId.text` and just
configure formatters/multiline differently.

```dart
final _kUuid = _Kind(
  id: _KindId.text,           // reuse text body if no custom editor needed
  label: 'uuid',
  color: AppColors.sqlNumber, // or whatever fits the palette
  size: const Size(320, 132),
  inputFormatters: [_uuidFilter],
);
```

If the column type has a "with time zone" variant or any optional mode,
add a separate constant for it and a `withTimezone: true` (or your own
new flag on `_Kind`).

## 2. Type detection in `_kindFor`

`_kindFor(value, dataType)` is the only place that maps Postgres data
types to kinds. The catalog `dataType` is the authoritative signal —
runtime value class is a fallback for query results without metadata.

```dart
if (dt == 'uuid') return _kUuid;
```

Place these before the broad fallback branches (string, etc.). Order
matters when types share prefixes (e.g. `timestamp` vs `time`).

For runtime-only fallback (when `dataType` is null), add a class check
at the bottom:

```dart
if (v is YourDartType) return _kUuid;
```

## 3. State for a new body kind (only if the kind has its own _KindId)

`_PanelState` holds state per kind. If you're reusing `_KindId.text`,
**no state changes are needed** — the existing text path handles input
filters / sizing automatically.

If you really need a new body kind (your own enum value), add state
slots:

```dart
// In _PanelState fields
SomeType? _yourState;
SomeType? _baselineYourState;
```

And initialize / commit / dirty-check it in `initState`, `_save`, and
`_isDirty` for that kind.

## 4. Routing in `_buildBody`

If you reuse `_KindId.text`, **skip this step**. Otherwise add a `case`:

```dart
case _KindId.yourKind:
  return _YourBody(
    initial: _yourState,
    onChange: (next) => setState(() => _yourState = next),
  );
```

Define `_YourBody` as a StatelessWidget or StatefulWidget that renders
the input UI. Wrap it in a `Container(color: AppColors.bg)`. Pad
appropriately.

## 5. Save format

`_save` builds a `CellLiteral(stringValue)`. The string must be valid
Postgres syntax for that type *without* an explicit cast — Postgres will
coerce from the unknown literal. For most types this is the obvious
"text representation":

- UUID: `'550e8400-e29b-41d4-a716-446655440000'`
- interval: `'1 day 2 hours'`
- inet: `'192.168.1.1/24'`

If the input editor doesn't already validate format, parse on `_save`
and show an inline error (see the JSON path's `_jsonError` for the
pattern).

## 6. Today/Now (if it makes sense for the type)

Only date/time/datetime kinds currently expose a Today/Now footer icon.
If your new type has a "current value" notion (e.g. a UUID v4
generator?), wire it through:

- Add `_supportsNow()` case → return `true`
- Provide `_setToNow()` for the kind
- Footer renders the icon when `onNow != null`

## Checklist

- [ ] Constant added in `_Kind` block
- [ ] `_kindFor` mapping for the dataType string
- [ ] `_kindFor` runtime fallback (only if a Dart class signals it)
- [ ] New body widget (only if `_KindId.text` doesn't suffice)
- [ ] `_save` produces a Postgres-acceptable literal
- [ ] `_isDirty` returns true when the new state differs from baseline
- [ ] Verified with `flutter analyze && flutter build macos --debug`
