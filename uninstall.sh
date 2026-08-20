#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${SECRET_BIN_DIR:-$HOME/.local/bin}"
ZSH_COMP_DIR="${ZSH_COMPLETION_DIR:-$HOME/.zfunc}"
BASH_COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"

for path in "$BIN_DIR/secret" "$ZSH_COMP_DIR/_secret" "$BASH_COMP_DIR/secret"; do
  if [[ -L "$path" ]]; then
    rm "$path"
    printf 'Removed %s\n' "$path"
  fi
done

echo 'Stored secrets were not removed.'
