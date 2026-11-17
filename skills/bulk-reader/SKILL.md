---
name: bulk-reader
description: Delegate large file reads and source traces to a worker model. Use when a question needs substantial content across files or a large saved diff.
---

Use direct search or a bounded read for a small lookup. Delegate when substantial file content would otherwise enter your context. A file count alone does not require delegation. Reuse evidence already in the conversation.

Use the native `bulk-reader` subagent when installed (`cc-shunt:bulk-reader` in the Claude plugin). In Pi, call `shunt_bulk_reader`. Send one worker the complete related question, starting paths, scope, required output, and request for exact `file:line` evidence. Include relevant known facts for follow-up questions. Do not split one source trace into separate readers and citation reviewers. Use parallel workers only for independent questions. Do not read the full files into the parent context first. Request a fresh worker context, without the parent conversation, where supported.

Prefer a blocking delegation call when the harness provides one. With asynchronous agents, wait for completion. If an explicit wait is required, use the longest supported wait up to 60 seconds and repeat only while work remains. Do not send status requests or progress reminders. Partial messages do not establish completion. Collect the worker's final result before answering.

Check calculations and consistency from the returned evidence. If evidence is missing or conflicts, send one combined follow-up to the same worker, or read the exact bounded source section. Do not start another reviewer or repeat all reads to check citations. State any gap that remains.

Use the following CLI fallback only when native delegation is not installed or the user selects a CLI backend. Do not silently fall back to the parent model when the configured worker model is unavailable.

For a CLI installation, prefer `bulk_read` from the `shunt_reader` MCP server when available. It uses the same CLI worker and waits for its final answer. Do not launch another CLI call or poll the terminal for that request. In Codex code mode, await the MCP call in one exec cell with `// @exec: {"yield_time_ms": 60000}` on the first line. If the cell itself yields, wait for that cell with the longest supported wait up to 60 seconds.

Use the `scripts/bulk-read` file beside this SKILL.md. Resolve its absolute path from the skill location supplied by the harness. Keep the working directory at the user's project.

```sh
"<skill-directory>/scripts/bulk-read" --question "<question>" --paths <file1> [<file2> ...]
```

Use `--backend claude`, `--backend codex`, or `--backend command` to select the worker. `--model` overrides `SHUNT_MODEL`. Claude defaults to Haiku. Codex requires a configured worker model ID. Use the backend configured at installation unless the user requests another.

CLI calls are independent. For a follow-up, send the paths again. The worker consumes tokens for each request. Only its answer enters your context. Check the relevant source section before edits. Keep debugging and design decisions with the main agent.
