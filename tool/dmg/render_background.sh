#!/usr/bin/env bash
# Renders background.svg to background.png and background@2x.png, which
# dmgbuild folds into one HiDPI TIFF. The PNGs are committed, so a release
# needs no SVG renderer; run this after editing the SVG.
#
# Needs rsvg-convert (brew install librsvg). The text is set in the app's
# bundled fonts, handed to rsvg through a private fontconfig file.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fonts="$(cd "$here/../../assets/fonts" && pwd)"
conf="$(mktemp)"
trap 'rm -f "$conf"' EXIT
cat > "$conf" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><dir>$fonts</dir><cachedir>$(mktemp -d)</cachedir></fontconfig>
XML

for scale in 1 2; do
  suffix=""
  [ "$scale" = 2 ] && suffix="@2x"
  PANGOCAIRO_BACKEND=fc FONTCONFIG_FILE="$conf" rsvg-convert --zoom "$scale" \
    -o "$here/background$suffix.png" "$here/background.svg"
done
