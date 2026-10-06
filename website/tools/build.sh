#!/usr/bin/env bash
# Build the Aperture website into website/dist.
#
#   ./tools/build.sh           compile the CSS, then render pages and screens
#   ./tools/build.sh serve     …and serve dist on http://localhost:8080
#
# Set BASE for a subpath deploy — a GitHub project page lives at /<repo>/,
# so CI builds with BASE=/aperture.
#
# The CSS is compiled first because the generator copies assets/ verbatim:
# rendering against a stale stylesheet publishes the wrong one, silently.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
MODE="${1:-build}"
BASE="${BASE:-}"

./tools/get-tailwind.sh >/dev/null

echo "==> Compiling CSS"
./tools/tailwindcss -i ui/app.css -o assets/site.css --minify
echo "    $(wc -c < assets/site.css | tr -d ' ') bytes"

echo "==> Rendering pages and screens"
cargo run --release --quiet -- --base "${BASE}"

if [ "${MODE}" = "serve" ]; then
  echo "==> http://localhost:8080${BASE}/"
  python3 -m http.server 8080 --directory dist
fi
