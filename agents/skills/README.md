# Mojo Skills

Reusable agent skills for mojotech workflows. Each skill is a directory
containing a `SKILL.md` file following the [Agent Skills](https://agentskills.io)
standard, extended with a `triggers` frontmatter block for deterministic
event-driven dispatch.

## Frontmatter Schema

```yaml
---
name: mojo-<name>          # unique skill identifier, required
description: <string>      # human-readable summary, required
once: <bool>               # fire at most once per session (default: false)
triggers:                  # list of event bindings (empty = manual-only)
  - event: <string>        # OpenCode event name verbatim
    tool: <regex>          # match tool name (tool events only)
    command: <regex>       # match bash command string (bash tool only)
    when: <shell>          # shell guard: skip trigger if exits nonzero
    blocking: <bool>       # halt the tool on nonzero exit (tool.execute.before only)
---
```

### Fields

**`once`** (root) — When true, the skill fires at most once per session
regardless of which trigger activates it.

**`triggers[].event`** — The OpenCode plugin event name verbatim. Maps to
named hooks (`tool.execute.before`, `tool.execute.after`, `chat.message`) or
the generic `event` handler (`session.created`, `session.idle`, etc.).

**`triggers[].tool`** — Regex matched against `input.tool`. Only meaningful
for tool events. Absent means match all tools.

**`triggers[].command`** — Regex matched against the bash command string.
Only meaningful when `tool` matches `bash`. The match is unanchored (substring).
For `tool.execute.before` the command is in `output.args.command`; for
`tool.execute.after` it is in `input.args.command`.

**`triggers[].when`** — Shell expression evaluated at fire time. The trigger
is skipped if the expression exits nonzero. Used for state-dependent skills
where the event alone is insufficient to decide whether to inject.

**`triggers[].blocking`** — Only valid on `tool.execute.before` triggers.
When true, the skill's shell block is executed and the tool call is halted if
it exits nonzero. The skill body is not injected into context on block.

## Skill Discovery

Skills are loaded from these paths in priority order:

1. `.agents/skills/` — project-local skills (committed to the repo)
2. `~/.agents/skills/` — user-global skills (synced from this repo on shell entry)

The temper CLI and the OpenCode plugin both walk these paths. The plugin
additionally uses `client.app.skills()` which resolves all paths OpenCode
itself discovers.

## Naming

All mojotech skills use the `mojo-` prefix to avoid collisions with
third-party skills installed by the user.
