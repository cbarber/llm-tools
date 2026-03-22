# llm-tools

Experimental LLM agent environments configured via Nix flakes.

## Agents

### Claude Code

```bash
nix develop github:cbarber/llm-tools#claude-code
```

### OpenCode

```bash
nix develop github:cbarber/llm-tools#opencode
```

Both agents include:

- Sandboxed execution (bubblewrap on Linux, sandbox-exec on macOS)
- cclsp MCP server for LSP integration
- Auto-detected language servers (Nix via nil)
- Beads task management with git integration
- Shared tooling (notify)

## Sandboxing

Agents run in a deny-by-default sandbox (bubblewrap on Linux, sandbox-exec on macOS). Access is explicitly granted per category:

- **Read-write**: Project directory, temp workspace, agent config/cache dirs
- **Read-only**: OS directories, `/nix`, git identity files (`~/.gitconfig`, `~/.ssh/known_hosts`)
- **Denied**: `~/.ssh` keys, `~/.gnupg`, rest of home directory, other projects

See [`tools/SANDBOX.md`](tools/SANDBOX.md) for platform details and environment variables.

## Task Management

Beads provides git-backed issue tracking:

```bash
bd ready                    # Show available work
bd create "task" -p 2       # Create issue (P0-P4)
bd close <id>               # Complete work
bd sync                     # Sync with git
```

Auto-initializes in agent shells.

## Configuration

Auto-generates on first run if missing:

- `.mcp.json` / `opencode.json` - MCP server configuration
- `cclsp.json` - Language server mappings for detected project languages

Set `ANTHROPIC_API_KEY` in `.env` for API auth. Set `AUTO_LAUNCH=false` to skip auto-launch.

## Structure

- `agents/` - Agent environments (claude-code, opencode)
- `tools/` - Shared MCP servers (cclsp), scripts, and sandbox
- `flake.nix` - Root configuration
