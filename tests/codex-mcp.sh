#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/shunt-codex-mcp.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
project="$work/project with spaces"
mkdir -p "$project/.codex"
printf '%s\n' '[model]' 'name = "keep-me"' > "$project/.codex/config.toml"
"$root/scripts/install-codex-mcp" --project "$project" --model configured-worker > /dev/null
file=$project/.codex/config.toml
grep -q 'name = "keep-me"' "$file" || fail 'existing Codex config changed'
grep -q '^\[mcp_servers\.shunt_reader\]$' "$file" || fail 'MCP section missing'
grep -q '"--backend","codex","--model","configured-worker"' "$file" || fail 'MCP model config missing'
cp "$file" "$work/before"
if "$root/scripts/install-codex-mcp" --project "$project" > /dev/null 2>&1; then fail 'duplicate MCP server accepted'; fi
cmp "$work/before" "$file" || fail 'duplicate install changed Codex config'
printf '%s\n' 'Codex MCP install: passed'
