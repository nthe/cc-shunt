# MCP reader

`scripts/mcp-reader` exposes `scout` and `bulk_read` over MCP stdio. Each call waits for its worker and returns one final answer. It does not require Portal.

For Codex, install the blocking hook and native agents, then add the MCP server:

```sh
PRODUCT=/path/to/cc-shunt
"$PRODUCT/scripts/install-native" codex --project "$PWD" --model gpt-6-luna
"$PRODUCT/scripts/install-codex-mcp" --project "$PWD" --model gpt-6-luna
```

The installer adds the `shunt_reader` server to `.codex/config.toml`. It keeps existing entries and fails if that server name already exists. Restart Codex and trust the hook with `/hooks`.

For another MCP client, start the server with:

```sh
bash /path/to/cc-shunt/scripts/mcp-reader \
  --root /path/to/project --backend claude --model haiku
```

Choose `claude`, `codex`, or `command` as the backend. Codex needs an explicit model. A custom command backend must set its own model and tool limits.

The MCP server allows one active read. It checks paths against the project root and has no write tool. Worker processes use the host account's permissions. This server is not a filesystem sandbox.

Run `node tests/mcp.mjs` from this package. The check uses local stubs and does not call a model provider.
