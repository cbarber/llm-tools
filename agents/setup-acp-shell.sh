#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=../tools/setup-shared-aliases.sh
source "${TOOLS_DIR}/setup-shared-aliases.sh"

# shellcheck source=../tools/setup-shared-shell.sh
source "${TOOLS_DIR}/setup-shared-shell.sh"

run-acp-agent() {
  if [[ -z "${IN_AGENT_SANDBOX:-}" ]] && [[ "${AGENT_SANDBOX:-true}" == "true" ]] && [[ -x "$AGENT_SANDBOX_SCRIPT" ]]; then
    agent-sandbox bash -c 'exec toad acp "$ACP_AGENT_COMMAND"'
    return
  fi
  toad acp "$ACP_AGENT_COMMAND"
}
export -f run-acp-agent

if [[ -n "${IN_AGENT_SANDBOX:-}" ]]; then
  exec run-acp-agent
elif [[ "${AUTO_LAUNCH:-true}" == "true" ]]; then
  run-acp-agent "$@"
else
  echo "ACP agent environment ready. Run 'run-acp-agent' to start."
fi
