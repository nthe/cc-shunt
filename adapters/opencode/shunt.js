import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const hook = resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), "../../scripts/check-large-read.sh");
const workers = new Set(["scout", "bulk-reader", "code-writer"]);

function checkRead(payload, cwd) {
  return new Promise((resolve, reject) => {
    const child = execFile("bash", [hook, "claude"], {
      cwd, encoding: "utf8", timeout: 10000, maxBuffer: 65536,
    }, (error, stdout) => {
      if (error) return reject(new Error("Shunt read check failed. Check that jq is installed and the CC Shunt source path exists."));
      try {
        resolve(stdout.trim() ? JSON.parse(stdout).hookSpecificOutput?.permissionDecisionReason : undefined);
      } catch {
        reject(new Error("Shunt read check returned invalid JSON."));
      }
    });
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  });
}

export const Shunt = async ({ client, directory }) => {
  const agents = new Map();
  return {
    "chat.params": async (input) => {
      agents.set(input.sessionID, input.agent);
    },
    event: async ({ event }) => {
      if (event.type === "session.deleted") agents.delete(event.properties.info.id);
    },
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "read" && input.tool !== "bash") return;
      let agent = agents.get(input.sessionID);
      if (!agents.has(input.sessionID)) {
        // A resumed tool call can run before the next model request.
        const response = await client.session.messages({ path: { id: input.sessionID } });
        const messages = response.data ?? [];
        agent = [...messages].reverse().find((message) => message.info.role === "assistant")?.info.agent;
      }
      if (workers.has(agent)) return;
      const args = input.tool === "read"
        ? { file_path: output.args.filePath, offset: output.args.offset, limit: output.args.limit }
        : output.args;
      const reason = await checkRead({
        tool_name: input.tool === "read" ? "Read" : "Bash",
        tool_input: args,
        cwd: directory,
      }, directory);
      if (reason) throw new Error(`${reason} Delegate to the native scout agent with the task tool. Pass starting paths and the complete task.`);
    },
  };
};
