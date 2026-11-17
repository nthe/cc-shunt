# Pi adapter

Pi has no built-in subagent system. The extension starts isolated Pi workers and registers Scout, bulk-reader, and code-writer tools.

Install into a project with a model that Pi supports:

```sh
/path/to/cc-shunt/scripts/install-native pi --project "$PWD" --model provider/model
```

The installer links the extension into `.pi/extensions` and writes `.pi/shunt.json`. Trust the project and run `/reload`.

The worker uses read-only tools. It does not load extensions, MCP servers, skills, session history, or project context files. The extension shows worker status, model, token use, cost, and cancellation. Code-writer can write one target through the shared safe writer.

A published package can also be installed through Pi's package manager. Set `SHUNT_PI_MODEL` to a supported `provider/model`, or add the worker model to `.pi/shunt.json`.

Run `node tests/pi.mjs` from this package. It uses a local stub and does not call a model provider. See the [Pi package guide](https://pi.dev/docs/latest/packages) and [extension guide](https://pi.dev/docs/latest/extensions).
