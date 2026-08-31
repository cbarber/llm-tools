#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${IN_AGENT_SANDBOX:-}" ]]; then
  if [[ ! -x "${AGENT_SANDBOX_SCRIPT:-}" ]]; then
    echo "test-acp-startup: enter the cursor-cli Nix shell first" >&2
    exit 1
  fi
  exec "$AGENT_SANDBOX_SCRIPT" bash "$0" "$@"
fi

if [[ -z "${ACP_AGENT_COMMAND:-}" ]]; then
  echo "test-acp-startup: ACP_AGENT_COMMAND is not set" >&2
  exit 1
fi

timeout="${ACP_STARTUP_TIMEOUT:-20}"
rpc_response=""
debug_dir="${ACP_STARTUP_DEBUG_DIR:-$(mktemp -d /tmp/cursor-acp-startup.XXXXXX)}"
agent_command="$ACP_AGENT_COMMAND"

echo "ACP startup diagnostics"
echo "  sandbox: ${IN_AGENT_SANDBOX:-unset}"
echo "  cwd: $PWD"
echo "  command: $ACP_AGENT_COMMAND"
echo "  debug directory: $debug_dir"
echo "  cursor-agent: $(command -v cursor-agent)"
echo "  cursor-agent version: $(cursor-agent --version)"
for variable in CURSOR_API_KEY HTTP_PROXY HTTPS_PROXY NODE_EXTRA_CA_CERTS SSL_CERT_FILE; do
  if [[ -n "${!variable:-}" ]]; then
    echo "  $variable: set"
  else
    echo "  $variable: unset"
  fi
done

cursor_config="${AGENT_ENV_CONFIG_DIR:-$HOME/.cursor}/cli-config.json"
echo "  Cursor config: $cursor_config"
if [[ -r "$cursor_config" ]]; then
  jq -c '{version, network, hasAuthInfo: has("authInfo"), serverHttp2Config: .serverConfigCache.serverHttp2Config}' "$cursor_config"
else
  echo "  Cursor config is not readable"
fi

echo "Sandboxed Cursor status:"
cursor-agent status || true
echo "Sandboxed Cursor about:"
cursor-agent about --format json || true

if [[ "${agent_command%% *}" == *sacp-conductor ]]; then
  conductor="${agent_command%% *}"
  components="${agent_command#* }"
  printf -v quoted_debug_dir '%q' "$debug_dir"
  agent_command="$conductor --debug --debug-dir $quoted_debug_dir $components"
fi

coproc ACP_PROCESS { exec bash -c "$agent_command"; }

cleanup() {
  if [[ -n "${ACP_PROCESS_PID:-}" ]] && kill -0 "$ACP_PROCESS_PID" 2>/dev/null; then
    kill "$ACP_PROCESS_PID" 2>/dev/null || true
    wait "$ACP_PROCESS_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

read_response() {
  local expected_id="$1"
  local deadline=$((SECONDS + timeout))
  local line

  while ((SECONDS < deadline)); do
    if IFS= read -r -t 1 -u "${ACP_PROCESS[0]}" line; then
      echo "ACP response: $line"
      if jq -e --argjson expected_id "$expected_id" '.id == $expected_id' >/dev/null 2>&1 <<<"$line"; then
        rpc_response="$line"
        return 0
      fi
      continue
    fi

    if ! kill -0 "$ACP_PROCESS_PID" 2>/dev/null; then
      echo "test-acp-startup: ACP process exited before response $expected_id" >&2
      return 1
    fi
  done

  echo "test-acp-startup: timed out waiting for response $expected_id" >&2
  return 1
}

initialize_request=$(jq -nc '{
  jsonrpc: "2.0",
  id: 0,
  method: "initialize",
  params: {
    protocolVersion: 1,
    clientCapabilities: {
      fs: {readTextFile: true, writeTextFile: true},
      terminal: true
    },
    clientInfo: {name: "cursor-cli-startup-test", version: "1"}
  }
}')
echo "Sending initialize"
printf '%s\n' "$initialize_request" >&"${ACP_PROCESS[1]}"
read_response 0

if ! jq -e '.result.protocolVersion == 1' >/dev/null 2>&1 <<<"$rpc_response"; then
  echo "test-acp-startup: initialize failed" >&2
  jq -c '{id, error, result}' <<<"$rpc_response" >&2
  exit 1
fi

session_request=$(jq -nc --arg cwd "$PWD" '{
  jsonrpc: "2.0",
  id: 1,
  method: "session/new",
  params: {cwd: $cwd, mcpServers: []}
}')
echo "Sending session/new"
printf '%s\n' "$session_request" >&"${ACP_PROCESS[1]}"
read_response 1

if ! jq -e '.result.sessionId | strings | length > 0' >/dev/null 2>&1 <<<"$rpc_response"; then
  echo "test-acp-startup: session/new failed" >&2
  jq -c '{id, error}' <<<"$rpc_response" >&2
  exit 1
fi

echo "ACP startup OK: session/new returned a session ID"
