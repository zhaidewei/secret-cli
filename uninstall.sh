#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${SECRET_BIN_DIR:-$HOME/.local/bin}"
ZSH_COMP_DIR="${ZSH_COMPLETION_DIR:-$HOME/.zfunc}"
BASH_COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"

remove_link() {
  local path=$1 expected=$2
  if [[ -L "$path" ]]; then
    if [[ "$(readlink "$path")" == "$expected" ]]; then
      rm "$path"
      printf 'Removed %s\n' "$path"
    else
      printf 'Skipped unrelated symlink: %s\n' "$path"
    fi
  fi
}

remove_link "$BIN_DIR/secret" "$SCRIPT_DIR/bin/secret"
remove_link "$ZSH_COMP_DIR/_secret" "$SCRIPT_DIR/completions/_secret"
remove_link "$BASH_COMP_DIR/secret" "$SCRIPT_DIR/completions/secret.bash"

echo 'Stored secrets were not removed.'
