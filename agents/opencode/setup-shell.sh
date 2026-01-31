#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"

# Alias opencode to run in sandbox when AGENT_SANDBOX is enabled
# Always pass --port to ensure API is available on known port
if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  opencode() {
    agent-sandbox opencode --port "${OPENCODE_PORT}" "$@"
  }
  export -f opencode
else
  opencode() {
    command opencode --port "${OPENCODE_PORT}" "$@"
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

# Allocate random port for OpenCode API server
# OpenCode accepts --port flag to specify server port
if [ -z "${OPENCODE_PORT:-}" ]; then
  # Find random open port between 40000-50000
  while true; do
    OPENCODE_PORT=$(shuf -i 40000-50000 -n 1)
    if ! ss -tln 2>/dev/null | grep -q ":${OPENCODE_PORT} "; then
      break
    fi
  done
fi

export OPENCODE_PORT
export OPENCODE_API="http://127.0.0.1:${OPENCODE_PORT}"
echo "OpenCode API: $OPENCODE_API"

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
  
  branch_arg=""
  if [[ -n "${BD_BRANCH:-}" ]]; then
    branch_arg="--branch ${BD_BRANCH}"
  fi
  
  if bd init --quiet $branch_arg 2>/dev/null; then
    if [[ -n "${BD_BRANCH:-}" ]]; then
      sed -i "s/^# sync-branch:.*/sync-branch: \"${BD_BRANCH}\"/" .beads/config.yaml
      echo "Beads initialized with auto-commit to branch: ${BD_BRANCH}"
    else
      echo "Beads initialized. Use 'bd ready' to see tasks, 'bd create' to add tasks."
    fi
    echo "Set BD_SKIP_SETUP=true to disable auto-initialization."
  fi
fi

# Start daemon if sync-branch is configured
if [[ -d ".beads" && -f ".beads/config.yaml" && "${BD_SKIP_SETUP:-}" != "true" ]]; then
  if grep -q "^sync-branch:" .beads/config.yaml 2>/dev/null; then
    if ! bd daemon --status --json 2>/dev/null | jq -e '.running' >/dev/null 2>&1; then
      bd daemon --start --auto-commit 2>/dev/null || true
      echo "Started beads daemon with auto-commit"
    fi
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

# Start PR polling daemon if in git repo
# Daemon monitors PR status and notifies on changes
if [[ "${PR_POLL_DAEMON:-true}" == "true" ]] && git rev-parse --git-dir >/dev/null 2>&1; then
  PR_POLL_PID_FILE="$(git rev-parse --show-toplevel)/.pr-poll.pid"
  
  # Cleanup function to kill daemon on shell exit
  cleanup_pr_poll() {
    if [[ -f "$PR_POLL_PID_FILE" ]]; then
      local pid=$(cat "$PR_POLL_PID_FILE")
      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "Stopped PR polling daemon (PID $pid)"
      fi
      rm -f "$PR_POLL_PID_FILE"
    fi
  }
  trap cleanup_pr_poll EXIT
  
  # Start daemon in background with logging
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PR_POLL_LOG="$REPO_ROOT/.pr-poll.log"
  "$REPO_ROOT/tools/pr-poll" --daemon > "$PR_POLL_LOG" 2>&1 &
  echo $! > "$PR_POLL_PID_FILE"
  echo "Started PR polling daemon (PID $!, interval: 30s)"
  echo "Logs: $PR_POLL_LOG"
  echo "Disable with: PR_POLL_DAEMON=false"
fi

# Auto-launch opencode unless disabled
# Skip if already in sandbox (prevent infinite loop)
# Note: Don't use exec so background daemon (pr-poll) can survive
if [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  opencode
else
  echo "OpenCode environment ready. Run 'opencode' to start."
  if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    echo "Sandbox enabled: use 'agent-sandbox opencode' or just 'opencode' will be sandboxed"
  fi
  echo "Available commands: cclsp, smart-lint, smart-test, notify, bd, anvil, pr-poll"
fi
