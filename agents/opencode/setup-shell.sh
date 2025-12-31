#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"

# Alias opencode to run in sandbox when AGENT_SANDBOX is enabled
if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  opencode() {
    agent-sandbox opencode "$@"
  }
  export -f opencode
fi

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

# Fix beads git hooks for NixOS if needed (even in existing repos)
if [[ -d ".beads" && -d ".git/hooks" ]]; then
  # Check if any beads hook has broken shebang
  for hook in .git/hooks/pre-commit .git/hooks/post-checkout .git/hooks/post-merge .git/hooks/pre-push; do
    if [[ -f "$hook" ]] && head -1 "$hook" | grep -q "^#!/bin/sh"; then
      "${TOOLS_DIR}/fix-beads-hooks" . 2>/dev/null || true
      break
    fi
  done
fi

# Setup beads task tracking (optional, skippable with BD_SKIP_SETUP=true)
if [[ ! -d ".beads" && "${BD_SKIP_SETUP:-}" != "true" ]]; then
  echo "Initializing beads for task tracking..."
  
  # Support custom branch via BD_BRANCH (useful for protected branches)
  branch_arg=""
  if [[ -n "${BD_BRANCH:-}" ]]; then
    branch_arg="--branch ${BD_BRANCH}"
    echo "  Using branch: ${BD_BRANCH}"
    # Export BD_BRANCH so daemon can see it when started later
    export BD_BRANCH
  fi
  
  if bd init --quiet $branch_arg 2>/dev/null; then
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

# Run agent setup (SSH keys + API tokens)
# Scripts check if setup is needed and exit early if not
if [[ "${SKIP_AGENT_SETUP:-}" != "true" ]] && git remote -v &>/dev/null 2>&1; then
  "${TOOLS_DIR}/setup-agent-keys.sh" || {
    echo "Error: SSH key setup failed" >&2
    exit 1
  }
  "${TOOLS_DIR}/setup-agent-api-tokens.sh" || {
    echo "Error: API token setup failed" >&2
    exit 1
  }
fi

# Auto-launch opencode unless disabled
# Skip if already in sandbox (prevent infinite loop)
if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Already in sandbox, starting OpenCode directly..."
  exec opencode
elif [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  # Use sandbox if enabled (default: enabled)
  if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    echo "Launching OpenCode in sandbox (disable with AGENT_SANDBOX=false)..."
    exec "$AGENT_SANDBOX_SCRIPT" opencode
  else
    exec opencode
  fi
else
  echo "OpenCode environment ready. Run 'opencode' to start."
  if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    echo "Sandbox enabled: use 'agent-sandbox opencode' or just 'opencode' will be sandboxed"
  fi
  echo "Available commands: cclsp, smart-lint, smart-test, notify, bd"
fi
