# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repository provides experimental environments for LLM agent tools, MCPs (Model Context Protocols), and supporting tools. Each environment is configured via Nix flakes that construct development shells with pre-loaded configurations and tooling.

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

