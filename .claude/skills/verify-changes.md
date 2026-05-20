---
name: verify-changes
description: Run before claiming any work is done — analyze + test + macOS build in one shot. Catches Swift / entitlement issues the analyzer misses. Use after every meaningful edit and before every commit.
---

The Flutter binary isn't on the default PATH (mise picks a different one).
Always prepend the flutter bin dir:

```bash
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter analyze 2>&1 | tail -15
```

Run the three steps in order. Each one catches issues the others don't:

```bash
# 1. Static analysis — Dart errors, unused imports, lint hints.
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter analyze 2>&1 | tail -15

# 2. Widget tests — boots the app to make sure nothing crashes on startup.
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter test 2>&1 | tail -5

# 3. macOS debug build — surfaces Swift / Xcode / entitlement breakage that
#    pure Dart analysis can't see (e.g. macos_window_utils registration).
export PATH="/Users/jwo1f/flutter/flutter/bin:$PATH" && flutter build macos --debug 2>&1 | tail -6
```

Or all together with `&& echo "===TEST===" &&` separators so the output is
readable in one tool call.

If `flutter analyze` reports `info`-level lints that aren't yours, leave
them — only fix ones introduced by your edits. If it reports `error`s or
`warning`s, fix them before moving on.

A green run on all three is the precondition for a commit. Don't claim
"done" before this passes.
