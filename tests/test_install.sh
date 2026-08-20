#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/data"
export SECRET_BIN_DIR="$TMP/bin"
export ZSH_COMPLETION_DIR="$TMP/zfunc"
mkdir -p "$HOME" "$SECRET_BIN_DIR"

printf 'keep-me\n' >"$SECRET_BIN_DIR/secret"
if "$ROOT/install.sh" >/dev/null 2>&1; then
  echo 'expected installer to refuse an existing file' >&2
  exit 1
fi
grep -qx 'keep-me' "$SECRET_BIN_DIR/secret"

rm "$SECRET_BIN_DIR/secret"
ln -s "$TMP/unrelated" "$SECRET_BIN_DIR/secret"
"$ROOT/uninstall.sh" >/dev/null
[[ -L "$SECRET_BIN_DIR/secret" ]]
rm "$SECRET_BIN_DIR/secret"

"$ROOT/install.sh" >/dev/null
[[ -L "$SECRET_BIN_DIR/secret" ]]
[[ -L "$ZSH_COMPLETION_DIR/_secret" ]]
[[ -L "$XDG_DATA_HOME/bash-completion/completions/secret" ]]

"$ROOT/uninstall.sh" >/dev/null
[[ ! -e "$SECRET_BIN_DIR/secret" && ! -L "$SECRET_BIN_DIR/secret" ]]
[[ ! -e "$ZSH_COMPLETION_DIR/_secret" && ! -L "$ZSH_COMPLETION_DIR/_secret" ]]

echo 'install/uninstall tests passed'
