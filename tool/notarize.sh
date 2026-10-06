#!/usr/bin/env bash
# Submits a file to Apple's notary service, waits for the verdict, and
# staples the ticket onto it so Gatekeeper can check it offline.
#
#   tool/notarize.sh path/to/Aperture.app|.dmg
#
# Credentials, one of:
#   NOTARY_PROFILE      a profile saved with `xcrun notarytool store-credentials`
#                       (the convenient local setup)
#   APPLE_API_KEY_PATH, APPLE_API_KEY_ID, APPLE_API_ISSUER
#                       an App Store Connect API key (what CI uses)
set -euo pipefail

target="${1:?usage: tool/notarize.sh path/to/Aperture.app|.dmg}"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  auth=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then
  auth=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
else
  echo "notarize: set NOTARY_PROFILE, or APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER" >&2
  exit 1
fi

# The notary service takes a zip, a pkg or a dmg — not a bare .app.
submission="$target"
if [ -d "$target" ]; then
  submission="$(mktemp -d)/$(basename "$target").zip"
  ditto -c -k --keepParent "$target" "$submission"
fi

echo "==> notarizing $(basename "$target")"
result="$(xcrun notarytool submit "$submission" "${auth[@]}" --wait --timeout 30m --output-format json || true)"
status="$(printf '%s' "$result" | sed -n 's/.*"status" *: *"\([^"]*\)".*/\1/p')"
id="$(printf '%s' "$result" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p')"

if [ "$status" != "Accepted" ]; then
  echo "notarize: $(basename "$target") was not accepted (status: ${status:-unknown})" >&2
  [ -n "$id" ] && xcrun notarytool log "$id" "${auth[@]}" >&2
  exit 1
fi

xcrun stapler staple "$target"
echo "==> notarized and stapled $(basename "$target")"
