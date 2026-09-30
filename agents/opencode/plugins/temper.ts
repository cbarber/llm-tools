/**
 * OpenCode Temper Plugin
 *
 * Loaded automatically via opencode.json configuration.
 * Injects workflow context at session start and tool execution boundaries.
 */
import { tool, type Plugin, type PluginInput } from "@opencode-ai/plugin";
import { appendFile, chmod, mkdir, readFile, rename, stat, unlink, writeFile } from "node:fs/promises";
import { createHash, randomUUID } from "node:crypto";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createOpencodeClient as createV2Client } from "@opencode-ai/sdk/v2/client";
import { setup } from "xstate";
import { WorkflowRuntime, type WorkflowDefinition } from "./workflow-runtime";

type OpencodeClient = PluginInput["client"];
const importWorkflow = new Function("specifier", "return import(specifier)") as (specifier: string) => Promise<unknown>;

type TriggerAction = "inject" | "reset" | "fail";

type Trigger = {
  event: string;
  tool?: string;
  command?: string;
  when?: string;
  blocking?: boolean;
  action?: TriggerAction;
  worktree?: boolean;
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
  | { event: "chat.message" }
  | { event: "tool.execute.before"; tool: string; command: string }
  | {
    event: "tool.execute.after";
    tool: string;
    command: string;
    filePaths?: string[];
    output: { title: string; output: string; metadata: any };
  }
  | { event: "todo.updated"; todos: Array<{ content: string; status: string; priority: string; id: string }> };

type ProviderToolPart = {
  id?: string;
  type: "tool";
  callID: string;
  tool: string;
  metadata?: { providerExecuted?: boolean };
  state: {
    status: string;
    input?: Record<string, unknown>;
    title?: string;
    output?: string;
    metadata?: Record<string, unknown>;
    time?: { end?: number };
  };
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
    } else if (current && line.match(/^\s+(tool|command|when|blocking|action|worktree):/)) {
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

async function toSkill(raw: { name: string; description?: string; location: string }): Promise<Skill | null> {
  const data = await readFile(raw.location, { encoding: 'utf8' }).catch((err) => {
    throw new Error(`Failed to read ${raw.name}: ${raw.location}`, { cause: err });
  });
  const { meta, body } = parseFrontmatter(data);
  const triggers = (meta.triggers as Trigger[] | undefined) ?? [];
  if (triggers.length === 0) return null;
  return {
    name: raw.name,
    description: raw.description ?? "",
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

function changedFilePaths(tool: string, args: any, directory: string): string[] {
  if (tool === "edit" || tool === "write") {
    return args?.filePath ? [resolve(directory, args.filePath)] : [];
  }
  if (tool !== "apply_patch") return [];

  const paths = [...String(args?.patchText ?? "").matchAll(/^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+)$/gm)];
  return paths.map((match) => resolve(directory, match[1].trim()));
}

class ProviderToolQueue {
  private readonly seen = new Set<string>();
  private pending: DispatchContext[] = [];

  constructor(private readonly directory: string) {}

  restore(part: unknown): void {
    if (!this.isTerminalProviderTool(part)) return;
    this.seen.add(this.key(part));
  }

  update(part: unknown, earliest = 0): boolean {
    if (!this.isTerminalProviderTool(part)) return false;
    if (typeof part.state.time?.end === "number" && part.state.time.end < earliest) return false;
    const key = this.key(part);
    if (this.seen.has(key)) return false;
    this.seen.add(key);
    if (part.state.status !== "completed") return false;
    if (part.tool === "bash" && typeof part.state.metadata?.exit === "number" && part.state.metadata.exit !== 0) return false;

    const input = part.state.input ?? {};
    this.pending.push({
      event: "tool.execute.after",
      tool: part.tool,
      command: part.tool === "bash" ? String(input.command ?? "") : "",
      filePaths: changedFilePaths(part.tool, input, this.directory),
      output: {
        title: part.state.title ?? part.tool,
        output: part.state.output ?? "",
        metadata: part.state.metadata ?? {},
      },
    });
    return true;
  }

  drain(): DispatchContext[] {
    const pending = this.pending;
    this.pending = [];
    return pending;
  }

  private isTerminalProviderTool(part: unknown): part is ProviderToolPart {
    if (!part || typeof part !== "object") return false;
    const tool = part as ProviderToolPart;
    return tool.type === "tool" &&
      tool.metadata?.providerExecuted === true &&
      (tool.state?.status === "completed" || tool.state?.status === "error");
  }

  private key(part: ProviderToolPart): string {
    return part.id ?? part.callID;
  }
}

async function evalWhen($: PluginInput["$"], when: string, cwd: string): Promise<boolean> {
  try {
    const result = await $.cwd(cwd)`bash -c ${when}`.nothrow();
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

async function executeBashBlock($: PluginInput["$"], content: string, cwd: string): Promise<string> {
  const bashBlockRe = /^```bash \{exec\}\n([\s\S]*?)^```/gm;
  let rendered = "";
  let offset = 0;
  for (const match of content.matchAll(bashBlockRe)) {
    rendered += content.slice(offset, match.index);
    const result = await $.cwd(cwd)`bash -c ${match[1]}`.nothrow().quiet();
    let output = result.stdout.toString().trim();
    if (result.exitCode !== 0) {
      const stderr = result.stderr.toString().trim();
      output += `\n\nCommand execution failed (exit code: ${result.exitCode})`;
      if (stderr) output += `\n\nError output:\n\`\`\`\n${stderr}\n\`\`\``;
      output += "\n\nWorkflow context may be incomplete.";
    }
    rendered += output;
    offset = match.index + match[0].length;
  }
  return rendered + content.slice(offset);
}

async function injectSkill(
  client: OpencodeClient,
  $: PluginInput["$"],
  directory: string,
  sessionID: string,
  content: string,
  noReply = true,
): Promise<void> {
  const rendered = await executeBashBlock($, content, directory);
  await client.session.prompt({
    path: { id: sessionID },
    body: {
      noReply,
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
  providerTools: ProviderToolQueue;
  pendingProviderParts: unknown[];
  restoreStartedAt: number;
  hydration?: Promise<SessionState>;
};

type WorkflowFacts = {
  dirty: boolean;
  head: string;
  ahead: number;
  branchCommits: number;
  hasPr: boolean;
  prHead?: string;
  merged?: boolean;
  authorApprovalRequired?: boolean;
  reviewDecision?: string;
};

type ActiveWorkflow = {
  definition: WorkflowDefinition;
  runtime: WorkflowRuntime;
  source: string;
  sourceHash: string;
  queue: Promise<void>;
  idleTimer?: ReturnType<typeof setTimeout>;
  idleDeadline?: number;
  skipSkillOnce?: string;
  lastFacts: WorkflowFacts;
};

type WorkflowEnvelope = {
  workflowId: string;
  version: number;
  source: string;
  sourceHash: string;
  directory: string;
  snapshot: unknown;
  idleDeadline?: number;
};

const sessionStore = new Map<string, SessionState>();

const BASH_GIT_INSTRUCTIONS = `
# Git and GitHub
- Only commit, amend, push, or create PRs when explicitly requested.
- Before committing, inspect \`git status\`, \`git diff\`, and \`git log --oneline -10\`; stage only intended files and never commit secrets.
- Write a concise commit message that matches the repo style.
- Do not update git config, skip hooks, use interactive \`-i\`, force-push, or create empty commits unless explicitly requested.
- If a commit fails or hooks reject it, fix the issue and create a new commit; do not amend the failed commit.
- Before creating a PR, inspect status, diff, remote tracking, recent commits, and the diff from the base branch.
- Review all commits included in the PR, not just the latest commit.
- Use \`gh\` for GitHub tasks, including PRs, issues, checks, and releases; return the PR URL when done.`;

const SYSTEM_GIT_INSTRUCTIONS = [
  "- Do not amend a commit unless explicitly requested to do so.",
  "- You struggle using the git interactive console. **ALWAYS** prefer using non-interactive git commands.",
  "- Do not amend commits unless explicitly requested.",
  "NEVER commit changes unless the user explicitly asks you to. It is VERY IMPORTANT to only commit when explicitly asked, otherwise the user will feel that you are being too proactive.",
  "DO NOT run `git commit`, `git push`, `git reset`, `git rebase` and/or do any other git mutations unless explicitly asked to do so. Ask for confirmation each time when you need to do git mutations, even if the user has confirmed in earlier conversations.",
  "If the user tells you to stage and commit, you may do so. ",
  "You are NEVER allowed to stage and commit files automatically.",
];

function removeSystemGitInstructions(system: string): string {
  return SYSTEM_GIT_INSTRUCTIONS.reduce((result, instruction) => result.replace(instruction, ""), system);
}

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
  const workflows = new Map<string, ActiveWorkflow>();
  const toolFacts = new Map<string, { active: ActiveWorkflow; facts: WorkflowFacts }>();
  const providerFacts = new Map<string, { active: ActiveWorkflow; facts: WorkflowFacts }>();
  const stateRoot = join(process.env.XDG_STATE_HOME ?? join(process.env.HOME ?? directory, ".local", "state"), "opencode", "temper");

  function sessionFile(sessionID: string, extension: string): string {
    return join(stateRoot, `${createHash("sha256").update(sessionID).digest("hex")}.${extension}`);
  }

  async function ensureStateRoot(): Promise<void> {
    await mkdir(stateRoot, { recursive: true, mode: 0o700 });
    await chmod(stateRoot, 0o700);
  }

  async function trace(sessionID: string, record: Record<string, unknown>): Promise<void> {
    await ensureStateRoot();
    const path = sessionFile(sessionID, "jsonl");
    const redacted = JSON.parse(JSON.stringify(record, (key, value) => {
      if (/(?:token|secret|password|authorization|api.?key)/i.test(key)) return "<REDACTED>";
      if (typeof value !== "string") return value;
      return value
        .replace(/(bearer\s+)[^\s"']+/gi, "$1<REDACTED>")
        .replace(/((?:token|secret|password|api[_-]?key)\s*[=:]\s*)[^\s"']+/gi, "$1<REDACTED>");
    }));
    await appendFile(path, `${JSON.stringify({ timestamp: new Date().toISOString(), sessionID, ...redacted })}\n`, { mode: 0o600 });
    await chmod(path, 0o600);
  }

  async function sampleFacts(): Promise<WorkflowFacts> {
    const status = await $.cwd(directory)`git status --porcelain`.nothrow().text();
    const head = (await $.cwd(directory)`git rev-parse HEAD`.nothrow().text()).trim();
    const aheadText = (await $.cwd(directory)`git rev-list --count @{upstream}..HEAD`.nothrow().text()).trim();
    const remoteHead = (await $.cwd(directory)`git symbolic-ref refs/remotes/origin/HEAD`.nothrow().text()).trim();
    const main = (await $.cwd(directory)`git show-ref --verify refs/remotes/origin/main`.nothrow().text()).trim();
    const master = (await $.cwd(directory)`git show-ref --verify refs/remotes/origin/master`.nothrow().text()).trim();
    const defaultBranch = remoteHead || (main ? "refs/remotes/origin/main" : master ? "refs/remotes/origin/master" : "");
    const branchCommitsText = defaultBranch
      ? (await $.cwd(directory)`git rev-list --count ${defaultBranch}..HEAD`.nothrow().text()).trim()
      : "0";
    const prStatus = await $.cwd(directory)`forge pr status`.nothrow().text();
    const prNumber = prStatus.match(/PR #(\d+)/)?.[1];
    const prJson = prNumber
      ? (await $.cwd(directory)`forge pr view ${prNumber} --json number,state,headRefOid,reviewDecision`.nothrow().text()).trim()
      : "";
    let pr: { number?: number; state?: string; headRefOid?: string; reviewDecision?: string } = {};
    try { pr = JSON.parse(prJson); } catch {}
    const prAheadText = pr.headRefOid && /^[0-9a-f]{40}$/.test(pr.headRefOid)
      ? (await $.cwd(directory)`git rev-list --count ${pr.headRefOid}..HEAD`.nothrow().text()).trim()
      : "";
    const upstream = (await $.cwd(directory)`git rev-parse @{upstream}`.nothrow().text()).trim();
    const commitBodies = defaultBranch
      ? (await $.cwd(directory)`git log --format=%B%x00 ${defaultBranch}..HEAD`.nothrow().text()).split("\0")
      : [];
    return {
      dirty: status.trim().length > 0,
      head,
      ahead: Math.max(Number.parseInt(aheadText, 10) || 0, Number.parseInt(prAheadText, 10) || 0),
      branchCommits: Number.parseInt(branchCommitsText, 10) || 0,
      hasPr: typeof pr.number === "number" || Boolean(prNumber),
      prHead: pr.headRefOid || upstream || undefined,
      merged: pr.state === "MERGED" || /merged PR/.test(prStatus),
      authorApprovalRequired: commitBodies.some((body) => /^Authored-By:/im.test(body) && !/^Reviewed-By:/im.test(body)),
      reviewDecision: pr.reviewDecision,
    };
  }

  async function discoveredSkills() {
    const response = await v2.app.skills({ directory });
    return (response.data ?? []).filter((skill) => skill.location !== "<built-in>");
  }

  async function renderWorkflowSkills(sessionID: string, names: string[], reply: boolean): Promise<void> {
    const skills = await discoveredSkills();
    const rendered: string[] = [];
    const renderedNames: string[] = [];
    const active = workflows.get(sessionID);
    for (const name of names) {
      if (active?.skipSkillOnce === name) {
        active.skipSkillOnce = undefined;
        continue;
      }
      const skill = skills.find((candidate) => candidate.name === name);
      if (!skill) throw new Error(`Workflow skill not found: ${name}`);
      const raw = await readFile(skill.location, "utf8");
      rendered.push(await executeBashBlock($, parseFrontmatter(raw).body, directory));
      renderedNames.push(name);
    }
    if (workflows.get(sessionID) !== active) return;
    await client.session.prompt({
      path: { id: sessionID },
      body: {
        noReply: !reply,
        parts: [{ type: "text", text: rendered.join("\n\n"), synthetic: true }],
      },
    });
    await trace(sessionID, { event: "skills.injected", source: "workflow", skills: renderedNames, reply });
  }

  async function persistWorkflow(sessionID: string, active: ActiveWorkflow, snapshot: unknown): Promise<void> {
    await ensureStateRoot();
    if (workflows.get(sessionID) !== active) return;
    const envelope: WorkflowEnvelope = {
      workflowId: active.definition.id,
      version: active.definition.version,
      source: active.source,
      sourceHash: active.sourceHash,
      directory,
      snapshot,
      idleDeadline: active.idleDeadline,
    };
    const path = sessionFile(sessionID, "json");
    const temporary = `${path}.${randomUUID()}.tmp`;
    await writeFile(temporary, JSON.stringify(envelope), { mode: 0o600 });
    if (workflows.get(sessionID) !== active) {
      await unlink(temporary).catch(() => {});
      return;
    }
    await rename(temporary, path);
    await chmod(path, 0o600);
  }

  async function loadDefinition(source: string, expectedHash?: string): Promise<{ definition: WorkflowDefinition; sourceHash: string }> {
    const code = await readFile(source, "utf8");
    const sourceHash = createHash("sha256").update(code).digest("hex");
    if (expectedHash && expectedHash !== sourceHash) throw new Error("Workflow definition changed");
    const module = await importWorkflow(`${pathToFileURL(source).href}?v=${sourceHash}`) as {
      workflow?: { id: string; version: number; createMachine: (factory: typeof setup) => WorkflowDefinition["machine"] };
    };
    if (!module.workflow || typeof module.workflow.createMachine !== "function") {
      throw new Error(`Invalid workflow definition: ${source}`);
    }
    return {
      definition: {
        id: module.workflow.id,
        version: module.workflow.version,
        machine: module.workflow.createMachine(setup),
      },
      sourceHash,
    };
  }

  async function installWorkflow(
    sessionID: string,
    source: string,
    snapshot?: unknown,
    expected?: Pick<WorkflowEnvelope, "workflowId" | "version" | "sourceHash">,
    skipSkillOnce?: string,
    idleDeadline?: number,
  ): Promise<ActiveWorkflow> {
    const loaded = await loadDefinition(source, expected?.sourceHash);
    if (expected && (loaded.definition.id !== expected.workflowId || loaded.definition.version !== expected.version)) {
      throw new Error("Workflow definition metadata changed");
    }
    const facts = await sampleFacts();
    const previous = workflows.get(sessionID);
    if (previous?.idleTimer) clearTimeout(previous.idleTimer);
    previous?.runtime.stop();
    if (previous) {
      workflows.delete(sessionID);
      await previous.queue;
    }

    let active: ActiveWorkflow;
    const runtime = new WorkflowRuntime(loaded.definition, {
      persist: async (value) => persistWorkflow(sessionID, active, value),
      renderSkills: async (skills, reply) => {
        if (workflows.get(sessionID) === active) await renderWorkflowSkills(sessionID, skills, reply);
      },
    }, snapshot);
    active = {
      definition: loaded.definition,
      runtime,
      source,
      sourceHash: loaded.sourceHash,
      queue: Promise.resolve(),
      skipSkillOnce,
      lastFacts: facts,
      idleDeadline,
    };
    workflows.set(sessionID, active);
    active.queue = runtime.start();
    await active.queue;
    if (idleDeadline) armIdle(sessionID, active);
    await trace(sessionID, { event: snapshot === undefined ? "workflow.started" : "workflow.restored", workflowId: active.definition.id });
    return active;
  }

  async function activateWorkflow(sessionID: string, skillName: string, nativeAlreadyRendered = false): Promise<boolean> {
    const skills = await discoveredSkills();
    const skill = skills.find((candidate) => candidate.name === skillName);
    if (!skill) return false;
    const projectSource = join(directory, "agents", "skills", skillName, "workflow.ts");
    const source = (await stat(projectSource).catch(() => undefined))?.isFile()
      ? projectSource : join(dirname(skill.location), "workflow.ts");
    if (!(await stat(source).catch(() => undefined))?.isFile()) return false;
    await installWorkflow(sessionID, source, undefined, undefined, nativeAlreadyRendered ? skillName : undefined);
    return true;
  }

  async function restoreWorkflow(sessionID: string): Promise<ActiveWorkflow | undefined> {
    if (workflows.has(sessionID)) return workflows.get(sessionID);
    try {
      const envelope = JSON.parse(await readFile(sessionFile(sessionID, "json"), "utf8")) as WorkflowEnvelope;
      if (envelope.directory !== directory) throw new Error("Workflow directory changed");
      const skills = await discoveredSkills();
      const allowed = skills.some((skill) => [
        join(dirname(skill.location), "workflow.ts"),
        join(directory, "agents", "skills", skill.name, "workflow.ts"),
      ].includes(envelope.source));
      if (!allowed) throw new Error("Workflow source is no longer discovered");
      return await installWorkflow(sessionID, envelope.source, envelope.snapshot, envelope, undefined, envelope.idleDeadline);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
        await trace(sessionID, { event: "workflow.restore-failed", error: String(error) });
        await unlink(sessionFile(sessionID, "json")).catch(() => {});
      }
      return undefined;
    }
  }

  function enqueueWorkflow(sessionID: string, operation: (active: ActiveWorkflow) => Promise<void>): Promise<void> {
    const active = workflows.get(sessionID);
    if (!active) return Promise.resolve();
    active.queue = active.queue.then(async () => {
      if (workflows.get(sessionID) !== active) return;
      await operation(active);
      if (!active.lastFacts.merged || workflows.get(sessionID) !== active) return;
      if (active.idleTimer) clearTimeout(active.idleTimer);
      active.runtime.stop();
      workflows.delete(sessionID);
      await unlink(sessionFile(sessionID, "json")).catch(() => {});
      await trace(sessionID, { event: "workflow.merged", workflowId: active.definition.id });
    }).catch(async (error) => {
      await trace(sessionID, { event: "workflow.error", error: String(error) });
    });
    return active.queue;
  }

  async function cancelIdle(sessionID: string, persist = true): Promise<void> {
    const active = workflows.get(sessionID);
    if (!active) return;
    if (active.idleTimer) clearTimeout(active.idleTimer);
    active.idleTimer = undefined;
    active.idleDeadline = undefined;
    if (persist) await persistWorkflow(sessionID, active, active.runtime.getPersistedSnapshot());
  }

  function armIdle(sessionID: string, active: ActiveWorkflow): void {
    const delay = Math.max(0, (active.idleDeadline ?? Date.now()) - Date.now());
    active.idleTimer = setTimeout(() => {
      active.idleTimer = undefined;
      active.idleDeadline = undefined;
      void enqueueWorkflow(sessionID, async (current) => {
        const facts = await sampleFacts();
        current.lastFacts = facts;
        await trace(sessionID, { event: "idle.elapsed", facts });
        await current.runtime.send({ type: "idle.elapsed", facts });
      });
    }, delay);
  }

  async function scheduleIdle(sessionID: string): Promise<void> {
    const active = workflows.get(sessionID);
    if (!active) return;
    await cancelIdle(sessionID, false);
    active.idleDeadline = Date.now() + 5_000;
    await persistWorkflow(sessionID, active, active.runtime.getPersistedSnapshot());
    armIdle(sessionID, active);
  }

  async function stopWorkflow(sessionID: string): Promise<boolean> {
    const active = workflows.get(sessionID);
    if (!active) return false;
    if (active.idleTimer) clearTimeout(active.idleTimer);
    active.runtime.stop();
    workflows.delete(sessionID);
    await active.queue;
    await unlink(sessionFile(sessionID, "json")).catch(() => {});
    await trace(sessionID, { event: "workflow.stopped", workflowId: active.definition.id });
    return true;
  }

  async function hydrateSession(sessionID: string): Promise<SessionState> {
    const state = sessionStore.get(sessionID)!;
    if (state.hydration) return state.hydration;

    const hydration = (async () => {
      try {
        const response = await v2.session.messages({ sessionID });
        const messages = response.data ?? [];

        // If no messages yet, don't cache — allow re-hydration on next event
        // once the server has loaded the session history.
        if (messages.length === 0) return state;

        for (const part of state.pendingProviderParts.splice(0)) {
          state.providerTools.update(part, state.restoreStartedAt);
        }

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
            state.providerTools.restore(part);
          }
        }

        state.phase = "restored";
        sessionStore.set(sessionID, state);
        await logEvent(client, "dispatch-hydrate", { sessionID, foundInHistory, messageCount: messages.length });
      } catch (error) {
        await logEvent(client, "hydrate-error", { sessionID, error: String(error) });
      }
      return state;
    })();

    state.hydration = hydration.finally(() => {
      state.hydration = undefined;
    });
    return state.hydration;
  }

  async function loadSkills(): Promise<Skill[]> {
    try {
      const response = await v2.app.skills();
      const raws = response.data ?? [];
      const maybeSkills = await Promise.all(raws.map(async (r) => {
        if (r.location === "<built-in>") {
          return null;
        }
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
    deferReply = false,
  ): Promise<boolean> {
    // Load skills on every dispatch so changes to ~/.agents/skills/ take
    // effect without restarting the plugin process.
    const skills = await loadSkills();

    const state = sessionStore.get(sessionID);
    if (!state || state.phase === "pending-restore") {
      await logEvent(client, "dispatch-skip-no-state", { ctx });
      return false;
    }

    await logEvent(client, "dispatch", { sessionID, ctx });

    const matches = skills.flatMap((skill) =>
      skill.triggers.filter((trigger) => matchesTrigger(trigger, ctx)).map((trigger) => ({ skill, trigger }))
    );

    let injected = false;
    for (const { skill, trigger } of matches) {
      if (workflows.has(sessionID) && skill.name === "mojo-complete") continue;
      const action: TriggerAction = trigger.action ?? "inject";

      // reset action: clear firedOnce for this skill — no injection.
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

      if (trigger.worktree) {
        const filePaths = "filePaths" in ctx ? (ctx.filePaths ?? []) : [];
        if (filePaths.length === 0) {
          await logEvent(client, "dispatch-skip", { skill: skill.name, reason: "worktree-no-filepath" });
          continue;
        }
        const worktreeRoot = (await $.cwd(directory)`git rev-parse --show-toplevel`.nothrow().text()).trim();
        const outside = filePaths.find((filePath) => !filePath.startsWith(worktreeRoot + "/") && filePath !== worktreeRoot);
        if (outside) {
          await logEvent(client, "dispatch-skip", { skill: skill.name, reason: "worktree-outside", filePath: outside, worktreeRoot });
          continue;
        }
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
        const reply = !deferReply && ctx.event === "session.idle";
        await injectSkill(client, $, directory, sessionID, skill.content, !reply);
        await trace(sessionID, { event: "skills.injected", source: "legacy", skills: [skill.name], reply });
        injected = true;
      }
    }
    return injected;
  }

  return {
    tool: {
      temper_workflow_stop: tool({
        description: "Stop the active Temper workflow for this session.",
        args: {},
        execute: async (_args, context) => await stopWorkflow(context.sessionID)
          ? "Stopped the active Temper workflow."
          : "No active Temper workflow.",
      }),
    },

    "tool.definition": async (input, output) => {
      if (input.toolID !== "bash") return;
      if (!output.description.includes(BASH_GIT_INSTRUCTIONS)) {
        throw new Error("Expected Bash Git workflow instructions were not found");
      }
      output.description = output.description.replace(BASH_GIT_INSTRUCTIONS, "");
    },

    "experimental.chat.system.transform": async (_input, output) => {
      output.system.splice(0, output.system.length, ...output.system.map(removeSystemGitInstructions));
    },

    "shell.env": async (input, output) => {
      if (input.sessionID) output.env.OPENCODE_SESSION_ID = input.sessionID;
    },

    "command.execute.before": async (input, output) => {
      await cancelIdle(input.sessionID);
      if (await activateWorkflow(input.sessionID, input.command)) {
        output.parts.splice(0);
      }
    },

    "chat.message": async (input, output) => {
      const { sessionID } = input;
      if (output?.parts?.length > 0 && output.parts.every((part) => part.type === "text" && part.synthetic)) return;
      await cancelIdle(sessionID);
      const workflow = await restoreWorkflow(sessionID);
      if (workflow) {
        const facts = await sampleFacts();
        await enqueueWorkflow(sessionID, async (active) => {
          active.lastFacts = facts;
          await trace(sessionID, { event: "external.chat", facts });
          await active.runtime.send({ type: "external.chat", facts });
        });
      }
      if (sessionStore.has(sessionID)) {
        await dispatchEvent(sessionID, { event: "chat.message" });
        return;
      }
      // No prior session.updated — fresh process restore where session.updated. First chat.message means restore
      sessionStore.set(sessionID, {
        phase: "pending-restore",
        firedOnce: new Set(),
        lastInjectionTokens: new Map(),
        providerTools: new ProviderToolQueue(directory),
        pendingProviderParts: [],
        restoreStartedAt: Date.now(),
      });
    },

    "tool.execute.before": async (input, _output) => {
      await logEvent(client, "tool.execute.before", { tool: input.tool });
      await cancelIdle(input.sessionID);
      if (input.tool === "skill" && typeof _output.args?.name === "string") {
        await activateWorkflow(input.sessionID, _output.args.name, true);
      }
      const active = workflows.get(input.sessionID);
      if (active) {
        toolFacts.set(input.callID, { active, facts: await sampleFacts() });
      }
      const command: string = input.tool === "bash" ? (_output.args?.command ?? "") : "";
      await dispatchEvent(input.sessionID, { event: "tool.execute.before", tool: input.tool, command });
    },

    "tool.execute.after": async (input, output) => {
      const command: string = input.tool === "bash" ? (input.args?.command ?? "") : "";
      const filePaths = changedFilePaths(input.tool, input.args, directory);
      await logEvent(client, "tool.execute.after", { tool: input.tool, command, filePaths });
      const pending = toolFacts.get(input.callID);
      toolFacts.delete(input.callID);
      if (pending && workflows.get(input.sessionID) === pending.active) {
        const before = pending.facts;
        const after = await sampleFacts();
        await enqueueWorkflow(input.sessionID, async (active) => {
          active.lastFacts = after;
          await trace(input.sessionID, {
            event: "tool.finished",
            callID: input.callID,
            tool: input.tool,
            command,
            output: output.output,
            exit: output.metadata?.exit,
            before,
            after,
          });
          await active.runtime.send({ type: "tool.finished", tool: input.tool, before, after });
        });
      }
      if (input.tool === "bash" && output.metadata?.exit !== 0) {
        await logEvent(client, "dispatch-skip", { tool: input.tool, command, reason: "command-failed" });
        return;
      }
      await dispatchEvent(input.sessionID, {
        event: "tool.execute.after",
        tool: input.tool,
        command,
        filePaths,
        output,
      });
    },

    event: async ({ event }) => {
      if (event.type === "session.created") {
        const { id: sessionID } = event.properties.info;
        if (sessionStore.has(sessionID)) return;
        // First sesion.created means new session
        sessionStore.set(sessionID, {
          phase: "new",
          firedOnce: new Set(),
          lastInjectionTokens: new Map(),
          providerTools: new ProviderToolQueue(directory),
          pendingProviderParts: [],
          restoreStartedAt: Date.now(),
        });
        await dispatchEvent(sessionID, { event: "session.created" });
      }
      if (event.type === "session.status") {
        const { sessionID } = event.properties;
        if (event.properties.status?.type === "busy") await cancelIdle(sessionID);
        if (!sessionStore.has(sessionID)) return;
        if (sessionStore.get(sessionID)?.phase !== "pending-restore") return;
        await hydrateSession(sessionID);
      }
      if (event.type === "session.idle") {
        const { sessionID } = event.properties;
        if (await restoreWorkflow(sessionID)) await scheduleIdle(sessionID);
        let state = sessionStore.get(sessionID);
        if (state?.phase === "pending-restore") state = await hydrateSession(sessionID);
        if (state?.phase === "pending-restore") state = await hydrateSession(sessionID);
        let injected = false;
        for (const ctx of state?.providerTools.drain() ?? []) {
          injected = await dispatchEvent(sessionID, ctx, true) || injected;
        }
        injected = await dispatchEvent(sessionID, { event: "session.idle" }, true) || injected;
        if (injected) {
          await injectSkill(client, $, directory, sessionID, "Continue with the injected workflow context.", false);
        }
      }
      if (event.type === "message.part.updated") {
        const { part } = event.properties;
        if (part.type !== "tool") return;
        if (part.metadata?.providerExecuted) {
          const key = `${part.sessionID}:${part.messageID}:${part.callID}`;
          const active = workflows.get(part.sessionID);
          if (part.state.status === "running" && active && !providerFacts.has(key)) {
            providerFacts.set(key, { active, facts: await sampleFacts() });
          }
          if (part.state.status === "completed" || part.state.status === "error") {
            const pending = providerFacts.get(key);
            const before = pending && pending.active === active ? pending.facts : active?.lastFacts;
            providerFacts.delete(key);
            const state = sessionStore.get(part.sessionID);
            if (active && before && state?.phase !== "pending-restore" && state?.providerTools.update(part)) {
              const after = await sampleFacts();
              await enqueueWorkflow(part.sessionID, async (current) => {
                current.lastFacts = after;
                await trace(part.sessionID, { event: "tool.finished", callID: part.callID, tool: part.tool, before, after });
                await current.runtime.send({ type: "tool.finished", tool: part.tool, before, after });
              });
              return;
            }
          }
        }
        const state = sessionStore.get(part.sessionID);
        if (!state) return;
        if (state.phase === "pending-restore") {
          state.pendingProviderParts.push(part);
          return;
        }
        if (state.providerTools.update(part)) {
          await logEvent(client, "provider-tool-queued", { sessionID: part.sessionID, callID: part.callID, tool: part.tool });
        }
      }
      if (event.type === "todo.updated") {
        const { sessionID, todos } = event.properties;
        await logEvent(client, "todo.updated", { sessionID, todos });
      }
      if (event.type === "session.deleted") {
        const { id: sessionID } = event.properties.info;
        await stopWorkflow(sessionID);
        sessionStore.delete(sessionID);
      }
    },

    dispose: async () => {
      for (const [sessionID, active] of workflows) {
        if (active.idleTimer) clearTimeout(active.idleTimer);
        active.runtime.stop();
        workflows.delete(sessionID);
      }
      _registeredDirs.delete(directory);
    },
  };
};

if (import.meta.main) {
  const [skillFile, event = "session.created", tool = "", command = ""] = process.argv.slice(2);
  if (skillFile === "--provider-tools") {
    const queue = new ProviderToolQueue(command || process.cwd());
    const parts = JSON.parse(event) as Array<{ restore?: boolean; part: unknown }>;
    const updates = parts.map(({ restore, part }) => {
      if (restore) {
        queue.restore(part);
        return false;
      }
      return queue.update(part);
    });
    console.log(JSON.stringify({ updates, pending: queue.drain() }));
    process.exit(0);
  }
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
      ctx = { event, tool, command }
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
