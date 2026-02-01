/**
 * OpenCode Temper Plugin
 *
 * Loaded automatically via opencode.json configuration.
 * Injects workflow context at session start and tool execution boundaries.
 */

import type { Plugin, PluginInput } from "@opencode-ai/plugin";
import { appendFile } from "node:fs/promises";

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
  const lastInjection = new Map<string, number>();
  const THROTTLE_MS = 60000;

  const logEvent = async (eventName: string, data: any) => {
    try {
      const timestamp = new Date().toISOString();
      const logEntry = `\n${"=".repeat(80)}\n[${timestamp}] ${eventName}\n${JSON.stringify(data, null, 2)}\n`;
      await appendFile(logPath, logEntry)
    } catch (error) {
      console.error(`[temper] Failed to log ${eventName}:`, error);
    }
  };

  // Helper to inject workflow message (throttled)
  const injectWorkflowMessage = async (
    sessionID: string,
    hookName: string,
    message: string
  ) => {
    const key = `${sessionID}:${hookName}`;
    const now = Date.now();
    const last = lastInjection.get(key) || 0;
    
    // Throttle: only inject if THROTTLE_MS has passed
    if (now - last < THROTTLE_MS) {
      return;
    }
    
    lastInjection.set(key, now);
    
    try {
      await client.session.prompt({
        path: { id: sessionID },
        body: {
          noReply: true,
          parts: [{ type: "text", text: message, synthetic: true }],
        },
      });
    } catch (error) {
      // Silent fail
      await logEvent("injection-failed", { hookName, error: String(error) });
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

      logEvent(`chat.message fired for session ${sessionID}`, {});

      // Inject using the same model/agent as the user message
      await injectTemperContext(client, $, sessionID, {
        model: output.message.model,
        agent: output.message.agent,
      });
    },

    "file.edited": async (input, output) => {
      logEvent("file.edited", { input, output })
    },

    "tool.execute.before": async (input, output) => {
      logEvent("tool.execute.before", { input, output });
      
      const tool = input.tool;
      const sessionID = input.sessionID;
      const eventString = `tool.execute.before:${tool}`;
      
      await logEvent("workflow-event", { event: eventString });
      
      if (tool === "bash" && input.args?.command) {
        const originalCommand = input.args.command;
        input.args.command = `export OPENCODE_SESSION_ID="${sessionID}"; ${originalCommand}`;
      }
      
      try {
        const guidance = await $`bash tools/temper --event ${eventString}`.text();
        if (guidance && guidance.trim().length > 0) {
          await injectWorkflowMessage(sessionID, eventString, guidance);
        }
      } catch (error) {
        console.error(`[temper] Hook failed for ${eventString}:`, error);
      }
    },

    "tool.execute.after": async (input, output) => {
      logEvent("tool.execute.after", { input, output });
      
      const tool = input.tool;
      const sessionID = input.sessionID;
      const command = tool === "bash" ? output.args?.command || "" : "";
      const eventString = tool === "bash" 
        ? `tool.execute.after:bash:${command}`
        : `tool.execute.after:${tool}`;
      
      await logEvent("workflow-event", { event: eventString });
      
      try {
        const guidance = await $`bash tools/temper --event ${eventString}`.text();
        if (guidance && guidance.trim().length > 0) {
          await injectWorkflowMessage(sessionID, eventString, guidance);
        }
      } catch (error) {
        console.error(`[temper] Hook failed for ${eventString}:`, error);
      }
    },
  };
};
