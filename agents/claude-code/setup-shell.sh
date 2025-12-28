#!/usr/bin/env bash
set -euo pipefail

# Select user-specific template with fallback to default
# Priority: agents/templates/${USER}.md -> agents/templates/default.md
select_template() {
  local user_template="${AGENTS_TEMPLATES_DIR}/${USER}.md"
  if [ -f "$user_template" ]; then
    echo "$user_template"
  else
    echo "$AGENTS_TEMPLATE_DEFAULT"
  fi
}

export AGENTS_TEMPLATE="$(select_template)"
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

# Check home directory
[ "$agents_found" = false ] && [ -f ~/.claude/CLAUDE.md ] && agents_found=true

# Create template if no agent instruction file found anywhere
if [ "$agents_found" = false ]; then
  cp "$AGENTS_TEMPLATE" ./AGENTS.md
  ln -s AGENTS.md CLAUDE.md
  echo "Created AGENTS.md with CLAUDE.md symlink (add AGENTS.md to .gitignore if needed)"
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
    
    # Start daemon with auto-commit if using a separate branch
    if [[ -n "${BD_BRANCH:-}" ]]; then
      bd daemon --start --auto-commit 2>/dev/null || true
      echo "Beads initialized with auto-commit to branch: ${BD_BRANCH}"
    else
      echo "Beads initialized. Use 'bd ready' to see tasks, 'bd create' to add tasks."
    fi
    
    echo "Set BD_SKIP_SETUP=true to disable auto-initialization."
  fi
fi

# Auto-launch claude unless disabled
if [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  exec claude
else
  echo "Claude Code environment ready. Run 'claude' to start."
  echo "Available commands: smart-lint, smart-test, notify, cclsp, bd"
fi
