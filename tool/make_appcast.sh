#!/usr/bin/env bash
# Signs the release DMG with Sparkle's EdDSA key and writes dist/appcast.xml,
# the one-item feed every installed copy polls (Info.plist's SUFeedURL
# points at the latest release's copy of it).
#
#   SPARKLE_ED_PRIVATE_KEY=… tool/make_appcast.sh
#
# Run after tool/make_dmg.sh, which leaves both the DMG and the resolved
# Sparkle package (and so its sign_update) under build/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

: "${SPARKLE_ED_PRIVATE_KEY:?set SPARKLE_ED_PRIVATE_KEY to the exported EdDSA private key}"

repo="https://github.com/JWo1F/aperture"
version="$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml)"
build="$(sed -n 's/^version: *[^+]*+\([0-9]*\).*/\1/p' pubspec.yaml)"
min_macos="$(sed -n 's/.*MACOSX_DEPLOYMENT_TARGET = \([0-9.]*\);/\1/p' macos/Runner.xcodeproj/project.pbxproj | head -1)"
[ -n "$version" ] && [ -n "$build" ] && [ -n "$min_macos" ] || {
  echo "make_appcast: could not read version, build number or deployment target" >&2
  exit 1
}

dmg="dist/Aperture-$version.dmg"
[ -f "$dmg" ] || { echo "make_appcast: $dmg missing — run tool/make_dmg.sh first" >&2; exit 1; }

sign_update="build/macos/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$sign_update" ] || { echo "make_appcast: $sign_update missing — build the app first" >&2; exit 1; }

# Prints `sparkle:edSignature="…" length="…"`, the enclosure's attributes.
signature="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$dmg")"

# Sparkle compares sparkle:version against CFBundleVersion — the pubspec
# build number — so every release must raise it.
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Aperture</title>
    <link>$repo</link>
    <item>
      <title>Aperture $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$min_macos</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$repo/releases/tag/v$version</sparkle:releaseNotesLink>
      <enclosure url="$repo/releases/download/v$version/Aperture.dmg" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
XML

echo "==> dist/appcast.xml (Aperture $version, build $build)"
