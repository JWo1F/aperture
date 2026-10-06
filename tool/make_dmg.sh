#!/usr/bin/env bash
# Builds the release app and packs it into a compressed DMG under dist/.
#
# With DEVELOPER_ID set, the app and the DMG are signed for distribution
# (tool/sign_app.sh); with notary credentials too (see tool/notarize.sh),
# both are notarized and stapled. Without them the DMG is ad-hoc signed,
# which runs on this Mac and nowhere else without a Gatekeeper override.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

app_name="Aperture"
version="$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml)"
[ -n "$version" ] || { echo "make_dmg: no version: line in pubspec.yaml" >&2; exit 1; }

app="build/macos/Build/Products/Release/$app_name.app"
dist="$root/dist"
dmg="$dist/$app_name-$version.dmg"

echo "==> flutter build macos --release"
flutter build macos --release

[ -d "$app" ] || { echo "make_dmg: $app missing after build" >&2; exit 1; }

notary_credentials() {
  [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${APPLE_API_KEY_PATH:-}" ]
}

# The app is notarized and stapled on its own, before it goes into the
# DMG: Sparkle installs updates from the app inside the image, and a
# stapled app opens without a network check wherever it ends up.
if [ -n "${DEVELOPER_ID:-}" ]; then
  tool/sign_app.sh "$app"
  if notary_credentials; then
    tool/notarize.sh "$app"
  fi
fi

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

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$dmg"
  if notary_credentials; then
    tool/notarize.sh "$dmg"
  fi
fi

echo "==> $dmg ($(du -h "$dmg" | cut -f1))"
