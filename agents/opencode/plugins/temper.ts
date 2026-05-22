/**
 * OpenCode Temper Plugin
 *
 * Loaded automatically via opencode.json configuration.
 * Injects workflow context at session start and tool execution boundaries.
 */
import type { Plugin, PluginInput } from "@opencode-ai/plugin";
import { readFile } from "node:fs/promises";
import { createOpencodeClient as createV2Client } from "@opencode-ai/sdk/v2/client";

type OpencodeClient = PluginInput["client"];

type TriggerAction = "inject" | "reset" | "fail";

type Trigger = {
  event: string;
  tool?: string;
  command?: string;
  when?: string;
  blocking?: boolean;
  action?: TriggerAction;
};

type Skill = {
  name: string;
  description: string;
  once?: boolean;
  triggers: Trigger[];
  content: string;
};

// Discriminated union carrying the full context for each event type.
// The tool.execute.after variant carries the live output object so that
// "fail" actions can mutate it before OpenCode serialises the tool result.
type DispatchContext =
  | { event: "session.created" }
  | { event: "session.idle" }
  | { event: "tool.execute.before"; tool: string }
  | {
    event: "tool.execute.after";
    tool: string;
    command: string;
    output: { title: string; output: string; metadata: any };
  }
  | { event: "todo.updated"; todos: Array<{ content: string; status: string; priority: string; id: string }> };

// Parses the subset of YAML used by our skill frontmatter schema.
// Handles scalar fields (name, description, once) and the triggers list.
function parseFrontmatter(raw: string): { meta: Record<string, unknown>; body: string } {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { meta: {}, body: raw };

  const fm = match[1];
  const meta: Record<string, unknown> = {};

  // Parse scalar top-level fields
  for (const line of fm.split("\n")) {
    const scalar = line.match(/^(\w+):\s+(.+)$/);
    if (scalar && scalar[1] !== "triggers") {
      const raw = scalar[2].trim();
      const val = raw.replace(/^["']|["']$/g, "");
      meta[scalar[1]] = val === "true" ? true : val === "false" ? false : val;
    }
  }

  // Parse triggers list — each item starts with "  - event: ..."
  const triggers: Trigger[] = [];
  let current: Partial<Trigger> | null = null;
  for (const line of fm.split("\n")) {
    if (line.startsWith("  - event:")) {
      if (current?.event) triggers.push(current as Trigger);
      current = { event: line.replace(/.*event:\s*/, "").trim() };
    } else if (current && line.match(/^\s+(tool|command|when|blocking|action):/)) {
      const kv = line.match(/^\s+(\w+):\s+(.+)$/);
      if (kv) {
        const key = kv[1] as keyof Trigger;
        const raw = kv[2].trim();
        const val = raw.replace(/^["']|["']$/g, "");
        (current as Record<string, unknown>)[key] = val === "true" ? true : val === "false" ? false : val;
      }
    }
  }
  if (current?.event) triggers.push(current as Trigger);
  if (triggers.length) meta.triggers = triggers;

  return { meta, body: match[2] };
}

async function toSkill(raw: { name: string; description: string; location: string }): Promise<Skill | null> {
  const data = await readFile(raw.location, { encoding: 'utf8' });
  const { meta, body } = parseFrontmatter(data);
  const triggers = (meta.triggers as Trigger[] | undefined) ?? [];
  if (triggers.length === 0) return null;
  return {
    name: raw.name,
    description: raw.description,
    once: (meta.once as boolean | undefined) ?? false,
    triggers,
    content: body,
  };
}

function matchesTrigger(trigger: Trigger, ctx: DispatchContext): boolean {
  if (trigger.event !== ctx.event) return false;
  const tool = "tool" in ctx ? ctx.tool : "";
  const command = "command" in ctx ? ctx.command : "";
  if (trigger.tool && !new RegExp(trigger.tool).test(tool)) return false;
  if (trigger.command && !new RegExp(trigger.command).test(command)) return false;
  return true;
}

async function evalWhen($: PluginInput["$"], when: string, cwd: string): Promise<boolean> {
  try {
    const result = await $.cwd(cwd)`bash -c ${when}`.nothrow();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

// Execute the first bash code block in content, substitute its stdout output
// in place of the block, and return the result. Remaining content follows.
// Mirrors the execute_bash_block logic in tools/temper.
async function executeBashBlock($: PluginInput["$"], content: string, cwd: string): Promise<string> {
  const bashBlockRe = /^```bash \{exec\}\n([\s\S]*?)^```/m;
  const match = content.match(bashBlockRe);
  if (!match) return content;

  const code = match[1];
  const result = await $.cwd(cwd)`bash -c ${code}`.nothrow().quiet();
  const stdout = result.stdout.toString().trim();

  let output = stdout || "";
  if (result.exitCode !== 0) {
    const stderr = result.stderr.toString().trim();
    output += `\n\n⚠️ **Command execution failed (exit code: ${result.exitCode})**`;
    if (stderr) output += `\n\n**Error output:**\n\`\`\`\n${stderr}\n\`\`\``;
    output += "\n\n*Note: Workflow context may be incomplete.*";
  }

  return content.replace(match[0], output);
}

async function injectSkill(
  client: OpencodeClient,
  $: PluginInput["$"],
  directory: string,
  sessionID: string,
  content: string
): Promise<void> {
  const rendered = await executeBashBlock($, content, directory);
  await client.session.prompt({
    path: { id: sessionID },
    body: {
      noReply: true,
      parts: [{ type: "text", text: rendered, synthetic: true }],
    },
  });
}

async function logEvent(client: OpencodeClient, eventName: string, data: { [key: string]: unknown }): Promise<void> {
  await client.app.log({
    body: {
      service: "temper",
      level: "info",
      message: eventName,
      extra: data,
    },
  })
}

type SessionPhase = "new" | "pending-restore" | "restored";

type SessionState = {
  phase: SessionPhase;
  firedOnce: Set<string>;
  lastInjectionTokens: Map<string, number>;
};

const sessionStore = new Map<string, SessionState>();

const _registeredDirs = new Set<string>();
export const TemperPlugin: Plugin = async ({ client, $, directory, serverUrl }) => {
  if (_registeredDirs.has(directory)) return {};
  _registeredDirs.add(directory);
  const throttleMap = new Map<string, number>();
  await logEvent(client, "loading plugin", { directory, _registeredDirs })
  const THROTTLE_MS = 60_000;

  // client.app.skills() is only available on the v2 SDK client.
  // The plugin-injected client uses the legacy SDK, so we instantiate v2 directly.
  const v2 = createV2Client({ baseUrl: serverUrl.toString() });

  async function hydrateSession(sessionID: string): Promise<SessionState> {
    const state = sessionStore.get(sessionID)!;

    try {
      const response = await v2.session.messages({ sessionID });
      const messages = response.data ?? [];

      // If no messages yet, don't cache — allow re-hydration on next event
      // once the server has loaded the session history.
      if (messages.length === 0) return state;

      const foundInHistory: string[] = [];
      for (const { parts } of messages) {
        for (const part of parts) {
          if (part.type === "text" && part.synthetic) {
            const m = part.text.match(/^# (\S+)/m);
            if (m) {
              state.firedOnce.add(m[1]);
              foundInHistory.push(m[1]);
            }
          } else if (part.type === "tool" && part.tool === "skill") {
            const input = (part.state as { input?: { name?: string } }).input;
            const name = input?.name;
            if (name) {
              state.firedOnce.add(name);
              if (!foundInHistory.includes(name)) foundInHistory.push(name);
            }
          }
        }
      }

      await logEvent(client, "dispatch-hydrate", { sessionID, foundInHistory, messageCount: messages.length });
    } catch (error) {
      await logEvent(client, "hydrate-error", { sessionID, error: String(error) });
    }

    state.phase = "restored";
    sessionStore.set(sessionID, state);
    return state;
  }

  async function loadSkills(): Promise<Skill[]> {
    try {
      const response = await v2.app.skills();
      const raws = response.data ?? [];
      const maybeSkills = await Promise.all(raws.map(async (r) => {
        const skill = await toSkill(r);
        return skill ? skill : null;
      }));
      const skills = maybeSkills.filter(s => !!s);
      return skills;
    } catch (error) {
      await logEvent(client, "skills-load-error", { error: String(error) });
      return [];
    }
  }

  async function dispatchEvent(
    sessionID: string,
    ctx: DispatchContext,
  ): Promise<void> {
    // Load skills on every dispatch so changes to ~/.agents/skills/ take
    // effect without restarting the plugin process.
    const skills = await loadSkills();

    const state = sessionStore.get(sessionID);
    if (!state || state.phase === "pending-restore") {
      await logEvent(client, "dispatch-skip-no-state", { ctx });
      return;
    }

    await logEvent(client, "dispatch", { sessionID, ctx });

    for (const skill of skills) {
      const trigger = skill.triggers.find((t) => matchesTrigger(t, ctx));
      if (!trigger) {
        continue;
      }

      const action: TriggerAction = trigger.action ?? "inject";

      // reset action: clear firedOnce for this skill and stop — no injection,
      // no throttle check, no when guard needed.
      if (action === "reset") {
        if (state.firedOnce.has(skill.name)) {
          state.firedOnce.delete(skill.name);
          await logEvent(client, "dispatch-reset", { skill: skill.name });
        }
        continue;
      }

      // inject and fail: honour once and throttle guards.
      if (skill.once && state.firedOnce.has(skill.name)) {
        await logEvent(client, "dispatch-skip", { skill: skill.name, reason: "once-already-fired" });
        continue;
      }

      if (trigger.when) {
        const passed = await evalWhen($, trigger.when, directory);
        await logEvent(client, "dispatch-when", { skill: skill.name, when: trigger.when, passed });
        if (!passed) continue;
      }

      const throttleKey = `${sessionID}:${skill.name}:${ctx.event}`;
      const now = Date.now();
      if (now - (throttleMap.get(throttleKey) ?? 0) < THROTTLE_MS) {
        await logEvent(client, "dispatch-skip", { skill: skill.name, reason: "throttled" });
        continue;
      }
      throttleMap.set(throttleKey, now);

      if (skill.once) {
        state.firedOnce.add(skill.name);
        await logEvent(client, "add-fired-once", { skill: skill.name, firedOnce: [...state.firedOnce], sessionID });
      }

      if (action === "fail") {
        // fail is only meaningful on tool.execute.before — throwing there
        // prevents the tool from running and delivers the error message as the
        // tool result the model sees. Guard at runtime; misconfigured triggers
        // on other events are silently ignored.
        if (ctx.event !== "tool.execute.before") {
          await logEvent(client, "dispatch-skip", { skill: skill.name, reason: "fail-requires-tool.execute.before" });
          continue;
        }
        const rendered = await executeBashBlock($, skill.content, directory);
        await logEvent(client, "dispatch-fail", { skill: skill.name });
        throw new Error(rendered);
      } else {
        await logEvent(client, "dispatch-inject", { sessionID, skill: skill.name });
        await injectSkill(client, $, directory, sessionID, skill.content);
      }
    }
  }

  return {
    "shell.env": async (input, output) => {
      if (input.sessionID) output.env.OPENCODE_SESSION_ID = input.sessionID;
    },

    "chat.message": async (input, _output) => {
      const { sessionID } = input;
      if (sessionStore.has(sessionID)) return;
      // No prior session.updated — fresh process restore where session.updated. First chat.message means restore
      sessionStore.set(sessionID, {
        phase: "pending-restore",
        firedOnce: new Set(),
        lastInjectionTokens: new Map(),
      });
    },

    "tool.execute.before": async (input, _output) => {
      await logEvent(client, "tool.execute.before", { tool: input.tool });
      await dispatchEvent(input.sessionID, { event: "tool.execute.before", tool: input.tool });
    },

    "tool.execute.after": async (input, output) => {
      const command: string = input.tool === "bash" ? (input.args?.command ?? "") : "";
      await logEvent(client, "tool.execute.after", { tool: input.tool, command });
      await dispatchEvent(input.sessionID, {
        event: "tool.execute.after",
        tool: input.tool,
        command,
        output,
      });
    },

    event: async ({ event }) => {
      if (event.type === "session.updated") {
        const { id: sessionID } = event.properties.info;
        if (sessionStore.has(sessionID)) return;
        // First sesion.updated means new
        sessionStore.set(sessionID, {
          phase: "new",
          firedOnce: new Set(),
          lastInjectionTokens: new Map(),
        });
        await dispatchEvent(sessionID, { event: "session.created" });
      }
      if (event.type === "session.status") {
        const { sessionID } = event.properties;
        if (!sessionStore.has(sessionID)) return;
        if (sessionStore.get(sessionID)?.phase !== "pending-restore") return;
        await hydrateSession(sessionID);
      }
      if (event.type === "session.idle") {
        const { sessionID } = event.properties;
        await dispatchEvent(sessionID, { event: "session.idle" });
      }
      if (event.type === "todo.updated") {
        const { sessionID, todos } = event.properties;
        await logEvent(client, "todo.updated", { sessionID, todos });
      }
    },
  };
};

if (import.meta.main) {
  const [skillFile, event = "session.created", tool = "", command = ""] = process.argv.slice(2);
  if (!skillFile) {
    console.error("Usage: bun .opencode/plugin/temper/index.ts <skill-file> [event] [tool] [command]");
    process.exit(1);
  }
  const skill = await toSkill({ name: skillFile, description: "", location: skillFile });
  if (!skill) {
    console.error("No triggers found in frontmatter");
    process.exit(1);
  }
  console.error("triggers:", JSON.stringify(skill.triggers, null, 2));
  let ctx: DispatchContext;
  switch (event) {
    case "tool.execute.after":
      ctx = { event, tool, command, output: { title: "", output: "", metadata: null } }
      break;
    case "tool.execute.before":
      ctx = { event, tool }
      break;
    case "session.idle":
    case "session.created":
      ctx = { event: event as "session.idle" | "session.created" }
      break;
    default:
      ctx = { event: "session.created" };
  }
  const trigger = skill.triggers.find((t) => matchesTrigger(t, ctx));
  if (!trigger) {
    console.error(`no trigger matched event="${event}" tool="${tool}" command="${command}"`);
    process.exit(1);
  }
  console.error("matched:", JSON.stringify(trigger));
  if (trigger.when) {
    const result = await Bun.$.cwd(process.cwd())`bash -c ${trigger.when}`.nothrow();
    if (result.exitCode !== 0) {
      console.error(`when guard failed (exit ${result.exitCode}): ${trigger.when}`);
      process.exit(1);
    }
    console.error(`when guard passed`);
  }
  const rendered = await executeBashBlock(Bun.$, skill.content, process.cwd());
  console.log(rendered);
}
