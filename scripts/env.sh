# Source from repo root: source scripts/env.sh
_strip_cr() {
  printf '%s' "$1" | tr -d '\r'
}

_pawn_root_default() {
  _strip_cr "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

export PAWN_ROOT="$(_strip_cr "${PAWN_ROOT:-$(_pawn_root_default)}")"
export PAWN_INCLUDE="$(_strip_cr "${PAWN_INCLUDE:-$PAWN_ROOT/include}")"
export PAWN_GAMEMODES="$(_strip_cr "${PAWN_GAMEMODES:-$PAWN_ROOT/gamemodes}")"
export PAWNCC="$(_strip_cr "${PAWNCC:-pawncc}")"
