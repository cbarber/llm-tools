# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository provides experimental environments for LLM agent tools, MCPs (Model Context Protocols), and supporting tools. Each environment is configured via Nix flakes that construct development shells with pre-loaded configurations and tooling.

## Configuration Templates

Agent shells auto-generate config files on first run via `agents/*/setup-*.sh` scripts. To update default configurations:
- Edit templates in setup scripts (e.g., `agents/opencode/setup-mcp.sh`)
- NOT the generated files (opencode.json, .mcp.json, cclsp.json)

### User-Specific AGENTS.md Templates

Create personalized templates in `agents/templates/${USER}.md` to customize agent instructions. The shell automatically selects:

1. `agents/templates/${USER}.md` (if exists)
2. `agents/templates/default.md` (fallback)

Example:
```bash
cp agents/templates/default.md agents/templates/cbarber.md
# Edit with personal preferences
```

See `agents/templates/README.md` for details.

## Development Guidelines

- Be terse. Only provide examples if actually necessary for clarification
- Avoid comments. When in doubt, name a variable or extract a function.
- Avoid function side effects. Functions are always better as a clear input and output.
- Strive for logical function organization. "clean code" and "one large function" are too dogmatic
- Avoid deep block nesting. Prefer conditions that return early.
- Do not update code through shell commands. When you're stuck, ask me to help with changes.
- Be strategic. Formulate a plan, consider all options, and ask questions before jumping to solutions.
- Remember neither you nor I are a god. Do not break your arm patting me on the back. Just continue working.
- Challenge my assumptions with compelling evidence.
- You are always on a branch. Delete code rather than versioning code.

## Repository Structure

```
llm-tools/
├── flake.nix                 # Root flake exposing all agents
├── flake.lock               # Version pinning for reproducible builds
├── agents/
│   └── claude-code/
│       ├── default.nix      # Claude Code shell environment
│       └── claude.md.template  # Shared CLAUDE.md template
├── tools/
│   └── default.nix         # Framework for shared MCP and agent tools
└── prompt                   # Original development guidelines
```

## Usage

### Remote Usage (Recommended)

```bash
# Enter Claude Code environment from any directory
nix develop github:cbarber/llm-tools#claude-code

# This will:
# 1. Check for authentication (API key or browser)
# 2. Search for existing CLAUDE.md files in precedence order
# 3. Create CLAUDE.local.md template if no CLAUDE files found
# 4. Launch Claude Code automatically
```

### Local Development

```bash
# Clone and enter development mode
git clone https://github.com/cbarber/llm-tools
cd llm-tools
nix develop .#claude-code

# Validate flake structure
nix flake check

# Update dependencies
nix flake update
```

## Architecture

### Agent Environments

Each agent in `agents/` provides an isolated development shell with:

- Agent-specific tooling and configurations
- Shared tools from the `tools/` directory
- Authentication handling (API key + browser auth)
- Automatic CLAUDE.md template provisioning
- Auto-launch into the agent environment

### Tool Sharing

The `tools/default.nix` framework allows:

- Common MCP servers across multiple agents
- Custom tool packaging with nix-init
- Shared dependency management
- Reproducible tool versions via flake.lock

### CLAUDE.md Precedence

The shell checks for CLAUDE files in this order:

1. Current directory: `CLAUDE.md` or `CLAUDE.local.md`
2. Parent directories: Walk up tree checking each level
3. Child directories: Recursive search (on-demand by Claude)
4. Home directory: `~/.claude/CLAUDE.md`

If none found, creates `CLAUDE.local.md` from template.

## Common Commands

```bash
# Test flake validation
nix flake check

# Build specific agent
nix build .#claude-code

# Enter specific environment
nix develop .#claude-code

# Update all inputs
nix flake update

# Package new tools with nix-init
nix-shell -p nix-init --run "nix-init"
```

## Beads Integration

Beads (bd) provides task tracking and memory management. Auto-initializes on first shell entry (disable with `BD_SKIP_SETUP=true`).

**Agent Integration:**
- **Claude Code**: Hooks auto-inject `bd prime` context on session start/compaction
- **OpenCode**: [opencode-beads](https://github.com/joshuadavidthomas/opencode-beads) plugin (v0.3.0) provides context injection and `/bd-*` commands
  - Pinned version in opencode.json: `"plugin": ["opencode-beads@0.3.0"]`
  - OpenCode auto-installs to `~/.cache/opencode/node_modules/` on first use
  - No project pollution - installed globally per-user

**Branch Configuration:**

For protected branches, use a separate sync branch:
```bash
export BD_BRANCH=beads-sync  # Commits to beads-sync via git worktrees
```

Without `BD_BRANCH`, commits go to current branch.

**Essential Commands:**

```bash
bd ready              # Show available work
bd create "Task" -p 1 # Create task
bd show <id>          # View details
bd sync               # Sync to git
```

## Authentication

Claude Code supports two authentication methods:

- **Browser authentication** (default for subscription users)
- **API key authentication** via `ANTHROPIC_API_KEY`

The shell sources API keys from:

1. Current directory `.env` file
2. `~/.config/claude/.env` file
3. Environment variables

If no API key found, uses browser authentication automatically.

## Tool Integration

Use `nix-init` to package new tools:

1. Create tool directory in `tools/`
2. Run `nix-init` to generate package.nix
3. Import in `tools/default.nix`
4. Add to agent buildInputs as needed

This allows shared MCP servers and custom tooling across multiple agent environments.


## Landing the Plane (Session Completion)

**When ending a work session**, complete ALL steps. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push --force-with-lease
   git status  # MUST show "up to date with origin"
   ```
   If `git push --force-with-lease` fails, STOP and request manual intervention.

5. **Clean up** - Remove debug code, temp files.
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Create next session prompt in this exact format:
   ```
   Recent Work:
   - Completed issue-id: Summary of changes

   Repository State:
   - Branch: <branch-name> (<commit-hash>)
   - Beads: X closed, Y ready issues

   Context:
   - Important details for continuity
   ```
   This prompt should be ready to paste into the next AI session.

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If force-with-lease fails, abort and request help
