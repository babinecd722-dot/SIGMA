#!/usr/bin/env bash
# Prepare Pawn/SA-MP dev environment (no servers or builds started).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAWNC_DIR="$ROOT/tools/pawnc-3.10.10-linux"
PAWNC_BIN="$PAWNC_DIR/bin/pawncc"
PAWNC_URL="https://github.com/pawn-lang/compiler/releases/download/v3.10.10/pawnc-3.10.10-linux.tar.gz"

mkdir -p "$ROOT/gamemodes" "$ROOT/include/system" "$ROOT/tools"
chmod +x "$ROOT/scripts/compile.sh" "$ROOT/scripts/env.sh" "$ROOT/scripts/setup-env.sh"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq libc6-i386 lib32gcc-s1 lib32stdc++6 curl
fi

if [[ ! -x "$PAWNC_BIN" ]]; then
  tmp="$(mktemp)"
  curl -fsSL -o "$tmp" "$PAWNC_URL"
  tar -xzf "$tmp" -C "$ROOT/tools"
  rm -f "$tmp"
  chmod +x "$PAWNC_BIN"
fi

# shellcheck source=env.sh
source "$ROOT/scripts/env.sh"
pawncc_out="$("$PAWNCC" -v 2>&1 || true)"
if ! grep -q 'Pawn compiler' <<<"$pawncc_out"; then
  echo "pawncc check failed: $PAWNCC" >&2
  exit 1
fi

echo "Environment ready: PAWN_ROOT=$PAWN_ROOT"
