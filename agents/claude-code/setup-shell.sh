#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"


# Resolve workflow file: explicit env > ~/.config/nixsmith/workflow.md > default
# Relative AGENTS_TEMPLATE is resolved against AGENTS_TEMPLATES_DIR
select_workflow() {
  if [[ -n "${AGENTS_TEMPLATE:-}" ]]; then
    if [[ "${AGENTS_TEMPLATE}" != /* ]]; then
      echo "${AGENTS_TEMPLATES_DIR}/${AGENTS_TEMPLATE}"
    else
      echo "${AGENTS_TEMPLATE}"
    fi
    return
  fi
  [[ -f ~/.config/nixsmith/workflow.md ]] && echo ~/.config/nixsmith/workflow.md && return
  echo "${AGENTS_TEMPLATE_DEFAULT}"
}

export AGENTS_TEMPLATE="$(select_workflow)"
export SETTINGS_TEMPLATE="${SETTINGS_TEMPLATE}"

if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  claude() { agent-sandbox claude --append-system-prompt-file "${AGENTS_TEMPLATE}" "$@"; }
else
  claude() { command claude --append-system-prompt-file "${AGENTS_TEMPLATE}" "$@"; }
fi
export -f claude

# Source .env files if they exist (for API key auth)
if [ -f .env ]; then
  source .env
fi
CLAUDE_ENV="${HOME}/.config/claude/.env"
if [ -f "$CLAUDE_ENV" ]; then
  source "$CLAUDE_ENV"
fi

# Note: Claude Code supports both browser auth and API key
# If no API key is set, it will attempt browser authentication
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "Note: No ANTHROPIC_API_KEY found. Claude Code will use browser authentication."
  echo "If you prefer API key auth, set ANTHROPIC_API_KEY in .env or ~/.config/claude/.env"
fi

# Setup MCP configuration for detected languages
${SETUP_MCP_SCRIPT}

# Setup Claude Code hooks configuration
${SETUP_SETTINGS_SCRIPT}

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
    bd setup claude --quiet 2>/dev/null || true
    
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

# Auto-launch claude unless disabled
# Skip if already in sandbox (prevent infinite loop)
if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Already in sandbox, starting Claude Code directly..."
  exec claude
elif [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  # Use sandbox if enabled (default: enabled)
  if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    echo "Launching Claude Code in sandbox (disable with AGENT_SANDBOX=false)..."
    exec "$AGENT_SANDBOX_SCRIPT" claude
  else
    exec claude
  fi
else
  echo "Claude Code environment ready. Run 'claude' to start."
  if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    echo "Sandbox enabled: use 'agent-sandbox claude' or just 'claude' will be sandboxed"
  fi
  echo "Available commands: smart-lint, smart-test, notify, cclsp, bd"
fi
