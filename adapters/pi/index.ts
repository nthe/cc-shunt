import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { checkRead, loadConfig, runTask } from "./runtime.mjs";

export default function (pi: ExtensionAPI) {
  if (process.env.SHUNT_ACTIVE) return;
  pi.on("tool_call", async (event, ctx) => {
    if (!["read", "bash"].includes(event.toolName)) return;
    try {
      const reason = checkRead(loadConfig(ctx.cwd), ctx.cwd, event.toolName, event.input);
      if (reason) return { block: true, reason };
    } catch (error) {
      return { block: true, reason: error instanceof Error ? error.message : String(error) };
    }
  });
  for (const agent of ["scout", "bulk-reader", "code-writer"] as const) {
    const writer = agent === "code-writer";
    const scout = agent === "scout";
    pi.registerTool({
      name: writer ? "shunt_code_writer" : scout ? "shunt_scout" : "shunt_bulk_reader",
      label: `Shunt ${agent}`,
      description: writer
        ? "Delegate one routine code file to the configured worker model. Supply the spec and reference file paths. Set target to write safely and return only its path."
        : scout ? "Complete a read-only source task. Supply starting files or folders and the complete task. The worker discovers related source and returns one concise cited answer."
        : "Delegate large file reads to the configured worker model. Supply the question and file paths. Only the answer enters this conversation.",
      parameters: writer ? Type.Object({
        spec: Type.String({ minLength: 1 }), reference: Type.Array(Type.String({ minLength: 1 }), { minItems: 1 }),
        target: Type.Optional(Type.String({ minLength: 1 })), overwrite: Type.Optional(Type.Boolean()),
      }) : scout ? Type.Object({ task: Type.String({ minLength: 1 }), paths: Type.Array(Type.String({ minLength: 1 }), { minItems: 1, maxItems: 256 }) })
        : Type.Object({ question: Type.String({ minLength: 1 }), paths: Type.Array(Type.String({ minLength: 1 }), { minItems: 1 }) }),
      async execute(_id, params, signal, onUpdate, ctx) {
        try {
          return await runTask(loadConfig(ctx.cwd), ctx.cwd, agent, params, signal, (details) => {
            onUpdate?.({ content: [{ type: "text", text: `${agent}: ${details.status}` }], details });
          });
        } catch (error) {
          return { content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }], details: { agent, status: "failed" }, isError: true };
        }
      },
      renderResult(result, { expanded }, theme, context) {
        const details = (result.details || {}) as { model?: string; status?: string; input?: number; output?: number; cost?: number };
        const isError = result.isError || context.isError;
        let text = `${agent}: ${details.status || "complete"}`;
        if (details.model) text += ` | ${details.model}`;
        if (details.input || details.output) text += ` | ${details.input || 0} input, ${details.output || 0} output tokens`;
        if (details.cost) text += ` | $${details.cost.toFixed(4)}`;
        if (expanded || isError) text += "\n" + result.content.filter((part) => part.type === "text").map((part) => part.text).join("\n");
        return new Text(theme.fg(isError ? "error" : "toolOutput", text), 0, 0);
      },
    });
  }
}
