#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/cc-shunt-install-test.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin"
for name in claude codex copilot pi opencode; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/$name"
  chmod +x "$work/bin/$name"
done
export PATH="$work/bin:$PATH"
for harness in claude codex copilot pi opencode; do
  project=$work/$harness
  mkdir "$project"
  "$root/scripts/install" "$harness" --project "$project" --model test-model >/dev/null
  "$root/scripts/install" "$harness" --project "$project" --model test-model >/dev/null
  case $harness in codex) skill=.agents ;; claude) skill=.claude ;; copilot) skill=.github ;; pi) skill=.pi ;; opencode) skill=.opencode ;; esac
  rm "$project/$skill/skills/scout/SKILL.md"
  "$root/scripts/install" "$harness" --project "$project" --model test-model >/dev/null
  [[ -f $project/$skill/skills/scout/SKILL.md ]]
  printf 'user content\n' > "$project/$skill/skills/scout/SKILL.md"
  if "$root/scripts/install" "$harness" --project "$project" --model test-model >/dev/null 2>&1; then
    printf 'Installer accepted a modified file for %s\n' "$harness" >&2; exit 1
  fi
  [[ $(cat "$project/$skill/skills/scout/SKILL.md") == 'user content' ]]
done
printf 'Install: five harnesses, rerun, repair, and conflicts passed.\n'
