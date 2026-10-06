#!/usr/bin/env bash
# Re-signs a built Aperture.app with a Developer ID for distribution.
#
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" tool/sign_app.sh path/to/Aperture.app
#
# Xcode signs the app ad-hoc so a debug build needs no certificate. A
# distributed build must carry a Developer ID, the hardened runtime and a
# secure timestamp on every piece of code in it, or notarization refuses
# it. The runtime is applied here and not in the Xcode project: under the
# hardened runtime an ad-hoc app fails library validation against its own
# frameworks, which would break every local build.
#
# Signing goes inside-out — frameworks first, the app last — because a
# bundle's signature seals the signatures of the code nested in it.
# `--deep` is avoided for the same reason Apple advises against it: it
# signs nested code with the outer bundle's options and entitlements.
set -euo pipefail

app="${1:?usage: tool/sign_app.sh path/to/Aperture.app}"
: "${DEVELOPER_ID:?set DEVELOPER_ID to the signing identity, e.g. \"Developer ID Application: Name (TEAMID)\"}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
entitlements="$root/macos/Runner/Release.entitlements"

sign() {
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$@"
}

# Sparkle ships helper executables inside its framework; each is signed on
# its own, in the order Sparkle's documentation gives, and the Downloader
# keeps the entitlements it was built with.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [ -d "$sparkle" ]; then
  sign "$sparkle/Versions/B/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  sign "$sparkle/Versions/B/Autoupdate"
  sign "$sparkle/Versions/B/Updater.app"
  sign "$sparkle"
fi

find "$app/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) ! -name Sparkle.framework -print0 |
  while IFS= read -r -d '' code; do
    sign "$code"
  done

sign --entitlements "$entitlements" "$app"

codesign --verify --strict --deep --verbose=2 "$app"
echo "==> signed $app as $DEVELOPER_ID"
