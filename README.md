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
- cclsp MCP server for LSP integration
- Auto-detected language servers (Nix via nil)
- Shared tooling (smart-lint, smart-test, notify)

## Configuration

Auto-generates on first run if missing:
- `.mcp.json` / `opencode.json` - MCP server configuration
- `cclsp.json` - Language server mappings for detected project languages

Set `ANTHROPIC_API_KEY` in `.env` for API auth. Set `AUTO_LAUNCH=false` to skip auto-launch.

## Structure

- `agents/` - Agent environments (claude-code, opencode)
- `tools/` - Shared MCP servers (cclsp) and scripts
- `flake.nix` - Root configuration
