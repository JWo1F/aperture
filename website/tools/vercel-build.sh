#!/usr/bin/env bash
# Vercel's build step: make sure a current stable Rust is on PATH, then run
# the ordinary build.
#
# Rust is set up here rather than in Vercel's install step because the two
# steps do not share a shell, and the image's CARGO_HOME is not $HOME/.cargo —
# so neither sourcing ~/.cargo/env nor a PATH exported in the install step
# survives into this one. Whatever is already on the image is reused: rustup
# only updates it to stable (the crate needs edition 2024).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export PATH="$CARGO_HOME/bin:$PATH"

if command -v rustup >/dev/null 2>&1; then
  rustup toolchain install stable --profile minimal --no-self-update
  rustup default stable
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
fi

echo "==> $(rustc --version)"
exec ./tools/build.sh
