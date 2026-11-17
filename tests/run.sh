#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/shunt-check.XXXXXXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin" "$work/record"
ln -s "$root/tests/stub-worker" "$work/bin/claude"
ln -s "$root/tests/stub-worker" "$work/bin/codex"
export PATH="$work/bin:$PATH" RECORD="$work/record"
unset SHUNT_ACTIVE SHUNT_MODEL SHUNT_COMMAND SHUNT_BACKEND SHUNT_MAX_PAYLOAD_BYTES SHUNT_TIMEOUT_SECONDS
export SHUNT_BACKEND=command
printf -v SHUNT_COMMAND '%q' "$root/tests/stub-worker"
export SHUNT_COMMAND
source_file="$work/a & \"quoted\" file"
printf 'answer = 42\n' > "$source_file"
out=$work/out err=$work/err
checks=0
pass() { checks=$((checks + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$err" >&2; exit 1; }
read_files() { "$root/scripts/bulk-read" --question 'what value?' --paths "$source_file" > "$out" 2> "$err"; }
write_code() { "$root/scripts/code-write" --spec 'write a constant' --reference "$source_file" "$@" > "$out" 2> "$err"; }

read_files || fail reader
[[ $(cat "$out") == 'short answer' ]] || fail 'reader output'
grep -q 'answer = 42' "$RECORD/prompt" && grep -q '&amp;.*&quot;' "$RECORD/prompt" || fail 'file boundaries'
grep -q $'^1\tanswer = 42$' "$RECORD/prompt" || fail 'CLI reader source line numbers'
[[ $(cat "$RECORD/cwd") != "$work" && $(cat "$RECORD/active") == 1 ]] || fail 'worker isolation'
pass

ANSWER=$'```python\nvalue = 42\n```' write_code --target "$work/result" || fail writer
[[ ! -s $out && $(cat "$work/result") == 'value = 42' ]] || fail 'writer output'
grep -qx 'answer = 42' "$RECORD/prompt" || fail 'writer reference text changed'
pass

code=$'text = """\n```example\nhello\n```\n"""'
ANSWER=$code write_code || fail fences
[[ $(cat "$out") == "$code" ]] || fail 'internal fences removed'
pass

if write_code --target "$work/result"; then fail 'existing target accepted'; fi
[[ $(cat "$work/result") == 'value = 42' ]] || fail 'existing target changed'
ANSWER=replacement write_code --target "$work/result" --overwrite || fail overwrite
[[ $(cat "$work/result") == replacement ]] || fail 'target not replaced'
pass

if FAIL=1 write_code --target "$work/result" --overwrite; then fail 'failed worker accepted'; fi
[[ $(cat "$work/result") == replacement ]] || fail 'failed worker replaced target'
pass

if "$root/scripts/code-write" --spec test > "$out" 2> "$err"; then fail 'missing reference accepted'; fi
if "$root/scripts/bulk-read" --question test --paths "$work/missing" > "$out" 2> "$err"; then fail 'missing path accepted'; fi
pass

if SHUNT_MAX_PAYLOAD_BYTES=4 read_files; then fail 'size limit ignored'; fi
if SHUNT_ACTIVE=1 read_files; then fail 'nested call accepted'; fi
if ANSWER='' read_files; then fail 'empty output accepted'; fi
if ANSWER=$'```\n\n```' write_code; then fail 'empty code accepted'; fi
printf '\000' > "$work/binary"
if "$root/scripts/bulk-read" --question test --paths "$work/binary" > "$out" 2> "$err"; then fail 'binary accepted'; fi
printf '\377' > "$work/invalid-utf8"
if "$root/scripts/bulk-read" --question test --paths "$work/invalid-utf8" > "$out" 2> "$err"; then fail 'invalid UTF-8 accepted'; fi
pass

SHUNT_BACKEND=claude read_files || fail 'Claude backend'
[[ $(cat "$out") == 'short answer' ]] && grep -qx haiku "$RECORD/args" || fail 'Claude response'
if JSON_ERROR=1 SHUNT_BACKEND=claude read_files; then fail 'Claude error accepted'; fi
pass

if SHUNT_BACKEND=codex read_files; then fail 'Codex accepted missing model'; fi
SHUNT_BACKEND=codex SHUNT_MODEL=configured-worker read_files || fail 'Codex backend'
[[ $(cat "$out") == 'short answer' ]] && grep -qx read-only "$RECORD/args" || fail 'Codex final answer'
grep -qx 'mcp_servers.shunt_reader={command="false",enabled=false}' "$RECORD/args" || fail 'Codex worker can reconnect to Shunt MCP'
pass

if WAIT=1 SHUNT_TIMEOUT_SECONDS=1 read_files; then fail 'timeout ignored'; fi
grep -q 'time limit' "$err" || fail 'timeout message'
child=$(cat "$RECORD/child")
sleep 0.1
if kill -0 "$child" 2>/dev/null; then fail 'timeout left a worker child'; fi
pass

hook_input=$(jq -n --arg file "$source_file" '{tool_input: {file_path: $file}}')
printf '%s\n' "$hook_input" | SHUNT_MIN_LINES=0 "$root/scripts/check-large-read.sh" > "$out"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$out" >/dev/null || fail hook
printf '%s\n' "$hook_input" | jq '.tool_input.offset = 0 | .tool_input.limit = 1' | SHUNT_MIN_LINES=0 "$root/scripts/check-large-read.sh" > "$out"
[[ ! -s $out ]] || fail 'targeted read blocked'
pass

for harness in claude codex copilot pi opencode; do
  case $harness in claude) location=.claude ;; codex) location=.agents ;; copilot) location=.github ;; pi) location=.pi ;; opencode) location=.opencode ;; esac
  project="$work/project $harness"
  "$root/scripts/install-skills" "$harness" --project "$project" --backend command > "$out" 2> "$err" || fail "install $harness"
  case $harness in
    claude) [[ -f $project/.claude/settings.json ]] || fail 'Claude hook not installed' ;;
    codex) [[ -f $project/.codex/hooks.json ]] || fail 'Codex hook not installed' ;;
    copilot) [[ -f $project/.github/hooks/shunt.json ]] || fail 'Copilot hook not installed' ;;
  esac
  for name in bulk-reader code-writer; do
    skill=$project/$location/skills/$name
    [[ -f $skill/SKILL.md && ! -L $skill/SKILL.md && -L $skill/scripts/lib ]] || fail "skill entry and shared library $harness"
    if [[ $name == bulk-reader ]]; then
      "$skill/scripts/bulk-read" --question value --paths "$source_file" > "$out" 2> "$err" || fail "installed reader $harness"
    else
      "$skill/scripts/code-write" --spec value --reference "$source_file" > "$out" 2> "$err" || fail "installed writer $harness"
    fi
  done
  if "$root/scripts/install-skills" "$harness" --project "$project" --backend command > "$out" 2> "$err"; then fail 'installer replaced existing skills'; fi
done
pass

# Quotes, spaces, and shell syntax must remain literal command arguments.
quoted_worker="$work/worker with space"
ln -s "$root/tests/stub-worker" "$quoted_worker"
printf -v custom '%q %q %q' "$quoted_worker" 'literal $(touch forbidden)' 'two words'
SHUNT_COMMAND=$custom read_files || fail 'quoted command'
grep -qxF 'literal $(touch forbidden)' "$RECORD/args" && grep -qxF 'two words' "$RECORD/args" || fail 'command argument parsing'
printf -v custom '\047%s\047 "two words" ""' "$quoted_worker"
SHUNT_COMMAND=$custom read_files || fail 'single and double quotes'
grep -qxF 'two words' "$RECORD/args" || fail 'double quote parsing'
if SHUNT_COMMAND="'unclosed" read_files; then fail 'unclosed command quote accepted'; fi
pass

ln -s "$work/result" "$work/link"
if write_code --target "$work/link" --overwrite; then fail 'symlink target accepted'; fi
[[ $(cat "$work/result") == replacement ]] || fail 'symlink changed referent'
pass

# Missing values must fail before a worker can incur a charge.
rm -f "$RECORD/prompt"
if "$root/scripts/bulk-read" --question --model --paths "$source_file" > "$out" 2> "$err"; then fail 'option used as question'; fi
if "$root/scripts/code-write" --spec --model --reference "$source_file" > "$out" 2> "$err"; then fail 'option used as spec'; fi
[[ ! -e $RECORD/prompt ]] || fail 'worker invoked with missing value'
pass

# A read can fail after validation. Do not send an incomplete corpus to a worker.
cat > "$work/bin/cat" <<'SHIM'
#!/usr/bin/env bash
if [[ ${1:-} == -- && ${2:-} == "$READ_FAIL_PATH" ]]; then exit 1; fi
exec /bin/cat "$@"
SHIM
chmod +x "$work/bin/cat"
if READ_FAIL_PATH=$source_file read_files; then fail 'source read failure ignored'; fi
[[ ! -e $RECORD/prompt ]] || fail 'worker received incomplete files'
if READ_FAIL_PATH=$source_file write_code --target "$work/result" --overwrite; then fail 'reference read failure ignored'; fi
[[ $(/bin/cat "$work/result") == replacement ]] || fail 'reference failure replaced target'
rm "$work/bin/cat"
pass
printf '%s checks passed\n' "$checks"
