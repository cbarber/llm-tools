#!/usr/bin/env bash
# Agent Sandbox Wrapper
#
# Usage: agent-sandbox <command> [args...]
#
# Runs the given command inside a fence sandbox. Uses defaultDenyRead so only
# explicitly allowed paths are readable. Path lists are built by
# setup-sandbox-paths.sh (same as the bwrap backend) and consumed as
# allowRead/allowWrite entries in the fence JSON config.
#
# Environment variables:
#   AGENT_SANDBOX_SSH   - "true" to allow reads+writes to ~/.ssh
#   SANDBOX_EXTRA_RO    - colon-separated additional read-only paths
#   SANDBOX_EXTRA_RW    - colon-separated additional read-write paths
#   SANDBOX_LOCAL_OUTBOUND_PORTS - colon-separated host loopback ports to bridge on Linux
#   OPENCODE_PORT       - opencode API port to bridge on Linux

set -euo pipefail

_dbg() { [[ "${AGENT_DEBUG:-false}" == "true" ]] && echo "[DEBUG agent-sandbox] $*" >&2 || true; }

# shellcheck source=common-helpers.sh
_dbg "sourcing common-helpers.sh"
source "${TOOLS_DIR:-$(dirname "$0")}/common-helpers.sh"

SANDBOX_MOUNTS_RO=()
SANDBOX_MOUNTS_RW=()

mkdir -p "$HOME/.config/nixsmith" 2>/dev/null || true

# shellcheck source=setup-sandbox-paths.sh
_dbg "sourcing setup-sandbox-paths.sh"
source "${TOOLS_DIR:-$(dirname "$0")}/setup-sandbox-paths.sh"
_dbg "setup-sandbox-paths.sh done"

# ── Locate fence ─────────────────────────────────────────────────────────────
_dbg "locating fence binary"

FENCE_BIN=""
if [[ -n "${FENCE_PATH:-}" ]] && [[ -x "$FENCE_PATH" ]]; then
  FENCE_BIN="$FENCE_PATH"
elif command -v fence &>/dev/null; then
  FENCE_BIN="$(command -v fence)"
fi

if [[ -z "$FENCE_BIN" ]]; then
  echo "agent-sandbox: fence not found. Install it or set FENCE_PATH." >&2
  exit 1
fi
_dbg "fence binary: $FENCE_BIN"

# ── Locate iron-proxy ─────────────────────────────────────────────────────────
_dbg "locating iron-proxy binary"

IRON_PROXY_BIN=""
if [[ -n "${IRON_PROXY_PATH:-}" ]] && [[ -x "$IRON_PROXY_PATH" ]]; then
  IRON_PROXY_BIN="$IRON_PROXY_PATH"
elif command -v iron-proxy &>/dev/null; then
  IRON_PROXY_BIN="$(command -v iron-proxy)"
fi
_dbg "iron-proxy binary: ${IRON_PROXY_BIN:-<not found>}"

# ── Build fence config ────────────────────────────────────────────────────────
# Explicit config — no template inheritance. defaultDenyRead: true means only
# paths in allowRead are readable. useDefaults: false disables fence's built-in
# command deny list (chroot, unshare, etc.) which blocks NixOS coreutils
# multi-call binaries via landlock.
#
# allowRead  ← SANDBOX_MOUNTS_RO  (built by setup-sandbox-paths.sh)
# allowWrite ← SANDBOX_MOUNTS_RW  (built by setup-sandbox-paths.sh)
# denyWrite  ← secrets + ssh keys + .git/config

_FENCE_CFG=$(mktemp /tmp/fence-XXXXXX.json)

_IRON_PROXY_PID=""
_IRON_CFG=""

_cleanup() {
  rm -f "$_FENCE_CFG" "$_IRON_CFG"
  if [[ -n "$_IRON_PROXY_PID" ]]; then
    kill "$_IRON_PROXY_PID" 2>/dev/null || true
  fi
}
trap _cleanup EXIT

# Paths agents must never write.
_deny_write=(
  "${HOME}/.gnupg"
  "${HOME}/.config/nixsmith/secrets.json"
)
if [[ "${AGENT_SANDBOX_SSH:-false}" != "true" ]]; then
  _deny_write+=("${HOME}/.ssh")
fi
if git rev-parse --git-dir >/dev/null 2>&1; then
  _git_cfg=$(git rev-parse --git-common-dir 2>/dev/null || git rev-parse --git-dir 2>/dev/null)/config
  [[ -f "$_git_cfg" ]] && _deny_write+=("$_git_cfg")
fi

# Always readable: /nix (binaries), /proc (self status), /etc (SSL/resolv),
# /run/current-system (NixOS compat). These are system paths not covered by
# setup-sandbox-paths.sh which focuses on home/project paths.
_system_ro=("/nix" "/proc" "/etc" "/run/current-system" "/tmp")

_deny_write_json=$(printf '%s\n' "${_deny_write[@]}"               | jq -R . | jq -s .)
_deny_read_json=$(printf '%s\n' "${_deny_write[@]}"                | jq -R . | jq -s .)
_allow_read_json=$(printf '%s\n' "${_system_ro[@]}" "${SANDBOX_MOUNTS_RO[@]:-}" "${SANDBOX_MOUNTS_RW[@]:-}" | jq -R . | jq -s .)
_allow_write_json=$(printf '%s\n' "/tmp" "${SANDBOX_MOUNTS_RW[@]:-}"            | jq -R . | jq -s .)
_local_ports=()
if [[ -n "${SANDBOX_LOCAL_OUTBOUND_PORTS:-}" ]]; then
  IFS=':' read -ra _local_ports <<< "$SANDBOX_LOCAL_OUTBOUND_PORTS"
  for _port in "${_local_ports[@]}"; do
    if [[ ! "$_port" =~ ^[0-9]+$ ]] || (( 10#$_port < 1 || 10#$_port > 65535 )); then
      echo "agent-sandbox: invalid port in SANDBOX_LOCAL_OUTBOUND_PORTS: $_port" >&2
      exit 1
    fi
  done
fi
_local_ports_json=$(printf '%s\n' "${_local_ports[@]:-}" | jq -R 'select(length > 0) | tonumber' | jq -s 'unique')

jq -n \
  --argjson allowRead  "$_allow_read_json" \
  --argjson allowWrite "$_allow_write_json" \
  --argjson allowLocalOutboundPorts "$_local_ports_json" \
  --argjson denyRead   "$_deny_read_json" \
  --argjson denyWrite  "$_deny_write_json" \
  '{
    allowPty: true,
    network: {
      allowedDomains: ["*"],
      allowLocalOutbound: true,
      allowLocalOutboundPorts: $allowLocalOutboundPorts,
      allowLocalBinding: true
    },
    filesystem: {
      defaultDenyRead: true,
      allowRead:  $allowRead,
      allowWrite: $allowWrite,
      denyRead:   $denyRead,
      denyWrite:  $denyWrite
    },
    command: {
      useDefaults: false
    }
  }' > "$_FENCE_CFG"
_dbg "fence config written: $_FENCE_CFG"

# ── Environment ───────────────────────────────────────────────────────────────

export IN_AGENT_SANDBOX=1
export AGENT_WORK_DIR=/tmp
export OPENCODE_AUTH_CONTENT="{}"
export NIXSMITH_SANDBOX_RO="${NIXSMITH_SANDBOX_RO:-}"
export NIXSMITH_SANDBOX_RW="${NIXSMITH_SANDBOX_RW:-}"

if [[ -n "${OPENCODE_PORT:-}" ]]; then
  export OPENCODE_PORT
  export OPENCODE_API="http://127.0.0.1:${OPENCODE_PORT}"
fi

# ── Credential proxy (iron-proxy) ─────────────────────────────────────────────
# Secrets must not enter the sandbox process environment. iron-proxy intercepts
# HTTPS traffic and injects credentials at the HTTP layer so the sandboxed
# agent never sees the raw secret values.
#
# Priority:
#   1. NIXSMITH_CREDENTIAL_PROXY already set → use it directly (no iron-proxy)
#   2. NIXSMITH_SECRETS_ENV set + iron-proxy available → start iron-proxy
#   3. Neither → secrets fall through as env vars (legacy, no proxy)

if [[ -n "${NIXSMITH_CREDENTIAL_PROXY:-}" ]]; then
  _dbg "using pre-configured credential proxy: $NIXSMITH_CREDENTIAL_PROXY"
  # Secrets already flow through the pre-configured proxy — the raw values
  # must not also ride along as a plaintext env var (TASK-38).
  unset NIXSMITH_SECRETS_ENV
  _PROXY_TUNNEL="$NIXSMITH_CREDENTIAL_PROXY"
  _PROXY_CA="${NIXSMITH_CREDENTIAL_PROXY_CA:-}"

elif [[ -n "${NIXSMITH_SECRETS_ENV:-}" ]] && [[ -n "$IRON_PROXY_BIN" ]]; then
  _dbg "starting iron-proxy for credential injection"

  # Generate CA once — persists across sessions
  _IRON_CA_DIR="${HOME}/.config/nixsmith/iron-proxy"
  mkdir -p "$_IRON_CA_DIR"
  if [[ ! -f "$_IRON_CA_DIR/ca.crt" ]]; then
    _dbg "generating iron-proxy CA in $_IRON_CA_DIR"
    "$IRON_PROXY_BIN" generate-ca --outdir "$_IRON_CA_DIR" >/dev/null 2>&1
  fi

  # Pick a free port for the tunnel listener
  _IRON_PORT=$(python3 -c \
    'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' \
    2>/dev/null || echo "0")
  _dbg "iron-proxy tunnel port: $_IRON_PORT"

  # Write per-session YAML config
  _IRON_CFG=$(mktemp /tmp/iron-proxy-XXXXXX.yaml)

  # For each KEY=VALUE pair: generate a per-session proxy token, configure
  # iron-proxy to swap it for the real secret, and export only the proxy token
  # into the sandbox env. The real secret goes only to iron-proxy's env.
  _IRON_SECRETS_YAML=""
  _iron_env=()
  _sandbox_token_env=()
  while IFS= read -r _pair; do
    [[ -z "$_pair" ]] && continue
    _key="${_pair%%=*}"
    _val="${_pair#*=}"
    # Random proxy token — sandbox sees this, never the real value
    _token="proxy-${_key,,}-$(head -c 12 /dev/urandom | base64 | tr -d '+/=')"
    _IRON_SECRETS_YAML+="        - source:"$'\n'
    _IRON_SECRETS_YAML+="            type: env"$'\n'
    _IRON_SECRETS_YAML+="            var: '${_key}'"$'\n'
    _IRON_SECRETS_YAML+="          replace:"$'\n'
    _IRON_SECRETS_YAML+="            proxy_value: '${_token}'"$'\n'
    _IRON_SECRETS_YAML+="            match_headers: ['X-Api-Key', 'Authorization']"$'\n'
    _IRON_SECRETS_YAML+="            match_body: true"$'\n'
    _IRON_SECRETS_YAML+="            match_query: true"$'\n'
    _IRON_SECRETS_YAML+="          rules:"$'\n'
    _IRON_SECRETS_YAML+="            - host: '*'"$'\n'
    _iron_env+=("${_key}=${_val}")
    _sandbox_token_env+=("${_key}=${_token}")
  done <<< "$NIXSMITH_SECRETS_ENV"
  unset NIXSMITH_SECRETS_ENV
  unset _pair _key _val _token

  {
    cat <<IRON_CFG_EOF
dns:
  enabled: false
proxy:
  http_listen: "127.0.0.1:0"
  https_listen: "127.0.0.1:0"
  tunnel_listen: "127.0.0.1:${_IRON_PORT}"
  upstream_deny_cidrs: []
metrics:
  listen: "127.0.0.1:0"
tls:
  ca_cert: "${_IRON_CA_DIR}/ca.crt"
  ca_key: "${_IRON_CA_DIR}/ca.key"
transforms:
  - name: allowlist
    config:
      warn: true
  - name: secrets
    config:
      secrets:
IRON_CFG_EOF
    printf '%s' "$_IRON_SECRETS_YAML"
  } > "$_IRON_CFG"

  unset _IRON_SECRETS_YAML

  # Start iron-proxy with real secrets in its env only; redirect logs to
  # FENCE_LOG_FILE when set, otherwise discard them.
  _iron_log="${FENCE_LOG_FILE:-/dev/null}"
  env "${_iron_env[@]}" "$IRON_PROXY_BIN" -config "$_IRON_CFG" >>"$_iron_log" 2>&1 &
  unset _iron_log
  _IRON_PROXY_PID=$!
  _dbg "iron-proxy started (pid=$_IRON_PROXY_PID, port=$_IRON_PORT)"

  # Wait up to 5s for the tunnel port to be ready
  _iron_ready=false
  for _i in 1 2 3 4 5; do
    sleep 1
    if (echo "" >/dev/tcp/127.0.0.1/"$_IRON_PORT") 2>/dev/null; then
      _iron_ready=true
      break
    fi
  done
  unset _i
  if [[ "$_iron_ready" != "true" ]]; then
    echo "agent-sandbox: iron-proxy did not start within 5s (port $_IRON_PORT), falling back to env injection" >&2
    kill "$_IRON_PROXY_PID" 2>/dev/null || true
    _IRON_PROXY_PID=""
    # Fall back: export real secrets since the proxy isn't intercepting
    for _pair in "${_iron_env[@]:-}"; do
      [[ -z "$_pair" ]] && continue
      export "${_pair?}"
    done
    unset _iron_env _sandbox_token_env _pair _IRON_PORT _IRON_CA_DIR
    _PROXY_TUNNEL=""
    _PROXY_CA=""
  else
    # Export proxy tokens into the sandbox env — real secrets stay in iron-proxy only
    for _pair in "${_sandbox_token_env[@]:-}"; do
      [[ -z "$_pair" ]] && continue
      export "${_pair?}"
    done
    unset _iron_env _sandbox_token_env _pair

    _PROXY_TUNNEL="http://127.0.0.1:${_IRON_PORT}"
    _PROXY_CA="${_IRON_CA_DIR}/ca.crt"
    unset _IRON_PORT _IRON_CA_DIR
  fi
  unset _iron_ready

else
  # No iron-proxy available — fall back to injecting secrets as env vars (legacy)
  if [[ -n "${NIXSMITH_SECRETS_ENV:-}" ]]; then
    while IFS= read -r _pair; do
      [[ -z "$_pair" ]] && continue
      _key="${_pair%%=*}"
      _val="${_pair#*=}"
      export "${_key}=${_val}"
    done <<< "$NIXSMITH_SECRETS_ENV"
    unset _pair _key _val
  fi
  unset NIXSMITH_SECRETS_ENV
  _PROXY_TUNNEL=""
  _PROXY_CA=""
fi

# Chain iron-proxy as fence's upstream: fence's internal proxy forwards all
# traffic to iron-proxy, which swaps tokens before reaching the internet.
# Setting HTTPS_PROXY directly is ineffective — fence overwrites it with its
# own socat bridge address. upstreamProxy in the fence config is the correct
# insertion point.
if [[ -n "${_PROXY_TUNNEL:-}" ]]; then
  # Switch from relaxed wildcard mode to proxy-routed mode so fence uses its
  # internal HTTP proxy (which chains to iron-proxy) for all traffic. Without
  # this, allowedDomains:["*"] puts fence in relaxed direct-network mode where
  # upstreamProxy is never consulted.
  jq --arg upstream "$_PROXY_TUNNEL" \
    'del(.network.allowedDomains) | .network.defaultAction = "proxy" | .network.upstreamProxy = $upstream' \
    "$_FENCE_CFG" > "${_FENCE_CFG}.tmp" && mv "${_FENCE_CFG}.tmp" "$_FENCE_CFG"
  _dbg "fence upstreamProxy set to $_PROXY_TUNNEL"
fi
if [[ -n "${_PROXY_CA:-}" ]] && [[ -f "$_PROXY_CA" ]]; then
  export SSL_CERT_FILE="$_PROXY_CA"
  export NODE_EXTRA_CA_CERTS="$_PROXY_CA"
  export REQUESTS_CA_BUNDLE="$_PROXY_CA"
  export CURL_CA_BUNDLE="$_PROXY_CA"
fi
unset _PROXY_TUNNEL _PROXY_CA

# ── Fence invocation ──────────────────────────────────────────────────────────

FENCE_ARGS=(--settings "$_FENCE_CFG")
if [[ -n "${FENCE_LOG_FILE:-}" ]]; then
  FENCE_ARGS+=(--fence-log-file "$FENCE_LOG_FILE")
fi

# expose-host-path-rw makes paths writable inside the sandbox (fence's
# --ro-bind / / baseline is read-only; RW paths need explicit exposure).
FENCE_ARGS+=(--expose-host-path-rw "$(pwd)")
FENCE_ARGS+=(--expose-host-path-rw /tmp)
for _p in "${SANDBOX_MOUNTS_RW[@]:-}"; do
  [[ -z "$_p" ]] && continue
  [[ -e "$_p" ]] || continue
  FENCE_ARGS+=(--expose-host-path-rw "$_p")
done


_dbg "exec fence: $FENCE_BIN ${FENCE_ARGS[*]}"
unset _git_cfg _deny_write _system_ro
unset _deny_write_json _allow_read_json _allow_write_json _local_ports _local_ports_json _port

# Run fence as a child (not exec) so the EXIT trap fires and kills iron-proxy.
"$FENCE_BIN" "${FENCE_ARGS[@]}" -- "$@"
exit $?
