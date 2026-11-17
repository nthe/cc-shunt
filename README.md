# CC Shunt

CC Shunt routes broad source reads to Scout. The parent gives Scout starting paths and the full task. Scout finds related source and returns a short answer with file and line evidence.

Scout runs with a model that the user selects in the harness. Claude Code uses Haiku by default. Codex uses `gpt-6-luna` in the project installer. Copilot, Pi, and OpenCode need a model ID that their harness supports. Each harness uses its own account.

The parent still reviews the answer, reads a short section when needed, edits code, and runs checks. `bulk-reader` and `code-writer` are optional. They are not the default flow.

## Evidence

The best repeated result used a forced broad read on one repository. Twelve paired blocks passed answer review.

| Measure | Direct | Scout and blocking hook | Change |
| --- | ---: | ---: | ---: |
| Estimated Codex credits | 67.4681 | 51.3305 | −23.9% |
| All-model tokens | 5,540,252 | 12,710,849 | +129.4% |
| Parent elapsed time | 1,614 s | 4,592 s | +184.5% |
| Correct answers | 12/12 | 12/12 | — |

Scout cost less in all 12 pairs. The median paired saving was 21.5%. Credits use a saved Codex rate card. They are not invoice amounts. This result covers one task, model pair, and repository. It does not prove savings on other work or harnesses.

## Install

Clone this repository to a stable path. Project installations link to its scripts. Keep the source folder in place. Install `jq`, `iconv`, and the CLI for your harness. Run the command for your harness from the project directory. Replace `/path/to/cc-shunt` with the clone path.

| Harness | One-command project installation |
| --- | --- |
| Codex | `/path/to/cc-shunt/scripts/install codex --project "$PWD"` |
| Claude Code | `/path/to/cc-shunt/scripts/install claude --project "$PWD"` |
| Copilot CLI | `/path/to/cc-shunt/scripts/install copilot --project "$PWD" --model MODEL` |
| Pi | `/path/to/cc-shunt/scripts/install pi --project "$PWD" --model provider/model` |
| OpenCode | `/path/to/cc-shunt/scripts/install opencode --project "$PWD" --model provider/model` |

Codex defaults to `gpt-6-luna` and Claude Code to `haiku`. Use `--model MODEL` to select another available worker model. The Codex command installs the `shunt_reader` MCP server as well as native agents and the read hook. After installation, restart the harness. For Codex, review and trust the hook with `/hooks`. For Pi, trust the project and run `/reload`.

Rerun the same command with the same model and options to repair missing files. It does not overwrite conflicting or edited files. If it reports a conflict, inspect the named path and preserve any changes before you remove or rename it. Then rerun the command. Do not install the marketplace plugin and project files together. They can add duplicate agents or hooks.

### Verify setup

Run `/path/to/cc-shunt/scripts/doctor HARNESS --project "$PWD"` to check the project installation. Replace `HARNESS` with `codex`, `claude`, `copilot`, `pi`, or `opencode`. Static checks do not confirm that the harness loaded or trusted the hook, or that provider authentication and model access work. For Codex or Claude, add `--live` to run a small worker request. It uses the configured provider and can incur charges. For the other harnesses, follow the manual checks printed by the command.

### Disable, update, and uninstall

Before editing configuration, back it up. Keep unrelated agents, skills, hooks, plugins, and MCP servers. Restart the harness after changes.

- **Disable routing:** For Codex, Claude, or Copilot, remove only the hook entry that invokes `scripts/check-large-read.sh` from `.codex/hooks.json`, `.claude/settings.json`, or `.github/hooks/shunt.json`, respectively. For Pi, set `hooks` to `false` in `.pi/shunt.json`. For OpenCode, remove the CC Shunt link at `.opencode/plugins/shunt.js`. This stops recognized broad-read blocking; installed agents remain available. `--no-hooks` selects no hook for a new install; do not rely on it to remove an existing hook.
- **Update:** Update the source clone, then rerun the install command. Inspect any conflict before replacing a file. The project install copies skill and agent definitions and links scripts to the source; a source update alone does not refresh the copies. To change a model, inspect and update the installed agent definitions and, for Codex, `.codex/config.toml`; for Pi, update `.pi/shunt.json`. Run the verification command again.
- **Uninstall:** First disable the hook as above. Remove the three CC Shunt skill folders `scout`, `bulk-reader`, and `code-writer` under the harness skill directory: `.agents/skills` for Codex, or `.claude/skills`, `.github/skills`, `.pi/skills`, or `.opencode/skills` for the other harnesses. Remove the matching agent files under `.codex/agents`, `.claude/agents`, `.github/agents`, or `.opencode/agents`. For Pi, remove the CC Shunt `.pi/extensions/shunt` link and `.pi/shunt.json`. For Codex, also remove only the `[mcp_servers.shunt_reader]` section from `.codex/config.toml`. Inspect ownership before deleting any file; do not delete an unrelated file with the same name. Remove the source clone only after its installed links are removed.

These steps apply to project installations. For a marketplace or plugin installation, use that harness's plugin manager to disable or remove `cc-shunt` instead.

## Harness capabilities

The hook blocks recognized broad reads. Its coverage is limited; shell pipes and some commands can pass through. It is not a security boundary. A blocked read does not itself guarantee that the parent delegates.

| Harness | Routing and worker | Waiting and visible status |
| --- | --- | --- |
| Codex | Read hook, native Scout, and `shunt_reader` MCP | MCP call waits for its final answer. Live MCP progress display is not established. Review and trust the hook. |
| Claude Code | Read hook and native Scout | Native agent visibility and waiting depend on the harness. Custom per-worker cost display is not established. |
| Copilot CLI | Read hook and native Scout | Native agent visibility and waiting depend on the harness. Live per-worker cost display is not established. |
| Pi | Read hook and isolated Pi worker tool | The tool waits for its worker. The extension displays status, model, token use, and reported cost when available. |
| OpenCode | Read hook plugin and native Scout | Native agent behavior varies by version. [Current OpenCode documentation](https://opencode.ai/docs/agents/) describes background subagents. Do not assume the parent is blocked. |

For blocking behavior, use a route that waits for the final result. Verify the behavior in the installed harness and version. Worker cost depends on provider usage and is not necessarily an invoice amount.

## How it works

- The hook blocks recognized reads above 120 selected lines. It tells the parent to send Scout the paths and complete task.
- Scout searches the project and returns cited findings. Codex can use the blocking `shunt_reader` MCP tool. Other installs use the harness's native agent or Pi extension tool.
- Use a direct read for a short, known section. Do not split one broad read into repeated sections.
- The hook is a routing aid. It does not detect every shell command or pipe. It is not a security boundary.
- `scripts/read-files` validates text and adds line numbers. `scripts/write-code` writes one file safely. Code-writer remains optional.

## Package formats

The root `plugin.json` uses Agent Plugins 1.0 for shared skills and client-specific components. Claude Code uses `.claude-plugin/plugin.json` and a Claude marketplace. Copilot uses `.github/plugin/marketplace.json` and `com.github.copilot/`. Codex uses an Agent Plugins marketplace and a local project installer for its native agents and MCP config. Pi packages use `package.json`; OpenCode supports local plugins and npm packages.

Harness formats do not provide equal features. Agent Plugins standardizes skills and MCP configuration. Hooks and agent profiles remain harness-specific. See the [Agent Plugins reference](https://docs.github.com/en/copilot/reference/plugin-and-marketplace-reference), [Claude plugin guide](https://code.claude.com/docs/en/plugins), [Codex packaging guide](https://developers.openai.com/plugins/build/plugins), [Copilot plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference), [Pi package guide](https://pi.dev/docs/latest/packages), and [OpenCode plugin guide](https://dev.opencode.ai/docs/plugins/).

## Checks

These checks use local stubs. They do not call a model provider.

```sh
bash tests/hooks.sh
bash tests/native.sh
bash tests/codex-mcp.sh
node tests/pi.mjs
node tests/opencode.mjs
node tests/mcp.mjs
```

Read `NOTICE` for the Spotify Shunt adaptation and license details. This is an independent project. It is not an official Spotify plugin.
