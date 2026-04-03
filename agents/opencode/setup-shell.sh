#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"

if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  opencode() { agent-sandbox opencode --port "${OPENCODE_PORT}" "$@"; }
else
  opencode() { command opencode --port "${OPENCODE_PORT}" "$@"; }
fi
export -f opencode

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
export OPENCODE_PORT
export OPENCODE_API="http://127.0.0.1:${OPENCODE_PORT}"
echo "OpenCode API: $OPENCODE_API"

${SETUP_CONFIG_SCRIPT}

if [[ "${PR_POLL_DAEMON:-true}" == "true" ]] && git rev-parse --git-dir >/dev/null 2>&1; then
  PR_POLL_PID_FILE="$(git rev-parse --show-toplevel)/.pr-poll.pid"

  cleanup_pr_poll() {
    [[ -f "$PR_POLL_PID_FILE" ]] || return
    local pid
    pid=$(cat "$PR_POLL_PID_FILE")
    kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null && echo "Stopped PR polling daemon (PID $pid)"
    rm -f "$PR_POLL_PID_FILE"
  }
  trap cleanup_pr_poll EXIT

  REPO_ROOT="$(git rev-parse --show-toplevel)"
  PR_POLL_LOG="$REPO_ROOT/.pr-poll.log"
  "$REPO_ROOT/tools/pr-poll" --daemon >"$PR_POLL_LOG" 2>&1 &
  echo $! >"$PR_POLL_PID_FILE"
  echo "Started PR polling daemon (PID $!, interval: 30s)"
  echo "Logs: $PR_POLL_LOG"
  echo "Disable with: PR_POLL_DAEMON=false"
fi

# Don't exec — background pr-poll daemon must survive the launch.
if [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  opencode
else
  echo "OpenCode environment ready. Run 'opencode' to start."
  if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    echo "Sandbox enabled: use 'agent-sandbox opencode' or just 'opencode' will be sandboxed"
  fi
  echo "Available commands: notify, bd, anvil, pr-poll"
fi
