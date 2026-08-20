#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${SECRET_BIN_DIR:-$HOME/.local/bin}"

mkdir -p "$BIN_DIR"
ln -sf "$SCRIPT_DIR/bin/secret" "$BIN_DIR/secret"
printf 'Linked secret -> %s/secret\n' "$BIN_DIR"

if command -v zsh >/dev/null 2>&1; then
  COMP_DIR="${ZSH_COMPLETION_DIR:-$HOME/.zfunc}"
  mkdir -p "$COMP_DIR"
  ln -sf "$SCRIPT_DIR/completions/_secret" "$COMP_DIR/_secret"
  printf 'Linked zsh completion -> %s/_secret\n' "$COMP_DIR"
fi

BASH_COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
mkdir -p "$BASH_COMP_DIR"
ln -sf "$SCRIPT_DIR/completions/secret.bash" "$BASH_COMP_DIR/secret"
printf 'Linked bash completion -> %s/secret\n' "$BASH_COMP_DIR"

printf '\nEnsure %s is on PATH. For zsh completion, add this before compinit:\n' "$BIN_DIR"
# The second argument is intentionally the literal zsh variable.
# shellcheck disable=SC2016
printf '  fpath=(%q %s)\n' "${ZSH_COMPLETION_DIR:-$HOME/.zfunc}" '$fpath'
