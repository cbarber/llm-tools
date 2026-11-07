# AGENTS.md

This file provides guidance to AI agents working in this repository.

## Project Purpose

This repository provides experimental environments for LLM agent tools, MCPs (Model Context Protocols), and supporting tools. Each environment is configured via Nix flakes that construct development shells with pre-loaded configurations and tooling.

## Agent Environment

Running inside `nix develop .#opencode` or `nix develop .#claude-code` provides:

- Sandboxed filesystem access (`IN_AGENT_SANDBOX` is set)
- Pre-configured MCP and PR tooling

Outside the nix shell, only this file is available.

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

## Common Commands

```bash
nix flake check        # Validate flake structure
nix flake update       # Update all inputs
nix develop .#opencode
nix develop .#claude-code
```
