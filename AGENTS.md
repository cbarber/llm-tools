# AGENTS.md

This file provides guidance to AI agents working in this repository.

## Project Purpose

This repository provides experimental environments for LLM agent tools, MCPs (Model Context Protocols), and supporting tools. Each environment is configured via Nix flakes that construct development shells with pre-loaded configurations and tooling.

## Agent Environment

Running inside `nix develop .#opencode` or `nix develop .#claude-code` provides:

- Sandboxed filesystem access (`IN_AGENT_SANDBOX` is set)
- Pre-configured MCP, beads, and PR tooling

Outside the nix shell, only this file is available.

## Repository Structure

```text
llm-tools/
├── flake.nix                    # Root flake exposing all agents
├── agents/
│   ├── claude-code/             # Claude Code shell environment
│   ├── opencode/                # OpenCode shell environment
├── tools/                       # Shared MCP servers and agent tools
└── .opencode/plugin/temper      # OpenCode temper plugin
```

## Architecture

### Agent Environments

Each agent in `agents/` provides an isolated development shell with:

- Agent-specific tooling and configurations
- Shared tools from the `tools/` directory
- Authentication handling (API key + browser auth)
- Auto-launch into the agent environment

### Tool Sharing

The `tools/default.nix` framework allows:

- Common MCP servers across multiple agents
- Custom tool packaging with nix-init
- Shared dependency management
- Reproducible tool versions via flake.lock

## Configuration

Shell-generated files are created on first entry — edit the templates, not the outputs:

| Generated file | Template source |
| --- | --- |
| `opencode.json` | `agents/opencode/setup-config.sh` |
| `.claude/settings.local.json` | `agents/claude-code/settings.template.json` |

## Common Commands

```bash
nix flake check        # Validate flake structure
nix flake update       # Update all inputs
nix develop .#opencode
nix develop .#claude-code
```
