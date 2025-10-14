# llm-tools

Experimental LLM agent environments configured via Nix flakes.

## Usage

```bash
# Remote (recommended)
nix develop github:cbarber/llm-tools#claude-code

# Local
git clone https://github.com/cbarber/llm-tools
cd llm-tools
nix develop .#claude-code
```

## Environment Variables

```bash
# Optional: Set API key (otherwise uses browser auth)
export ANTHROPIC_API_KEY="your-key"

# Optional: Skip auto-launch
export CLAUDE_AUTO_LAUNCH=false
```

## Local Files

On first run, creates `CLAUDE.local.md` from template if no `CLAUDE.md` found in current/parent directories.

## Structure

- `agents/` - Agent-specific environments (claude-code, etc)
- `tools/` - Shared MCP servers and tooling
- `flake.nix` - Root configuration exposing all agents
