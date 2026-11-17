#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/shunt-hooks-check.XXXXXXXX")
work=$(cd "$work" && pwd -P)
trap 'rm -rf -- "$work"' EXIT
unset SHUNT_ACTIVE
export SHUNT_MIN_LINES=2
printf 'one\ntwo\nthree' > "$work/large & file"
printf 'one\n' > "$work/small"
checks=0
pass() { checks=$((checks + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check_hook() { printf '%s\n' "$payload" | "$root/scripts/check-large-read.sh" "$1" > "$work/out"; }
check_auto_hook() {
  rm -f "$work/auto-record/calls" "$work/auto-record/prompt-bulk" "$work/auto-record/prompt-scout"
  hook_args=("$1" --auto-scout --backend command)
  [[ ${AUTO_FALLBACK:-1} == 1 ]] || hook_args+=(--no-scout-fallback)
  printf '%s\n' "$payload" | RECORD="$work/auto-record" \
    BULK_ANSWER="${AUTO_BULK_ANSWER:-$'SHUNT_COVERAGE: complete\nScout found the setting at config/app.toml:12.'}" \
    SCOUT_ANSWER="${AUTO_SCOUT_ANSWER:-$'SHUNT_COVERAGE: complete\nScout found the setting at config/app.toml:12.'}" \
    SHUNT_COMMAND="$root/tests/stub-auto-worker" "$root/scripts/check-large-read.sh" "${hook_args[@]}" > "$work/out"
}
blocked() {
  jq -e '(.hookSpecificOutput.permissionDecision // .permissionDecision) == "deny"' "$work/out" > /dev/null || fail "expected deny: $payload"
}
allowed() { [[ ! -s $work/out ]] || fail "unexpected deny: $payload"; }

payload=$(jq -n --arg cwd "$work" '{tool_name:"Bash", cwd:$cwd, tool_input:{command:"cat \"large & file\""}}')
check_hook codex; blocked
pass

mkdir -p "$work/auto-record"
printf '%s\n' \
  '{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"DO_NOT_SEND developer text."}]}}' \
  '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Find how document IDs are selected."}]}}' \
  '{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"analysis","content":[{"type":"reasoning","text":"DO_NOT_SEND hidden reasoning."}]}}' \
  '{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"I am tracing the document selection path."}]}}' > "$work/transcript.jsonl"
payload=$(jq -n --arg cwd "$work" --arg transcript "$work/transcript.jsonl" '{tool_name:"Bash",cwd:$cwd,transcript_path:$transcript,tool_input:{command:"cat \"large & file\""}}')
check_auto_hook codex
jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("Scout found the setting at config/app.toml:12."))' "$work/out" > /dev/null || fail 'automatic one-shot result was not returned with the read denial'
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("only if the checklist omits a required fact")' "$work/out" > /dev/null || fail 'automatic result did not tell the parent when to reread'
grep -q 'Find how document IDs are selected.' "$work/auto-record/prompt-bulk" || fail 'automatic reader did not receive the user task context'
grep -q 'I am tracing the document selection path.' "$work/auto-record/prompt-bulk" || fail 'automatic reader did not receive visible assistant context'
if grep -q 'DO_NOT_SEND' "$work/auto-record/prompt-bulk"; then fail 'automatic reader received hidden context'; fi
grep -q 'large &amp; file' "$work/auto-record/prompt-bulk" || fail 'automatic reader did not receive the blocked path'
grep -Fq $'1\tone' "$work/auto-record/prompt-bulk" || fail 'automatic reader did not receive numbered file content'
[[ $(cat "$work/auto-record/calls") == bulk ]] || fail 'complete one-shot result started Scout unnecessarily'
pass

AUTO_BULK_ANSWER=$'SHUNT_COVERAGE: incomplete\n[missing] Search mode default at routes.py:12.' \
AUTO_SCOUT_ANSWER=$'SHUNT_COVERAGE: complete\n[covered] Search mode defaults to hybrid at config.py:8.' \
  check_auto_hook codex
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("Scout checked the missing evidence") and contains("config.py:8")' "$work/out" > /dev/null || fail 'Scout fallback did not complete missing evidence'
grep -q 'Prior one-shot findings' "$work/auto-record/prompt-scout" || fail 'Scout fallback did not receive the coverage gap'
[[ $(cat "$work/auto-record/calls") == $'bulk\nscout' ]] || fail 'incomplete one-shot result did not start exactly one Scout'
pass

AUTO_BULK_ANSWER=$'SHUNT_COVERAGE: complete\n[missing] Test coverage not checked.' \
AUTO_SCOUT_ANSWER=$'SHUNT_COVERAGE: complete\n[covered] Test coverage is in tests/routes.test.ts:18.' \
  check_auto_hook codex
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("Scout checked the missing evidence") and contains("tests/routes.test.ts:18")' "$work/out" > /dev/null || fail 'one-shot result with a gap label was accepted as complete'
[[ $(cat "$work/auto-record/calls") == $'bulk\nscout' ]] || fail 'gap label did not start exactly one Scout'
pass

AUTO_FALLBACK=0 AUTO_BULK_ANSWER=$'SHUNT_COVERAGE: incomplete\n[missing] Architecture decision source.' \
  check_auto_hook codex
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("Treat its findings as partial") and contains("[missing] Architecture decision source.")' "$work/out" > /dev/null || fail 'one-shot mode did not return partial findings'
[[ $(cat "$work/auto-record/calls") == bulk ]] || fail 'one-shot mode started Scout'
pass

AUTO_BULK_ANSWER=unstructured AUTO_SCOUT_ANSWER=$'SHUNT_COVERAGE: incomplete\n[missing] No source found.' \
  check_auto_hook codex
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("could not confirm complete evidence coverage") and (contains("SHUNT_COVERAGE: complete") | not)' "$work/out" > /dev/null || fail 'hook accepted incomplete fallback evidence'
[[ $(cat "$work/auto-record/calls") == $'bulk\nscout' ]] || fail 'hook made more than one fallback call'
pass

printf '%s\n' \
  '{"type":"user","message":{"role":"user","content":"Trace the handler for this request."}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I am following the handler into the service."}]}}' > "$work/transcript.jsonl"
payload=$(jq -n --arg cwd "$work" --arg transcript "$work/transcript.jsonl" '{tool_name:"Bash",cwd:$cwd,transcript_path:$transcript,tool_input:{command:"cat \"large & file\""}}')
check_auto_hook claude
grep -q 'Trace the handler for this request.' "$work/auto-record/prompt-bulk" || fail 'Claude transcript user task was not passed to the reader'
grep -q 'I am following the handler into the service.' "$work/auto-record/prompt-bulk" || fail 'Claude transcript assistant context was not passed to the reader'
pass

# An offset alone or a large explicit range must not bypass routing.
payload=$(jq -n --arg cwd "$work" '{tool_name:"Read",cwd:$cwd,tool_input:{path:"large & file",offset:1}}')
check_hook codex; blocked
payload=$(jq '.tool_input.limit = 10000' <<< "$payload")
check_hook codex; blocked
payload=$(jq '.tool_input.limit = 2' <<< "$payload")
check_hook codex; allowed
printf 'one\ntwo\n' > "$work/second"
payload=$(jq -n --arg cwd "$work" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"cat small second"}}')
check_hook codex; blocked
payload=$(jq -n --arg cwd "$work" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"sed -n '\''1,10000p'\'' '\''large & file'\''"}}')
check_hook codex; blocked
payload=$(jq -n --arg cwd "$work" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"head -n 10000 '\''large & file'\''"}}')
check_hook codex; blocked
payload=$(jq -n --arg cwd "$work" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"nl -ba \"large & file\""}}')
check_hook codex; blocked
payload=$(jq '.agent_type = "scout"' <<< "$payload")
check_hook codex; allowed
pass

payload=$(jq -n --arg cwd "$work" '{tool_name:"exec_command", cwd:"/", tool_input:{cmd:"/bin/cat small \"large & file\"",workdir:$cwd}}')
check_hook codex; blocked
pass

payload=$(jq -n --arg cwd "$work" '{toolName:"view",cwd:$cwd,toolArgs:{path:"large & file"}}')
check_hook copilot; blocked
jq -e '.permissionDecision == "deny" and (.hookSpecificOutput == null)' "$work/out" > /dev/null || fail 'Copilot output shape'
payload=$(jq '.toolArgs |= tojson' <<< "$payload")
check_hook copilot; blocked
pass

payload=$(jq -n --arg cwd "$work" '{tool_name:"Read",cwd:$cwd,tool_input:{path:"large & file",view_range:[1,-1]}}')
check_hook copilot; blocked
payload=$(jq '.tool_input.view_range = [1,2]' <<< "$payload")
check_hook copilot; allowed
pass

for command in 'head -n 2 "large & file"' 'tail -2 "large & file"' 'cat "large & file" | grep one' 'cat "large & file" > output' 'git status' 'cat small'; do
  payload=$(jq -n --arg cwd "$work" --arg command "$command" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$command}}')
  check_hook codex; allowed
done
payload=$(jq -n --arg cwd "$work" '{toolName:"bash",cwd:$cwd,toolArgs:{command:"cat \"large & file\""}}')
check_hook copilot; blocked
SHUNT_ACTIVE=1 check_hook copilot; allowed
pass

for harness in claude codex copilot; do
  project="$work/project $harness"
  case $harness in
    claude) file=$project/.claude/settings.json; event=PreToolUse ;;
    codex) file=$project/.codex/hooks.json; event=PreToolUse ;;
    copilot) file=$project/.github/hooks/shunt.json; event=preToolUse ;;
  esac
  mkdir -p "$(dirname "$file")"
  if [[ $harness == copilot ]]; then
    original='{"type":"command","bash":"printf policy"}'
  else
    original='{"matcher":"^never$","hooks":[{"type":"command","command":"printf policy"}]}'
  fi
  jq -n --arg event "$event" --argjson original "$original" '{keep:42,hooks:{($event):[$original]}}' > "$file"
  "$root/scripts/install-hooks" "$harness" --project "$project" > /dev/null
  "$root/scripts/install-hooks" "$harness" --project "$project" > /dev/null
  jq -e --arg event "$event" --argjson original "$original" '.keep == 42 and (.hooks[$event] | length) == 2 and .hooks[$event][0] == $original' "$file" > /dev/null || fail 'hooks/settings not preserved or duplicated'
  if [[ $harness == copilot ]]; then
    command=$(jq -r '.hooks.preToolUse[-1].bash' "$file")
    payload=$(jq -n --arg cwd "$work" '{toolName:"view",cwd:$cwd,toolArgs:{path:"large & file"}}')
  else
    command=$(jq -r '.hooks.PreToolUse[-1].hooks[0].command' "$file")
    payload=$(jq -n --arg cwd "$work" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:"cat \"large & file\""}}')
  fi
  printf '%s\n' "$payload" | bash -c "$command" > "$work/out"
  blocked
done
pass

# Adding a status message must update the previous entry, not run it twice.
file=$work/project\ claude/.claude/settings.json
jq 'del(.hooks.PreToolUse[-1].hooks[0].statusMessage)' "$file" > "$work/old-hook"
mv "$work/old-hook" "$file"
"$root/scripts/install-hooks" claude --project "$work/project claude" > /dev/null
jq -e '(.hooks.PreToolUse | length) == 2 and .hooks.PreToolUse[-1].hooks[0].statusMessage != null' "$file" > /dev/null || fail 'old Shunt hook duplicated'
pass

file=$work/project\ codex/.codex/hooks.json
printf 'invalid json\n' > "$file"
if "$root/scripts/install-hooks" codex --project "$work/project codex" > /dev/null 2>&1; then fail 'invalid config replaced'; fi
[[ $(cat "$file") == 'invalid json' ]] || fail 'invalid config changed'
pass

payload=$(jq -n --arg cwd "$work" --arg marker "$work/should-not-exist" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:("cat $(touch " + $marker + ")")}}')
check_hook codex; allowed
[[ ! -e $work/should-not-exist ]] || fail 'hook evaluated command substitution'
pass

# Reject empty streams and multiple documents; preserve the original config.
for content in '' '{} {}'; do
  printf '%s' "$content" > "$file"
  if "$root/scripts/install-hooks" codex --project "$work/project codex" > /dev/null 2>&1; then fail 'invalid JSON stream accepted'; fi
  [[ $(cat "$file") == "$content" ]] || fail 'invalid JSON stream replaced'
done
pass

# Failed hook installation must not prevent a later retry of skill installation.
project="$work/rollback project"
mkdir -p "$project/.claude" "$project/.claude/skills/existing"
printf 'keep\n' > "$project/.claude/skills/existing/marker"
printf 'invalid json\n' > "$project/.claude/settings.json"
if "$root/scripts/install-skills" claude --project "$project" --backend command > /dev/null 2>&1; then fail 'skill install accepted bad hook config'; fi
[[ ! -e $project/.claude/skills/bulk-reader && ! -e $project/.claude/skills/code-writer ]] || fail 'partial skill installation remains'
[[ $(cat "$project/.claude/skills/existing/marker") == keep ]] || fail 'rollback changed an existing skill'
[[ $(cat "$project/.claude/settings.json") == 'invalid json' ]] || fail 'rollback changed existing hook config'
printf '{}\n' > "$project/.claude/settings.json"
"$root/scripts/install-skills" claude --project "$project" --backend command > /dev/null
[[ -f $project/.claude/skills/bulk-reader/SKILL.md && -f $project/.claude/skills/code-writer/SKILL.md ]] || fail 'retry did not install skills'
pass
printf '%s hook checks passed\n' "$checks"
