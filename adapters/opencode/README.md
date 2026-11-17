# OpenCode adapter

The installer adds native child-agent definitions and links the Shunt plugin into the project.

```sh
/path/to/cc-shunt/scripts/install-native opencode --project "$PWD" --model provider/model
```

Use a model that OpenCode supports. OpenCode shows delegated work in child sessions. The plugin blocks recognized broad reads and routes them to Scout. Native agents can also run without the plugin when the parent delegates directly.

OpenCode loads local plugins from `.opencode/plugins/` or `~/.config/opencode/plugins/`. It can also load npm packages from `opencode.json`. Publish this package to npm before using the npm install path.

Run `node tests/opencode.mjs` from this package. It uses a local stub and does not call a model provider. See the [OpenCode plugin guide](https://dev.opencode.ai/docs/plugins/) and [agent guide](https://opencode.ai/docs/agents/).
