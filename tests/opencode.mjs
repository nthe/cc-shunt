import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, mkdirSync, symlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Shunt } from "../adapters/opencode/shunt.js";

const directory = mkdtempSync(join(tmpdir(), "shunt-opencode-"));
const previous = process.env.SHUNT_MIN_LINES;
process.env.SHUNT_MIN_LINES = "2";
try {
  const large = join(directory, "large file.txt");
  writeFileSync(large, "one\ntwo\nthree\n");
  const plugin = await Shunt({
    directory,
    client: { session: { messages: async () => ({ data: [{ info: { role: "assistant", agent: "bulk-reader" } }] }) } },
  });
  const call = (sessionID, tool, args) => plugin["tool.execute.before"]({ sessionID, tool }, { args });
  await plugin["chat.params"]({ sessionID: "parent", agent: "build" });
  await assert.rejects(call("parent", "read", { filePath: large }), /native scout/);
  await assert.rejects(call("parent", "bash", { command: `cat '${large}'` }), /native scout/);
  await call("parent", "read", { filePath: large, offset: 1, limit: 1 });
  await call("parent", "bash", { command: `head -n 1 '${large}'` });
  await plugin["chat.params"]({ sessionID: "worker", agent: "bulk-reader" });
  await call("worker", "read", { filePath: large });
  await call("resumed-worker", "read", { filePath: large });
  await plugin["chat.params"]({ sessionID: "worker", agent: "build" });
  await assert.rejects(call("worker", "read", { filePath: large }), /native scout/);
  await plugin["chat.params"]({ sessionID: "scout", agent: "scout" });
  await call("scout", "read", { filePath: large });
  await plugin.event({ event: { type: "session.deleted", properties: { info: { id: "worker" } } } });
  await call("worker", "read", { filePath: large });
  const bin = join(directory, "bin");
  mkdirSync(bin);
  symlinkSync("/bin/bash", join(bin, "bash"));
  const path = process.env.PATH;
  process.env.PATH = bin;
  try {
    await assert.rejects(call("parent", "read", { filePath: large }), /read check failed/);
  } finally {
    process.env.PATH = path;
  }
  console.log("OpenCode routing: passed");
} finally {
  if (previous === undefined) delete process.env.SHUNT_MIN_LINES;
  else process.env.SHUNT_MIN_LINES = previous;
  rmSync(directory, { recursive: true, force: true });
}
