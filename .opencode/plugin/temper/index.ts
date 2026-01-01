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

export const TemperPlugin: Plugin = async ({ client, $ }) => {
  const injectedSessions = new Set<string>();

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

      // Inject using the same model/agent as the user message
      await injectTemperContext(client, $, sessionID, {
        model: output.message.model,
        agent: output.message.agent,
      });
    },
  };
};
