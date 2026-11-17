#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/shunt-scout-check.XXXXXXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/project/source" "$work/record" "$work/bin"
export RECORD=$work/record
unset SHUNT_ACTIVE
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
printf 'secret source value\n' > "$work/project/source/input"
ln -s "$work" "$work/project/escape"
ln -s "$root/tests/stub-worker" "$work/bin/codex"
PATH="$work/bin:$PATH" "$root/scripts/scout" --backend codex --model worker --root "$work/project" --task 'Find the value' --paths source > "$work/out"
[[ $(cat "$work/out") == 'short answer' ]] || fail 'missing final answer'
[[ $(cat "$RECORD/cwd") == "$work/project" ]] || fail 'worker has no project context'
grep -qx features.shell_tool=true "$RECORD/args" || fail 'worker cannot discover source'
grep -qx read-only "$RECORD/args" || fail 'worker sandbox changed'
grep -q 'Find the value' "$RECORD/prompt" || fail 'missing task'
if grep -q 'secret source value' "$RECORD/prompt"; then fail 'parent loaded source'; fi
ln -s "$root/tests/stub-worker" "$work/bin/claude"
PATH="$work/bin:$PATH" "$root/scripts/scout" --backend claude --root "$work/project" --task 'Find the value' --paths source > "$work/out"
[[ $(cat "$work/out") == 'short answer' ]] || fail 'Claude final answer'
grep -qx 'Read,Grep,Glob' "$RECORD/args" || fail 'Claude discovery tools'
grep -qx -- '--max-turns' "$RECORD/args" || fail 'Claude turn limit'
for path in escape ../record; do
  if "$root/scripts/scout" --backend command --root "$work/project" --task Read --paths "$path" >/dev/null 2>&1; then fail 'scope escape accepted'; fi
done
"$root/scripts/install-skills" codex --project "$work/project" --backend command --no-hooks >/dev/null
export SHUNT_COMMAND="$root/tests/stub-worker"
(cd "$work/project/source"; "$work/project/.agents/skills/scout/scripts/scout" --task 'Find the value' --paths source) > "$work/out"
[[ $(cat "$work/out") == 'short answer' ]] || fail 'installed Scout cannot load shared prompt'
[[ $(cat "$RECORD/cwd") == "$work/project" ]] || fail 'installed Scout lost the project root'
if FAIL=1 "$work/project/.agents/skills/scout/scripts/scout" --root "$work/project" --task Read --paths source >/dev/null 2>&1; then fail 'worker failure accepted'; fi
printf '%s\n' 'Scout task, discovery, scope, installation, and failure checks: passed'
