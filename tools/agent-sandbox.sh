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

AGENT_GITCONFIG_PATH=$(mktemp /tmp/agent-gitconfig-XXXXXX)
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

_cleanup() {
  rm -f "$_FENCE_CFG"
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
_system_ro=("/nix" "/proc" "/etc" "/run/current-system")

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

if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
  export GIT_CONFIG_GLOBAL
fi

if [[ -n "${OPENCODE_PORT:-}" ]]; then
  export OPENCODE_PORT
  export OPENCODE_API="http://127.0.0.1:${OPENCODE_PORT}"
fi

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

if [[ -n "${OPENCODE_PORT:-}" ]]; then
  # OPENCODE_PORT is a host-side service the sandbox needs to reach outbound,
  # not a service inside the sandbox. Use allowLocalOutboundPorts in the config.
  jq --argjson port "${OPENCODE_PORT}" \
    '.network.allowLocalOutboundPorts = [$port]' \
    "$_FENCE_CFG" > "${_FENCE_CFG}.tmp" && mv "${_FENCE_CFG}.tmp" "$_FENCE_CFG"
fi

_dbg "exec fence: $FENCE_BIN ${FENCE_ARGS[*]}"
unset _git_cfg _deny_write _system_ro
unset _deny_write_json _allow_read_json _allow_write_json _local_ports _local_ports_json _port

exec "$FENCE_BIN" "${FENCE_ARGS[@]}" -- "$@"
