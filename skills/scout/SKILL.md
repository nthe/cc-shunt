---
name: scout
description: Delegate read-only discovery, source traces, comparisons, and fact gathering. Supply starting paths and the complete task. Use direct reads only for short, known source sections.
---

Use Scout for source discovery, behavior traces, comparisons across files, and fact gathering. Do not read full files first. Direct search and a known section of at most 120 lines are permitted for a precise check or edit. Reuse evidence already in the conversation.

If you are already running as the Scout worker, do not invoke this skill's MCP tool or script. Use your normal source tools. The parent has already started this worker.

Call the `scout` tool from the `shunt_reader` MCP server when installed. Supply `paths` (starting files or folders) and `task` (the complete question, scope, known facts, and required output). Include every requested case and output field in this first task. Ask Scout to return one cited checklist item for each request and to mark gaps. The tool starts the configured worker and waits for its final answer. Do not poll or start a duplicate call.

In Codex code mode, await the MCP call in one exec cell with `// @exec: {"yield_time_ms": 60000}` on the first line. If the cell yields, wait for that cell with `yield_time_ms: 60000`. Do not use short waits or terminal polling. Keep the wait inside the tool call where supported.

Otherwise use the native `scout` agent (`cc-shunt:scout` in the Claude plugin), or `shunt_scout` in Pi. Send the same paths and task. Request a fresh context where supported. With asynchronous agents, collect the final answer without status requests. Do not split one related task into readers and citation reviewers. Use at most one combined follow-up, and only for a material missing or conflicting fact.

For a CLI installation, use `scripts/scout` beside this skill. A native installation needs an explicitly configured CLI backend and model before it can use this fallback. Do not use script defaults to choose another provider or model. If neither native delegation nor a configured CLI backend is available, report the failure.

```sh
"<skill-directory>/scripts/scout" --task "<complete task>" --paths <starting paths...>
```

The CLI launcher stores the installed project root, backend, and model. Paths are relative to that root, or absolute. Use those settings. Do not substitute another model or fall back to parent reading when the worker fails. Report the failure. Check calculations and consistency from the returned evidence. Do not repeat source reads merely to check each citation. Use at most one combined follow-up, and only when a material missing or conflicting fact blocks the answer. Check exact source before edits.
