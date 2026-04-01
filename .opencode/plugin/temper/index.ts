/**
 * OpenCode Temper Plugin
 *
 * Loaded automatically via opencode.json configuration.
 * Injects workflow context at session start and tool execution boundaries.
 */
import type { Plugin, PluginInput } from "@opencode-ai/plugin";
import { appendFile, readFile } from "node:fs/promises";
import { createOpencodeClient as createV2Client } from "@opencode-ai/sdk/v2/client";

type OpencodeClient = PluginInput["client"];

type Trigger = {
  event: string;
  tool?: string;
  command?: string;
  when?: string;
  blocking?: boolean;
};

type Skill = {
  name: string;
  description: string;
  once?: boolean;
  triggers: Trigger[];
  content: string;
};

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
    } else if (current && line.match(/^\s+(tool|command|when|blocking):/)) {
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

function matchesTrigger(trigger: Trigger, event: string, tool: string, command: string): boolean {
  if (trigger.event !== event) return false;
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

async function logEvent(logPath: string, eventName: string, data: unknown): Promise<void> {
  try {
    const entry = `\n${"=".repeat(80)}\n[${new Date().toISOString()}] ${eventName}\n${JSON.stringify(data, null, 2)}\n`;
    await appendFile(logPath, entry);
  } catch {
    // Non-fatal — logging must not break the plugin
  }
}

export const TemperPlugin: Plugin = async ({ client, $, directory, serverUrl }) => {
  const logPath = `${directory}/.opencode/event.log`;
  const firedOnce = new Set<string>();
  const throttleMap = new Map<string, number>();
  const THROTTLE_MS = 60_000;

  // client.app.skills() is only available on the v2 SDK client.
  // The plugin-injected client uses the legacy SDK, so we instantiate v2 directly.
  const v2 = createV2Client({ baseUrl: serverUrl.toString() });

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
      await logEvent(logPath, "skills-load-error", { error: String(error) });
      return [];
    }
  }

  async function dispatchEvent(
    sessionID: string,
    event: string,
    tool: string,
    command: string
  ): Promise<void> {
    // Load skills on every dispatch so changes to ~/.agents/skills/ take
    // effect without restarting the plugin process.
    const skills = await loadSkills();

    await logEvent(logPath, "dispatch", { event, tool, command, skillCount: skills.length });

    for (const skill of skills) {
      const trigger = skill.triggers.find((t) => matchesTrigger(t, event, tool, command));
      if (!trigger) {
        continue;
      }

      const onceKey = `${sessionID}:${skill.name}`;
      if (skill.once && firedOnce.has(onceKey)) {
        await logEvent(logPath, "dispatch-skip", { skill: skill.name, reason: "once-already-fired" });
        continue;
      }

      if (trigger.when) {
        const passed = await evalWhen($, trigger.when, directory);
        await logEvent(logPath, "dispatch-when", { skill: skill.name, when: trigger.when, passed });
        if (!passed) continue;
      }

      const throttleKey = `${sessionID}:${skill.name}:${event}`;
      const now = Date.now();
      if (now - (throttleMap.get(throttleKey) ?? 0) < THROTTLE_MS) {
        await logEvent(logPath, "dispatch-skip", { skill: skill.name, reason: "throttled" });
        continue;
      }
      throttleMap.set(throttleKey, now);

      if (skill.once) firedOnce.add(onceKey);

      await logEvent(logPath, "dispatch-inject", { skill: skill.name });
      await injectSkill(client, $, directory, sessionID, skill.content);
    }
  }

  return {
    "shell.env": async (input, output) => {
      if (input.sessionID) output.env.OPENCODE_SESSION_ID = input.sessionID;
    },

    "chat.message": async (_input, output) => {
      const sessionID = output.message.sessionID;
      await dispatchEvent(sessionID, "session.created", "", "");
    },

    "tool.execute.before": async (input, _output) => {
      await logEvent(logPath, "tool.execute.before", { tool: input.tool });
      await dispatchEvent(input.sessionID, "tool.execute.before", input.tool, "");
    },

    "tool.execute.after": async (input, _output) => {
      const command: string = input.tool === "bash" ? (input.args?.command ?? "") : "";
      await logEvent(logPath, "tool.execute.after", { tool: input.tool, command });
      await dispatchEvent(input.sessionID, "tool.execute.after", input.tool, command);
    },

    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const { sessionID } = event.properties;
        await dispatchEvent(sessionID, "session.idle", "", "");
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
  const trigger = skill.triggers.find((t) => matchesTrigger(t, event, tool, command));
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
