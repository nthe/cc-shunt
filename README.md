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

Keep this folder in a stable path. Project installs link scripts and adapters to it. Use one install route per harness. Do not install the plugin and project files at the same time; that can add duplicate hooks or agents.

### Codex: measured setup

Run these commands from the project root. They add native agent files, a blocking read hook, and the `shunt_reader` MCP server.

```sh
PRODUCT=/path/to/cc-shunt
"$PRODUCT/scripts/install-native" codex --project "$PWD" --model gpt-6-luna
"$PRODUCT/scripts/install-codex-mcp" --project "$PWD" --model gpt-6-luna
```

Restart Codex. Review and trust the hook with `/hooks`. The MCP server starts a separate Codex CLI worker. It uses the configured model and project root. Set `--model` to another model that Codex can use. To match the reported run, use `gpt-6.1-sol` at high effort for the parent and `gpt-6-luna` at high effort for the worker. The installer sets only the worker model.

The Codex marketplace plugin supplies skills and the blocking hook. Use that route by itself. The measured setup above is a separate project install with native agent files and MCP setup.

### Claude Code

Use the plugin directly:

```sh
claude --plugin-dir /path/to/cc-shunt
```

Or add the marketplace in Claude Code:

```text
/plugin marketplace add /path/to/cc-shunt
/plugin install cc-shunt@shunt-tools
```

The plugin includes native Scout, bulk-reader, and code-writer agents. Scout uses Haiku by default. For a project-scoped install with another worker model, use `scripts/install-native claude --project DIR --model MODEL` instead of the plugin.

### GitHub Copilot

The package uses the Agent Plugins format. Add the local marketplace in Copilot CLI:

```sh
copilot plugin marketplace add /path/to/cc-shunt
copilot plugin install cc-shunt@shunt-tools
```

The same package format can be installed from the VS Code Plugins view. For a project-scoped install with an explicit worker model, run this instead of the marketplace install:

```sh
/path/to/cc-shunt/scripts/install-native copilot --project "$PWD" --model MODEL
```

`MODEL` must be available in Copilot. Check the selected model in the harness.

### Pi

For a project install, run:

```sh
/path/to/cc-shunt/scripts/install-native pi --project "$PWD" --model provider/model
```

This links the extension into `.pi/extensions`. Trust the project and run `/reload`. The extension adds `shunt_scout`, `shunt_bulk_reader`, and `shunt_code_writer` tools. To use the package through Pi's package manager after publishing it to npm or Git, add its source with `pi install` and set `SHUNT_PI_MODEL` to a supported `provider/model`.

### OpenCode

Run:

```sh
/path/to/cc-shunt/scripts/install-native opencode --project "$PWD" --model provider/model
```

This installs native child-agent definitions and links the plugin. OpenCode also supports local plugins and npm packages. The package can be added to `opencode.json` after it is published to npm.

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
