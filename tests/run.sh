#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/tests/test_static.sh"
"$ROOT/tests/test_mac.sh"
