#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"

if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  sandboxed-opencode() { agent-sandbox opencode --port "${OPENCODE_PORT}" --dangerously-skip-permissions "$@"; }
  export -f sandboxed-opencode
fi

export AGENT_ENV_CONFIG_DIR="${HOME}/.config/opencode"
source "${TOOLS_DIR}/setup-shared-shell.sh"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Note: No ANTHROPIC_API_KEY found. Set it in .env or ${AGENT_ENV_CONFIG_DIR}/.env"
fi

if [[ -z "${OPENCODE_PORT:-}" ]]; then
  while true; do
    OPENCODE_PORT=$(shuf -i 40000-50000 -n 1)
    ss -tln 2>/dev/null | grep -q ":${OPENCODE_PORT} " || break
  done
fi
export OPENCODE_ENABLE_EXA=1
export OPENCODE_PORT
export OPENCODE_API="http://127.0.0.1:${OPENCODE_PORT}"
echo "OpenCode API: $OPENCODE_API"

${SETUP_CONFIG_SCRIPT}

if [[ "${PR_POLL_DAEMON:-true}" == "true" ]] && [[ -n "${OPENCODE_SESSION_ID:-}" ]] && git rev-parse --git-dir >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  REPO_HASH=$(echo "$REPO_ROOT" | sed 's#/#-#g' | sed 's#^-##')
  STATE_DIR="${HOME}/.local/share/nixsmith/pr-poll/${REPO_HASH}"
  mkdir -p "$STATE_DIR"

  PID_FILE="${STATE_DIR}/daemon.pid"
  LOG_FILE="${STATE_DIR}/daemon.log"

  if [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    nohup bash "${TOOLS_DIR}/pr-poll" --daemon >>"$LOG_FILE" 2>&1 &
    echo "Started PR polling daemon (session: ${OPENCODE_SESSION_ID})"
    echo "Logs: $LOG_FILE"
  fi
fi

# Don't exec — background pr-poll daemon must survive the launch.
if [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  if declare -f sandboxed-opencode >/dev/null 2>&1; then
    sandboxed-opencode
  else
    command opencode --port "${OPENCODE_PORT}"
  fi
else
  echo "OpenCode environment ready."
  if declare -f sandboxed-opencode >/dev/null 2>&1; then
    echo "Run 'sandboxed-opencode' to start (sandboxed + API port configured)."
  else
    echo "Run 'opencode' to start. Warning: sandbox is not available."
  fi
  echo "Available commands: notify, bd, anvil, pr-poll"
fi
