#!/usr/bin/env bash
# Builds release Linux bundles in Docker and writes one
# aperture-<version>-linux-<arch>.tar.gz per architecture to OUT_DIR.
#
#   tool/build_linux.sh [OUT_DIR] [ARCH...]
#
# OUT_DIR defaults to build/linux-dist, ARCH to both arm64 and amd64.
#
# The amd64 build runs under emulation on an Apple-silicon host.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mkdir -p "${1:-$root/build/linux-dist}" && cd "${1:-$root/build/linux-dist}" && pwd)"
flutter_version="$(flutter --version --machine | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')"
shift || true
archs=(arm64 amd64)
[ $# -gt 0 ] && archs=("$@")
version="$(sed -n 's/^version: *\([^+]*\).*/\1/p' "$root/pubspec.yaml")"

for arch in "${archs[@]}"; do
  # Flutter names the output directory after its own spelling of the arch.
  case "$arch" in
    arm64) flutter_arch=arm64 ;;
    amd64) flutter_arch=x64 ;;
  esac
  image="aperture-linux-build:$flutter_version-$arch"
  docker build --platform "linux/$arch" \
    --build-arg "FLUTTER_VERSION=$flutter_version" \
    -t "$image" "$root/tool/linux"
  # The tree is copied, not built in place: pub get inside the container
  # would rewrite .dart_tool with container paths and break the host build.
  docker run --rm --platform "linux/$arch" \
    -v "$root:/src:ro" -v "$out:/out" \
    -v "aperture-pub-cache-$arch:/root/.pub-cache" \
    "$image" bash -euo pipefail -c "
      mkdir /work
      tar -C /src --exclude=./build --exclude=./.dart_tool --exclude=./.git \
        --exclude=./macos --exclude=./website -cf - . | tar -C /work -xf -
      cd /work
      flutter build linux --release
      tar -C build/linux/$flutter_arch/release --transform 's,^bundle,aperture,' \
        -czf /out/aperture-$version-linux-$arch.tar.gz bundle
    "
done

for arch in "${archs[@]}"; do
  ls -lh "$out/aperture-$version-linux-$arch.tar.gz"
done
