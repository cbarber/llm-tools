#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"

export AGENT_ENV_CONFIG_DIR="${HOME}/.config/claude"
# bd setup claude configures beads hooks for Claude Code's hook format.
export BEADS_POST_INIT="bd setup claude --quiet 2>/dev/null || true"
source "${TOOLS_DIR}/setup-shared-shell.sh"

# Claude Code supports browser auth as fallback when no API key is set.
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Note: No ANTHROPIC_API_KEY found. Claude Code will use browser authentication."
  echo "If you prefer API key auth, set ANTHROPIC_API_KEY in .env or ${AGENT_ENV_CONFIG_DIR}/.env"
fi

export SETTINGS_TEMPLATE="${SETTINGS_TEMPLATE}"

if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  claude() { agent-sandbox claude --append-system-prompt-file "${AGENTS_TEMPLATE}" "$@"; }
else
  claude() { command claude --append-system-prompt-file "${AGENTS_TEMPLATE}" "$@"; }
fi
export -f claude

${SETUP_MCP_SCRIPT}
${SETUP_SETTINGS_SCRIPT}

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Already in sandbox, starting Claude Code directly..."
  exec claude
elif [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
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
