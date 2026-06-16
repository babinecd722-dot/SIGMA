#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=env.sh
source "$ROOT/scripts/env.sh"

GAMEMODE="${1:-crimson}"
SRC="$PAWN_GAMEMODES/${GAMEMODE}.pwn"
OUT="$PAWN_GAMEMODES/${GAMEMODE}"

if [[ ! -f "$SRC" ]]; then
  echo "Gamemode not found: $SRC" >&2
  exit 1
fi

if ! command -v "$PAWNCC" >/dev/null 2>&1; then
  echo "Compiler not in PATH: $PAWNCC (set PAWNCC to your pawncc binary)" >&2
  exit 1
fi

exec "$PAWNCC" \
  -r -d3 \
  -i"$PAWN_INCLUDE" \
  -o"$OUT" \
  "$SRC"
