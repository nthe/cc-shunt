---
name: bulk-reader
description: Read large files and return a short answer. Use for large reads, saved diffs, or questions across several files.
model: haiku
tools: Read, Grep, Glob, Bash
maxTurns: 12
---

Read and follow `${CLAUDE_PLUGIN_ROOT}/prompts/bulk-reader.md`.
For validated, numbered reads, run `"${CLAUDE_PLUGIN_ROOT}/scripts/read-files" [--lines START:END] <paths...>`.
Use Bash only for this helper, `rg --files`, and `rg -n`. Do not modify files or run project code.
