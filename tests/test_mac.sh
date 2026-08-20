#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/store"

cat >"$TMP/bin/security" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
store=${SECRET_TEST_STORE:?}
cmd=${1:?}; shift
account= service= password= comment= update=0
while (($#)); do
  case "$1" in
    -a) account=$2; shift 2 ;;
    -s) service=$2; shift 2 ;;
    -w) if [[ ${2+x} ]]; then password=$2; shift 2; else shift; fi ;;
    -j) comment=$2; shift 2 ;;
    -U) update=1; shift ;;
    *) shift ;;
  esac
done
path="$store/$service"
case "$cmd" in
  find-generic-password)
    [[ -f "$path" ]] || exit 44
    if [[ -n "$password" || " ${*:-} " == *' -w '* ]]; then :; fi
    if grep -q '^value=' "$path"; then sed -n 's/^value=//p' "$path"; fi
    ;;
  add-generic-password)
    [[ $update -eq 1 || ! -f "$path" ]] || exit 45
    if [[ -z "$comment" && -f "$path" ]]; then comment=$(sed -n 's/^comment=//p' "$path"); fi
    printf 'value=%s\ncomment=%s\n' "$password" "$comment" >"$path"
    ;;
  delete-generic-password)
    [[ -f "$path" ]] || exit 44
    rm "$path"
    ;;
  dump-keychain)
    for path in "$store"/*; do
      [[ -f "$path" ]] || continue
      service=${path##*/}
      comment=$(sed -n 's/^comment=//p' "$path")
      printf 'keychain: test\n    "acct"<blob>="agent-secrets"\n    "svce"<blob>="%s"\n    "icmt"<blob>="%s"\n' "$service" "$comment"
    done
    ;;
esac
FAKE
chmod +x "$TMP/bin/security"

export PATH="$TMP/bin:$PATH"
export SECRET_TEST_STORE="$TMP/store"

[[ "$("$ROOT/bin/secret" --version)" == 'secret 0.2.0' ]]
"$ROOT/bin/secret" --help >/dev/null
printf 'first-value\n' | "$ROOT/bin/secret" add example-token 'Example token'
[[ "$("$ROOT/bin/secret" get example-token)" == 'first-value' ]]
grep -q '^example-token' < <("$ROOT/bin/secret" list -l)
printf 'second-value\n' | "$ROOT/bin/secret" update example-token
[[ "$("$ROOT/bin/secret" get example-token)" == 'second-value' ]]
"$ROOT/bin/secret" rm example-token
if "$ROOT/bin/secret" get example-token >/dev/null 2>&1; then
  echo 'expected missing secret to fail' >&2
  exit 1
fi

echo 'macOS command tests passed'
