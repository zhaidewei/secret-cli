#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash -n "$ROOT/bin/secret" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/tests/"*.sh
shellcheck "$ROOT/bin/secret" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/tests/"*.sh
grep -qF "\$Version = '0.2.0'" "$ROOT/bin/secret.ps1"
grep -q 'CredWriteW' "$ROOT/bin/secret.ps1"
grep -q 'CredEnumerateW' "$ROOT/bin/secret.ps1"
grep -q 'maximum: 2560 bytes' "$ROOT/bin/secret.ps1"

echo 'static checks passed'
