#!/usr/bin/env bash
# Builds the release app and packs it into a compressed DMG under dist/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

export PATH="/Users/jwo1f/flutter/bin:$PATH"

app_name="Aperture"
version="$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml)"
[ -n "$version" ] || { echo "make_dmg: no version: line in pubspec.yaml" >&2; exit 1; }

app="build/macos/Build/Products/Release/$app_name.app"
dist="$root/dist"
dmg="$dist/$app_name-$version.dmg"

echo "==> flutter build macos --release"
flutter build macos --release

[ -d "$app" ] || { echo "make_dmg: $app missing after build" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# ditto keeps the bundle's signature and extended attributes intact; cp -R does not.
ditto "$app" "$stage/$app_name.app"
ln -s /Applications "$stage/Applications"

mkdir -p "$dist"
rm -f "$dmg"

echo "==> hdiutil create $dmg"
hdiutil create \
  -volname "$app_name $version" \
  -srcfolder "$stage" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -quiet \
  "$dmg"

hdiutil verify -quiet "$dmg"

echo "==> $dmg ($(du -h "$dmg" | cut -f1))"
