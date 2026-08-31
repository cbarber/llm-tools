#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../tools/setup-shared-aliases.sh
source "${TOOLS_DIR}/setup-shared-aliases.sh"

# shellcheck source=../tools/setup-shared-shell.sh
source "${TOOLS_DIR}/setup-shared-shell.sh"

toad_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/toad"
mkdir -p "$AGENT_ENV_CONFIG_DIR" "$toad_config_dir"
export SANDBOX_EXTRA_RW="${SANDBOX_EXTRA_RW:+$SANDBOX_EXTRA_RW:}$toad_config_dir"
unset toad_config_dir

run-acp-agent() {
  if [[ -z "${IN_AGENT_SANDBOX:-}" ]] && [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    agent-sandbox bash -c 'exec toad acp "$ACP_AGENT_COMMAND"'
    return
  fi
  toad acp "$ACP_AGENT_COMMAND"
}
export -f run-acp-agent

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  run-acp-agent
elif [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  run-acp-agent "$@"
else
  echo "ACP agent environment ready. Run 'run-acp-agent' to start."
fi
