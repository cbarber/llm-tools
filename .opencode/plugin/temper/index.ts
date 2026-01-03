/**
 * OpenCode Temper Plugin
 *
 * Injects workflow boundary context at session start.
 * Runs `temper init` and injects output as synthetic message.
 */

import type { Plugin, PluginInput } from "@opencode-ai/plugin";

type OpencodeClient = PluginInput["client"];

/**
 * Get the current model/agent context for a session by querying messages.
 */
async function getSessionContext(
  client: OpencodeClient,
  sessionID: string
): Promise<
  { model?: { providerID: string; modelID: string }; agent?: string } | undefined
> {
  try {
    const response = await client.session.messages({
      path: { id: sessionID },
      query: { limit: 50 },
    });

    if (response.data) {
      for (const msg of response.data) {
        if (msg.info.role === "user" && "model" in msg.info && msg.info.model) {
          return { model: msg.info.model, agent: msg.info.agent };
        }
      }
    }
  } catch {
    // On error, return undefined
  }

  return undefined;
}

/**
 * Inject temper workflow context into a session.
 */
async function injectTemperContext(
  client: OpencodeClient,
  $: PluginInput["$"],
  sessionID: string,
  context?: { model?: { providerID: string; modelID: string }; agent?: string }
): Promise<void> {
  try {
    // Check if AGENTS.md exists
    const agentsMdExists = await Bun.file("AGENTS.md").exists();
    if (!agentsMdExists) {
      return;
    }

    // Check if temper exists
    const temperExists = await Bun.file("tools/temper").exists();
    if (!temperExists) {
      return;
    }

    // Run temper init
    const output = await $`bash tools/temper init`.text();

    if (!output || output.trim().length === 0) {
      return;
    }

    const workflowContext = `## Workflow State

${output.trim()}
`;

    // Inject via synthetic message with noReply
    await client.session.prompt({
      path: { id: sessionID },
      body: {
        noReply: true,
        model: context?.model,
        agent: context?.agent,
        parts: [{ type: "text", text: workflowContext, synthetic: true }],
      },
    });
  } catch (error) {
    // Silent skip on error
    console.error("[temper] Injection failed:", error);
  }
}

export const TemperPlugin: Plugin = async ({ client, $, directory }) => {
  const injectedSessions = new Set<string>();
  const logPath = `${directory}/.opencode/event.log`;
  const absoluteLogPath = `/home/cbarber/src/llm-tools/.opencode/event.log`;
  
  // Test that plugin is loaded by writing to known location
  try {
    await Bun.write(absoluteLogPath, `[${new Date().toISOString()}] TemperPlugin loaded\n`, { append: true });
  } catch (e) {
    // Silent fail
  }

  // Helper to log event data
  const logEvent = async (eventName: string, data: any) => {
    try {
      const timestamp = new Date().toISOString();
      const logEntry = `\n${"=".repeat(80)}\n[${timestamp}] ${eventName}\n${JSON.stringify(data, null, 2)}\n`;
      
      // Force sync write to ensure it hits disk
      const file = Bun.file(logPath);
      const existing = await file.exists() ? await file.text() : "";
      await Bun.write(logPath, existing + logEntry);
    } catch (error) {
      // Try to write error to a known location
      await Bun.write(`${directory}/.opencode/plugin-error.log`, 
        `[${new Date().toISOString()}] Failed to log ${eventName}: ${error}\n`,
        { append: true }
      );
    }
  };

  return {
    "chat.message": async (_input, output) => {
      const sessionID = output.message.sessionID;

      // Skip if already injected this session
      if (injectedSessions.has(sessionID)) return;

      // Check if already injected (handles plugin reload)
      try {
        const existing = await client.session.messages({
          path: { id: sessionID },
        });

        if (existing.data) {
          const hasTemperContext = existing.data.some(msg => {
            const parts = (msg as any).parts || (msg.info as any).parts;
            if (!parts) return false;
            return parts.some((part: any) =>
              part.type === 'text' && part.text?.includes('## Workflow State')
            );
          });

          if (hasTemperContext) {
            injectedSessions.add(sessionID);
            return;
          }
        }
      } catch {
        // On error, proceed with injection
      }

      injectedSessions.add(sessionID);

      // Log that chat.message fired
      try {
        await Bun.write(absoluteLogPath, `[${new Date().toISOString()}] chat.message fired for session ${sessionID}\n`, { append: true });
      } catch (e) {}

      // Inject using the same model/agent as the user message
      await injectTemperContext(client, $, sessionID, {
        model: output.message.model,
        agent: output.message.agent,
      });
    },

    "file.edited": async (input, output) => {
      // Log with absolute path
      try {
        const timestamp = new Date().toISOString();
        const logEntry = `\n${"=".repeat(80)}\n[${timestamp}] file.edited\n${JSON.stringify({ input, output }, null, 2)}\n`;
        await Bun.write(absoluteLogPath, logEntry, { append: true });
      } catch (e) {}
      
      await logEvent("file.edited", { input, output });
    },

    "tool.execute.before": async (input, output) => {
      // Log with absolute path
      try {
        const timestamp = new Date().toISOString();
        const logEntry = `\n${"=".repeat(80)}\n[${timestamp}] tool.execute.before\n${JSON.stringify({ input, output }, null, 2)}\n`;
        await Bun.write(absoluteLogPath, logEntry, { append: true });
      } catch (e) {}
    },

    "tool.execute.after": async (input, output) => {
      // Log with absolute path
      try {
        const timestamp = new Date().toISOString();
        const logEntry = `\n${"=".repeat(80)}\n[${timestamp}] tool.execute.after\n${JSON.stringify({ input, output }, null, 2)}\n`;
        await Bun.write(absoluteLogPath, logEntry, { append: true });
      } catch (e) {}
    },
  };
};
