#!/usr/bin/env bash
set -euo pipefail

export AGENTS_TEMPLATE="${AGENTS_TEMPLATE}"

# Source .env files if they exist (for API key auth)
[ -f .env ] && source .env
[ -f ~/.config/opencode/.env ] && source ~/.config/opencode/.env

# Note: OpenCode supports API key authentication
# Set ANTHROPIC_API_KEY in .env or ~/.config/opencode/.env
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Note: No ANTHROPIC_API_KEY found. Set it for API key authentication."
  echo "Set ANTHROPIC_API_KEY in .env or ~/.config/opencode/.env"
fi

# Check for agent instruction files in all locations agents search
agents_found=false

# Check current and parent directories (walk up to root)
dir="$(pwd)"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/AGENTS.md" ] || [ -f "$dir/CLAUDE.md" ] || [ -f "$dir/CLAUDE.local.md" ]; then
    agents_found=true
    break
  fi
  dir="$(dirname "$dir")"
done

# Check child directories using find
if [ "$agents_found" = false ] && find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name "CLAUDE.local.md" | head -1 | grep -q .; then
  agents_found=true
fi

# Check global config directory
[ "$agents_found" = false ] && [ -f ~/.config/opencode/AGENTS.md ] && agents_found=true

# Create template if no agent instruction file found anywhere
if [ "$agents_found" = false ]; then
  cp "$AGENTS_TEMPLATE" ./AGENTS.md
  ln -s AGENTS.md CLAUDE.md
  echo "Created AGENTS.md with CLAUDE.md symlink (add AGENTS.md to .gitignore if needed)"
fi

# Setup MCP configuration for detected languages
${SETUP_MCP_SCRIPT}

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
    echo "Beads initialized. Use 'bd ready' to see tasks, 'bd create' to add tasks."
    echo "Set BD_SKIP_SETUP=true to disable auto-initialization."
    if [[ -n "${BD_BRANCH:-}" ]]; then
      echo "Set BD_BRANCH=<branch> to use a different branch for beads commits."
    fi
  fi
fi

# Auto-launch opencode unless disabled
if [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  exec opencode
else
  echo "OpenCode environment ready. Run 'opencode' to start."
  echo "Available commands: cclsp, smart-lint, smart-test, notify, bd"
fi
