#!/usr/bin/env bash
# Builds the release Linux tarballs from a Mac, in Docker, and copies them
# to OUT_DIR. CI builds them on native runners with make_linux_tarball.sh
# instead; this is the same build for a machine that has no Linux at hand.
#
#   tool/build_linux.sh [OUT_DIR] [ARCH...]
#
# OUT_DIR defaults to dist, ARCH to both arm64 and amd64. The amd64 build
# runs under emulation on Apple silicon, where the Dart VM now and then
# dies with "Unexpected EINTR errno"; running it again gets past it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mkdir -p "${1:-$root/dist}" && cd "${1:-$root/dist}" && pwd)"
shift || true
archs=(arm64 amd64)
[ $# -gt 0 ] && archs=("$@")
flutter_version="$(flutter --version --machine | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')"

for arch in "${archs[@]}"; do
  image="aperture-linux-build:$flutter_version-$arch"
  docker build --platform "linux/$arch" \
    --build-arg "FLUTTER_VERSION=$flutter_version" \
    -t "$image" "$root/tool/linux"
  # The tree is copied, not built in place: pub get inside the container
  # would rewrite .dart_tool with container paths and break the host build.
  docker run --rm --platform "linux/$arch" \
    -v "$root:/src:ro" -v "$out:/out" \
    -v "aperture-pub-cache-$arch:/root/.pub-cache" \
    "$image" bash -euo pipefail -c '
      mkdir /work
      tar -C /src --exclude=./build --exclude=./.dart_tool --exclude=./.git \
        --exclude=./dist --exclude=./macos --exclude=./website -cf - . \
        | tar -C /work -xf -
      /work/tool/make_linux_tarball.sh
      cp /work/dist/*.tar.gz /out/
    '
done
