#!/usr/bin/env bash
set -euo pipefail

source "${TOOLS_DIR}/setup-shared-aliases.sh"

export AGENT_ENV_CONFIG_DIR="${HOME}/.config/claude"
source "${TOOLS_DIR}/setup-shared-shell.sh"

# Claude Code supports browser auth as fallback when no API key is set.
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Note: No ANTHROPIC_API_KEY found. Claude Code will use browser authentication."
  echo "If you prefer API key auth, set ANTHROPIC_API_KEY in .env or ${AGENT_ENV_CONFIG_DIR}/.env"
fi

export SETTINGS_TEMPLATE="${SETTINGS_TEMPLATE}"

# Deliberately not named `claude`: bash exports functions into the sandbox as
# BASH_FUNC_<name>%%, so a wrapper shadowing the binary would re-enter
# agent-sandbox there and the nested launch dies in bubblewrap, which cannot map
# uids from the user namespace fence already created. Matches sandboxed-opencode.
if [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
  # Context renewal drives this pane through Herdr from outside the sandbox,
  # which never gets the socket; the helper exits with the process PID.
  # Herdr comes from a fixed path root controls, never from PATH, which holds
  # sandbox-writable directories; HERDR_RENEW_HERDR in the launching shell
  # overrides it under the same check. Detached with builtins alone.
  start-renewal-helper() {
    [[ -z "${IN_AGENT_SANDBOX:-}" && -n "${HERDR_SOCKET_PATH:-}" && -n "${HERDR_PANE_ID:-}" && -x "${HERDR_RENEW_PATH:-}" ]] || return 0
    # Run from /, so no relative path resolves into the sandbox-writable checkout.
    local herdr checkout=$PWD
    herdr=$(cd / && "$HERDR_RENEW_PATH" --resolve-herdr "${HERDR_RENEW_HERDR:-/run/current-system/sw/bin/herdr}") || return 0
    ( (
      trap '' HUP
      cd / || exit
      exec "$HERDR_RENEW_PATH" --watch "$1" --herdr "$herdr" --cwd "$checkout"
    ) </dev/null >/dev/null 2>&1 &)
  }
  sandboxed-claude() {
    (
      start-renewal-helper "$BASHPID"
      # agent-sandbox is a function, which exec would look up on PATH instead.
      exec "$AGENT_SANDBOX_SCRIPT" claude "$@"
    )
  }
  export -f start-renewal-helper sandboxed-claude
  # Herdr does not detect the sandboxed process as Claude without it, as for
  # sandboxed-opencode.
  [[ -n "${HERDR_PANE_ID:-}" ]] && export HERDR_AGENT=claude
fi

${SETUP_SETTINGS_SCRIPT}

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  echo "Already in sandbox, starting Claude Code directly..."
  exec claude
elif [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  if declare -f sandboxed-claude >/dev/null 2>&1; then
    echo "Launching Claude Code in sandbox (disable with AGENT_SANDBOX=false)..."
    # Equivalent to sandboxed-claude, but exec'able: a function cannot be exec'd.
    start-renewal-helper "$$"
    exec "$AGENT_SANDBOX_SCRIPT" claude --allow-dangerously-skip-permissions --dangerously-skip-permissions --add-dir "$HOME/.agents/skills/"
  else
    exec claude
  fi
else
  echo "Claude Code environment ready."
  if declare -f sandboxed-claude >/dev/null 2>&1; then
    echo "Run 'sandboxed-claude' to start (sandboxed)."
  else
    echo "Run 'claude' to start. Warning: sandbox is not available."
  fi
  echo "Available commands: notify, bd"
fi
