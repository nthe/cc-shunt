#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/shunt-native.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
printf 'value = 42\n' > "$work/reference"
"$root/scripts/read-files" "$work/reference" > "$work/out"
TMPDIR="$work/no-such-directory" "$root/scripts/read-files" "$work/reference" > "$work/no-temp-out"
cmp "$work/out" "$work/no-temp-out" || fail 'read helper requires temporary storage'
grep -q $'^1\tvalue = 42$' "$work/out" || fail 'numbered read'
printf 'first\n\nthird\nfourth' > "$work/lines"
"$root/scripts/read-files" --lines 02:04 "$work/lines" > "$work/out"
printf '<file path="%s" line_numbers="true">\n2\t\n3\tthird\n4\tfourth\n\n</file>\n\n' "$work/lines" > "$work/expected"
cmp "$work/expected" "$work/out" || fail 'bounded source line numbers'
for range in 0:2 3:2 1:-1 1:2:3 1:1000000000; do
  if "$root/scripts/read-files" --lines "$range" "$work/lines" > "$work/out" 2>/dev/null; then fail "invalid range accepted: $range"; fi
  [[ ! -s $work/out ]] || fail 'invalid range emitted content'
done
printf '\000' > "$work/binary"
if "$root/scripts/read-files" "$work/reference" "$work/binary" > "$work/out" 2>/dev/null; then fail 'binary read accepted'; fi
[[ ! -s $work/out ]] || fail 'partial read reached worker'
if "$root/scripts/read-files" --lines 1:1 "$work/reference" "$work/binary" > "$work/out" 2>/dev/null; then fail 'bounded binary read accepted'; fi
[[ ! -s $work/out ]] || fail 'partial bounded read reached worker'
printf 'valid\n\377' > "$work/invalid-utf8"
if "$root/scripts/read-files" --lines 1:1 "$work/invalid-utf8" > "$work/out" 2>/dev/null; then fail 'bounded read skipped UTF-8 validation'; fi
[[ ! -s $work/out ]] || fail 'invalid UTF-8 emitted content'
if SHUNT_MAX_PAYLOAD_BYTES=1 "$root/scripts/read-files" "$work/reference" > "$work/out" 2>/dev/null; then fail 'read size limit'; fi
printf '```sh\nvalue=42\n```\n' | "$root/scripts/write-code" --target "$work/code" > "$work/out" 2>/dev/null
[[ ! -s $work/out && $(cat "$work/code") == value=42 ]] || fail 'safe code write'
if printf 'new\n' | "$root/scripts/write-code" --target "$work/code" > /dev/null 2>&1; then fail 'implicit overwrite'; fi
if printf '\n' | "$root/scripts/write-code" --target "$work/code" --overwrite > /dev/null 2>&1; then fail 'empty replacement'; fi
ln -s "$work/code" "$work/link"
if printf 'new\n' | "$root/scripts/write-code" --target "$work/link" --overwrite > /dev/null 2>&1; then fail 'symlink write'; fi
[[ $(cat "$work/code") == value=42 ]] || fail 'failed write changed target'
SHUNT_ACTIVE=1 "$root/scripts/read-files" "$work/reference" > /dev/null

for harness in claude codex copilot pi opencode; do
  project="$work/project $harness"
  "$root/scripts/install-skills" "$harness" --project "$project" --model configured-worker > /dev/null
  case $harness in
    claude) scope=.claude; file=$project/.claude/agents/bulk-reader.md ;;
    codex) scope=.agents; file=$project/.codex/agents/bulk-reader.toml ;;
    copilot) scope=.github; file=$project/.github/agents/bulk-reader.agent.md ;;
    pi) scope=.pi; file=$project/.pi/extensions/shunt/index.ts ;;
    opencode) scope=.opencode; file=$project/.opencode/agents/bulk-reader.md ;;
  esac
  [[ -f $file && -L $project/$scope/skills/bulk-reader/scripts ]] || fail "native install $harness"
  [[ -f $project/$scope/skills/scout/SKILL.md && -L $project/$scope/skills/scout/scripts ]] || fail "Scout skill $harness"
  if [[ $harness != pi ]]; then
    scout_file=${file/bulk-reader/scout}
    [[ -f $scout_file ]] || fail "Scout agent $harness"
    grep -q 'Require paths and task' "$scout_file" || fail 'Scout task contract'
  fi
  if [[ $harness == claude ]]; then
    hook_command=$(jq -r '.hooks.PreToolUse[-1].hooks[0].command' "$project/.claude/settings.json")
    [[ $hook_command != *'--auto-scout'* ]] || fail 'Claude hook must block and route to Scout'
  elif [[ $harness == codex ]]; then
    hook_command=$(jq -r '.hooks.PreToolUse[-1].hooks[0].command' "$project/.codex/hooks.json")
    [[ $hook_command != *'--auto-scout'* ]] || fail 'Codex hook must block and route to Scout'
  fi
  if "$root/scripts/install-skills" "$harness" --project "$project" --model changed > /dev/null 2>&1; then fail "duplicate install $harness"; fi
  [[ -f $file ]] || fail 'duplicate install removed existing agent'
done
jq -e '.model == "configured-worker" and .hooks == true' "$work/project pi/.pi/shunt.json" > /dev/null
grep -q 'modelPolicy: required' "$work/project copilot/.github/agents/bulk-reader.agent.md" || fail 'Copilot model fallback'
[[ -L $work/project\ opencode/.opencode/plugins/shunt.js ]] || fail 'OpenCode routing install'

for harness in claude codex copilot pi opencode; do
  "$root/scripts/install-native" "$harness" --project "$work/nohooks $harness" --model configured-worker --no-hooks > /dev/null
done
[[ ! -e $work/nohooks\ claude/.claude/settings.json && ! -e $work/nohooks\ opencode/.opencode/plugins/shunt.js ]] || fail 'no-hooks ignored'
jq -e '.hooks == false' "$work/nohooks pi/.pi/shunt.json" > /dev/null

project="$work/rollback"
mkdir -p "$project/.claude"
printf 'invalid\n' > "$project/.claude/settings.json"
if "$root/scripts/install-native" claude --project "$project" > /dev/null 2>&1; then fail 'bad hook config accepted'; fi
[[ ! -e $project/.claude/agents/bulk-reader.md && ! -e $project/.claude/skills/code-writer ]] || fail 'native rollback'
[[ $(cat "$project/.claude/settings.json") == invalid ]] || fail 'existing config changed'

payload=$(jq -cn --arg path "$work/reference" '{agent_type:"cc-shunt:bulk-reader",tool_name:"Read",tool_input:{file_path:$path}}')
printf '%s\n' "$payload" | SHUNT_MIN_LINES=0 "$root/scripts/check-large-read.sh" > "$work/out"
[[ ! -s $work/out ]] || fail 'native reader recursion'
payload=$(jq '.agent_type = "other-agent"' <<< "$payload")
printf '%s\n' "$payload" | SHUNT_MIN_LINES=0 "$root/scripts/check-large-read.sh" > "$work/out"
jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$work/out" > /dev/null || fail 'other worker bypass'
printf '%s\n' 'Native installation and helpers: passed'
