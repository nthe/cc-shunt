#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/cc-shunt-doctor-test.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
project="$work/project with spaces"
mkdir -p "$project/.codex/agents" "$work/bin"
cat > "$work/bin/codex" <<'STUB'
#!/usr/bin/env bash
while (($#)); do
  if [[ $1 == --output-last-message ]]; then shift; printf 'Project: fixture (fixture:1)\n' > "$1"; exit 0; fi
  shift
done
exit 1
STUB
chmod +x "$work/bin/codex"
export PATH="$work/bin:$PATH"
printf 'model = "test-model"\n' > "$project/.codex/agents/scout.toml"
"$root/scripts/install-hooks" codex --project "$project" >/dev/null
printf '[mcp_servers.shunt_reader]\ncommand = "bash"\nargs = ["%s/scripts/mcp-reader"]\n' "$root" > "$project/.codex/config.toml"
"$root/scripts/doctor" codex --project "$project" > "$work/out"
grep -q 'Not verified:' "$work/out"
"$root/scripts/doctor" codex --project "$project" --live > "$work/out"
grep -q 'PASS: CLI worker returned a live response' "$work/out"
rm "$project/.codex/hooks.json"
if "$root/scripts/doctor" codex --project "$project" > "$work/out" 2>&1; then
  printf '%s\n' 'Expected missing hook failure' >&2; exit 1
fi
grep -q 'Hook configuration is missing' "$work/out"
printf '%s\n' 'Doctor: static, live worker, and missing-hook checks passed'
