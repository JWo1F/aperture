#!/usr/bin/env bash
# Fetch the pinned standalone Tailwind CLI into tools/.
#
# Tailwind v4 ships a self-contained binary, so the site needs no Node toolchain.
# The binary is gitignored — it is ~80MB and reproducible from this script, so
# pinning the version here is what keeps builds deterministic.
set -euo pipefail

TAILWIND_VERSION="v4.3.2"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${DIR}/tailwindcss"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  ASSET="tailwindcss-macos-arm64" ;;
  Darwin-x86_64) ASSET="tailwindcss-macos-x64" ;;
  Linux-aarch64) ASSET="tailwindcss-linux-arm64" ;;
  Linux-x86_64)  ASSET="tailwindcss-linux-x64" ;;
  *) echo "No Tailwind standalone build for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

if [ -x "${BIN}" ] && "${BIN}" --help 2>&1 | grep -q "${TAILWIND_VERSION#v}"; then
  echo "tailwindcss ${TAILWIND_VERSION} already present"
  exit 0
fi

URL="https://github.com/tailwindlabs/tailwindcss/releases/download/${TAILWIND_VERSION}/${ASSET}"
echo "Fetching ${ASSET} ${TAILWIND_VERSION}"
curl -fsSL "${URL}" -o "${BIN}.tmp"
chmod +x "${BIN}.tmp"
mv "${BIN}.tmp" "${BIN}"
"${BIN}" --help 2>&1 | head -1
