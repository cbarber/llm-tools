#!/usr/bin/env bash
set -euo pipefail

export CLAUDE_TEMPLATE="${CLAUDE_TEMPLATE}"
export SETTINGS_TEMPLATE="${SETTINGS_TEMPLATE}"

# Source .env files if they exist (for API key auth)
[ -f .env ] && source .env
[ -f ~/.config/claude/.env ] && source ~/.config/claude/.env

# Note: Claude Code supports both browser auth and API key
# If no API key is set, it will attempt browser authentication
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Note: No ANTHROPIC_API_KEY found. Claude Code will use browser authentication."
  echo "If you prefer API key auth, set ANTHROPIC_API_KEY in .env or ~/.config/claude/.env"
fi

# Check for CLAUDE files in all locations Claude searches
claude_found=false

# Check current and parent directories (walk up to root)
dir="$(pwd)"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/CLAUDE.md" ] || [ -f "$dir/CLAUDE.local.md" ]; then
    claude_found=true
    break
  fi
  dir="$(dirname "$dir")"
done

# Check child directories using find
if [ "$claude_found" = false ] && find . -name "CLAUDE.md" -o -name "CLAUDE.local.md" | head -1 | grep -q .; then
  claude_found=true
fi

# Check home directory
[ "$claude_found" = false ] && [ -f ~/.claude/CLAUDE.md ] && claude_found=true

# Create template if no CLAUDE file found anywhere
if [ "$claude_found" = false ]; then
  cp "$CLAUDE_TEMPLATE" ./CLAUDE.local.md
  echo "Created CLAUDE.local.md from template (add to .gitignore)"
fi

# Setup MCP configuration for detected languages
${SETUP_MCP_SCRIPT}

# Setup Claude Code hooks configuration
${SETUP_SETTINGS_SCRIPT}

# Setup beads task tracking (optional, skippable with BD_SKIP_SETUP=true)
if [[ ! -d ".beads" && "${BD_SKIP_SETUP:-}" != "true" ]]; then
  echo "Initializing beads for task tracking..."
  
  # Support custom branch via BD_BRANCH (useful for protected branches)
  branch_arg=""
  if [[ -n "${BD_BRANCH:-}" ]]; then
    branch_arg="--branch ${BD_BRANCH}"
    echo "  Using branch: ${BD_BRANCH}"
  fi
  
  if bd init --quiet $branch_arg 2>/dev/null; then
    bd setup claude --quiet 2>/dev/null || true
    echo "Beads initialized. Use 'bd ready' to see tasks, 'bd create' to add tasks."
    echo "Set BD_SKIP_SETUP=true to disable auto-initialization."
    if [[ -n "${BD_BRANCH:-}" ]]; then
      echo "Set BD_BRANCH=<branch> to use a different branch for beads commits."
    fi
  fi
fi

# Auto-launch claude unless disabled
if [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  exec claude
else
  echo "Claude Code environment ready. Run 'claude' to start."
  echo "Available commands: smart-lint, smart-test, notify, cclsp, bd"
fi
