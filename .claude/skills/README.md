# Skills

Project-local Claude skills. Each is a focused playbook for a recurring
task in this codebase.

| Skill | When to invoke |
|---|---|
| [verify-changes](verify-changes.md) | Before claiming work is done — analyze + test + macOS build |
| [commit-feature](commit-feature.md) | Right after a verified feature lands |
| [add-postgres-query](add-postgres-query.md) | New pg_catalog query or anything via the extended protocol |
| [add-cell-picker-kind](add-cell-picker-kind.md) | New column-type editor (UUID, interval, enum, …) |
| [persist-connection-field](persist-connection-field.md) | New persisted per-connection state |
| [add-context-menu-item](add-context-menu-item.md) | New right-click action anywhere |
| [add-export-format](add-export-format.md) | New export output format |
| [add-workspace-tab](add-workspace-tab.md) | New tab type beyond Query / Table / Schema |

These are guidance, not rituals — if a task doesn't fit one cleanly,
do what makes sense and update the skill afterward so the next session
has a better starting point.
