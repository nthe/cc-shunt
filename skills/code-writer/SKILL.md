---
name: code-writer
description: Delegate routine code generation to a worker model. Use for tests, configuration, type stubs, or code that follows an existing reference file.
---

Use the native `code-writer` subagent when installed (`cc-shunt:code-writer` in the Claude plugin). In Pi, call `shunt_code_writer`. Supply the specification, reference paths, target path, and explicit replacement choice. Do not read the references into the parent context first. Request a fresh worker context where supported. With a target, request only the write status. The worker must use the shared safe write helper; review and test its result.

Send the full specification in one task. Prefer a blocking delegation call. With asynchronous agents, wait for completion; use explicit waits of up to 60 seconds only when needed. Do not send status requests or create a second worker for the same target.

Use the following CLI fallback only when native delegation is not installed or the user selects a CLI backend. Do not silently fall back to the parent model when the configured worker model is unavailable.

Use the `scripts/code-write` file beside this SKILL.md. Resolve its absolute path from the skill location supplied by the harness. Keep the working directory at the user's project.

```sh
"<skill-directory>/scripts/code-write" --spec "<what to generate>" --reference <reference-file> --target <output-path>
```

The reference is required. You can supply more than one reference. Omit `--target` to print code. Existing targets require `--overwrite`; use it only when replacement is part of the user's task. With `--target`, only the write status enters your context.

Use `--backend claude`, `--backend codex`, or `--backend command` to select the worker. `--model` overrides `SHUNT_MODEL`. Claude defaults to Haiku. Codex requires a configured worker model ID. Use the backend configured at installation unless the user requests another.

Each call is independent. To build on generated code, use it as the next reference. Review the result and run the project checks before you accept it. Keep complex edits, debugging, and design decisions with the main agent.
