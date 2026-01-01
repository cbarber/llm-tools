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

* Be succinct. Only provide examples if necessary
* Code must be self-documenting. Comments explain WHY, not WHAT
* Avoid function side effects. Clear input → output
* Avoid deep nesting. Return early
* Be strategic. Plan first, ask questions, then execute
* Challenge assumptions with evidence
* Delete code rather than commenting it out
* **When git commands fail, STOP and ask for help**

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

## Workflow

### init

**Check repository state and pick work:**

```bash
git status --short --branch

bash tools/forge pr status

if command -v bd >/dev/null 2>&1 && [[ -d .beads ]]; then
  echo ""
  echo "📋 Available work:"
  bd ready --limit=5
fi
```

**Next action based on branch state:**
- **On main, clean** → Pick issue, create feature branch
- **On feature branch, PR merged** → Return to main, create new branch
- **On feature branch, PR open** → Continue work or address review feedback
- **On feature branch, no PR** → Complete work and create PR

### commit

Format: `<type>(<scope>): <subject>`

**Types:**
- `feat` - New feature for the user
- `fix` - Bug fix for the user
- `refactor` - Code restructuring without behavior change
- `test` - Adding or updating tests
- `docs` - Documentation changes
- `style` - Formatting, whitespace (no code change)
- `chore` - Build tasks, dependencies (no production code change)

**Body:** 1-2 sentences on WHY (motivation, rationale). Omit if subject is sufficient. Never itemize implementation.

**Footer:** `Authored By: <agent> (<model>)`

**Example:**
```
fix(sandbox): support XDG git config in Linux sandbox

Git reads both ~/.config/git/config (XDG) and ~/.gitconfig (legacy).
Linux sandbox only mounted legacy file, breaking XDG-only users.

Authored By: claude-code (claude-3.7-sonnet)
```

### pull-request

**IMPORTANT:** Use `bash tools/forge` exclusively. Never call `gh` or `tea` directly.

Forge is a unified wrapper for GitHub (gh) and Gitea (tea). Check `bash tools/forge --help` before attempting direct API calls.

**Workflow:**
```bash
# Create PR
git push -u origin <branch>
bash tools/forge pr create --title "..." --body "..."

# View PR with comments
bash tools/forge pr view 123 --comments

# View review comments
bash tools/forge pr review-comments 1
```

**PR body must explain:**
- WHY the change was made (motivation, rationale)
- Link to beads issue if applicable
- What's blocking completion (if using --draft)

**Addressing review feedback:**
```bash
git commit --fixup=<sha>              # Fix specific commit
git rebase --autosquash origin/main   # Squash fixups (non-interactive, NEVER use -i)
git push --force-with-lease
```

See `tools/AGENT_API_AUTH.md` for detailed examples and full forge CLI reference.

### complete

**Work is NOT done until pushed.** Complete ALL steps:

1. File issues for remaining work
2. Run quality gates (tests, linters, builds)
3. Update beads (close/update issues)
4. Push to remote:
   ```bash
   git pull --rebase
   bd sync
   git push --force-with-lease
   git status  # MUST show "up to date with origin"
   ```
   If `--force-with-lease` fails, STOP and ask for help.

5. Provide handoff for next session:
   ```
   Recent Work:
   - Completed issue-id: Summary
   - Created PR #N (status: open/merged)

   Repository State:
   - Branch: <branch> (<commit-hash>)
   - PR Status: <open/merged/none>
   - Main: <commit-hash>

   Next Action:
   - Work on issue-id (specific task)
   OR
   - Pick from: bd ready (3 issues available)

   Context:
   - Critical details only
   ```

## Quick Reference (by frequency)

**Session start:**
- Run `temper init` to check state and pick work
- See [Workflow: init](#init)

**Every commit:**
- Run `temper commit` to review commit format
- See [Workflow: commit](#commit)

**Before PR:**
- Run `temper pr` to review PR workflow
- See [Workflow: pull-request](#pull-request)

**Every session end:**
- Run `temper complete` for completion checklist
- See [Workflow: complete](#complete) and [Landing the Plane](#landing-the-plane)

**As needed:**
- [Development Guidelines](#development-guidelines) - Code style, terseness
- [Beads Integration](#beads-integration) - Task tracking workflow
