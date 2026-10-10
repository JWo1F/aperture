#!/usr/bin/env bash
# Builds the release Linux bundle for this machine's architecture and packs
# it as dist/Aperture-<version>-linux-<arch>.tar.gz, which unpacks to
# aperture/. Flutter cannot cross-compile a Linux desktop app, so each
# architecture has to be built on its own.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version="$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml)"
[ -n "$version" ] || { echo "make_linux_tarball: no version: line in pubspec.yaml" >&2; exit 1; }

# Flutter names its output directory after its own spelling of the arch.
case "$(uname -m)" in
  aarch64 | arm64) arch=arm64 flutter_arch=arm64 ;;
  x86_64) arch=amd64 flutter_arch=x64 ;;
  *) echo "make_linux_tarball: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

echo "==> flutter build linux --release"
flutter build linux --release

mkdir -p dist
tarball="dist/Aperture-$version-linux-$arch.tar.gz"
tar -C "build/linux/$flutter_arch/release" --transform 's,^bundle,aperture,' \
  -czf "$tarball" bundle
echo "==> $tarball"
