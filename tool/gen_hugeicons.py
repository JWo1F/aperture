#!/usr/bin/env python3
"""Regenerate lib/theme/hugeicons.dart from the upstream HugeIcons webfont CSS.

    python3 tool/gen_hugeicons.py [path/to/icons.css]

With no argument the CSS is fetched from CSS_URL. The matching font must be
saved as assets/fonts/hgi-stroke-rounded.ttf; the two are versioned together
upstream, so refresh both or neither.
"""

import pathlib
import re
import sys
import urllib.request

CSS_URL = "https://use.hugeicons.com/font/icons.css"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "lib" / "theme" / "hugeicons.dart"

# Dart keywords that cannot be used bare as a member name.
RESERVED = {
    "assert", "break", "case", "catch", "class", "const", "continue", "default",
    "do", "else", "enum", "extends", "false", "final", "finally", "for", "if",
    "in", "is", "new", "null", "rethrow", "return", "super", "switch", "this",
    "throw", "true", "try", "var", "void", "while", "with",
}

ENTRY = re.compile(
    r'\.hgi-stroke\.hgi-([a-z0-9-]+)::before\s*\{\s*content:\s*"\\([0-9a-fA-F]+)"'
)


def camel(name: str) -> str:
    head, *tail = name.split("-")
    ident = head + "".join(p[:1].upper() + p[1:] for p in tail)
    if ident[0].isdigit():
        ident = "i" + ident
    return ident + "Icon" if ident in RESERVED else ident


def main() -> int:
    if len(sys.argv) > 1:
        css = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    else:
        with urllib.request.urlopen(CSS_URL) as response:
            css = response.read().decode("utf-8")

    entries = ENTRY.findall(css)
    if not entries:
        sys.exit("no icons parsed — did the upstream CSS format change?")

    # Upstream ships pairs like `arrow-down-01` / `arrow-down01` that are
    # distinct glyphs but camelize identically. The hyphen-rich spelling keeps
    # the plain name; the glued one takes an `Alt` suffix, so the assignment is
    # a property of the names rather than of iteration order.
    buckets: dict[str, list[tuple[str, int]]] = {}
    for name, code in entries:
        buckets.setdefault(camel(name), []).append((name, int(code, 16)))

    rows: list[tuple[str, str, int]] = []
    for ident, members in buckets.items():
        members.sort(key=lambda m: -m[0].count("-"))
        for index, (name, code) in enumerate(members):
            rows.append((ident + "Alt" * index, name, code))
    rows.sort(key=lambda r: r[0])

    body = "\n\n".join(
        f"  /// `{name}`\n"
        f"  static const IconData {ident} = IconData(0x{code:x}, fontFamily: _family);"
        for ident, name, code in rows
    )

    OUT.write_text(
        "// GENERATED — do not edit by hand. See tool/gen_hugeicons.py.\n"
        "//\n"
        f"// Source: {CSS_URL} (family `hugeicons-stroke-rounded`),\n"
        "// paired with assets/fonts/hgi-stroke-rounded.ttf.\n"
        "\n"
        "import 'package:flutter/widgets.dart';\n"
        "\n"
        "/// Every glyph in the bundled HugeIcons stroke-rounded font, named after\n"
        "/// its upstream slug. This is the app's only icon source.\n"
        "abstract final class Hgi {\n"
        "  static const String _family = 'hugeicons';\n"
        "\n"
        f"{body}\n"
        "}\n",
        encoding="utf-8",
    )
    print(f"wrote {OUT.relative_to(ROOT)}: {len(rows)} icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
