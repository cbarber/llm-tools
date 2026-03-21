#!/usr/bin/env bash
# macOS Sandbox Implementation
#
# Environment variables:
#   AGENT_SANDBOX_BIND_HOME - "true" to allow writes to entire home dir (breaks isolation)
#   AGENT_SANDBOX_SSH       - "true" to allow reads+writes to ~/.ssh (for git operations)
#   SANDBOX_EXTRA_RO        - colon-separated additional read-only paths
#   SANDBOX_EXTRA_RW        - colon-separated additional read-write paths
#   BWRAP_EXTRA_PATHS       - deprecated alias for SANDBOX_EXTRA_RW

set -euo pipefail

# Ensure sandbox-exec is available
if ! command -v sandbox-exec &>/dev/null; then
  echo "Error: sandbox-exec not found. This script requires macOS." >&2
  exit 1
fi

WORK_DIR=$(mktemp -d -t agent-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_TEMPLATE="$SCRIPT_DIR/macos-sandbox-profile.sb"

if [[ ! -f "$PROFILE_TEMPLATE" ]]; then
  echo "Error: Sandbox profile template not found at $PROFILE_TEMPLATE" >&2
  exit 1
fi

PROFILE_CONTENT=$(<"$PROFILE_TEMPLATE")

SANDBOX_PARAMS=()
PROJECT_DIR="$(pwd)"
SANDBOX_PARAMS+=("-DPROJECT_DIR=$PROJECT_DIR")

# Canonicalize to resolve /var -> /private/var symlink on macOS
WORK_DIR_CANONICAL="$(cd "$WORK_DIR" && pwd -P)"
SANDBOX_PARAMS+=("-DWORK_DIR=$WORK_DIR_CANONICAL")

# TMPDIR is /var/folders/.../T/ by default on macOS; canonicalize for same reason
if [[ -n "${TMPDIR:-}" ]]; then
  TMPDIR_CANONICAL="$(cd "$TMPDIR" && pwd -P 2>/dev/null || echo "$TMPDIR")"
  SANDBOX_PARAMS+=("-DTMPDIR=$TMPDIR_CANONICAL")
else
  SANDBOX_PARAMS+=("-DTMPDIR=/tmp")
fi

SANDBOX_PARAMS+=("-DHOME_DIR=$HOME")
SANDBOX_PARAMS+=("-DHOME_SSH=$HOME/.ssh")
SANDBOX_PARAMS+=("-DHOME_GNUPG=$HOME/.gnupg")

GIT_CONFIG_PATH="$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null)/config" || true
if [[ -f "$GIT_CONFIG_PATH" ]]; then
  GIT_CONFIG_CANONICAL="$(cd "$(dirname "$GIT_CONFIG_PATH")" && pwd -P)/config"
  SANDBOX_PARAMS+=("-DGIT_CONFIG=$GIT_CONFIG_CANONICAL")
else
  SANDBOX_PARAMS+=("-DGIT_CONFIG=$PROJECT_DIR/.git/config")
fi

SANDBOX_MOUNTS_RO=()
SANDBOX_MOUNTS_RW=()

SANDBOX_MOUNTS_RO+=("$HOME/.config/nix" "$HOME/.local/share/nix")
SANDBOX_MOUNTS_RW+=("$HOME/.cache/nix")

AGENT_GITCONFIG_PATH="$WORK_DIR/agent-gitconfig"
# shellcheck source=setup-sandbox-paths.sh
source "${TOOLS_DIR:-$(dirname "$0")}/setup-sandbox-paths.sh"

SANDBOX_RO_RULES=""
for i in "${!SANDBOX_MOUNTS_RO[@]}"; do
  p="${SANDBOX_MOUNTS_RO[$i]}"
  [[ -e "$p" ]] || continue
  PARAM_NAME="SANDBOX_RO_$i"
  SANDBOX_RO_RULES+="  (subpath (param \"$PARAM_NAME\"))"$'\n'
  SANDBOX_PARAMS+=("-D$PARAM_NAME=$p")
done
[[ -n "$SANDBOX_RO_RULES" ]] && PROFILE_CONTENT+=$'\n(allow file-read*\n'"$SANDBOX_RO_RULES"')'

# Literal read access for intermediate directories that tools must stat to
# traverse into allowed subpaths. (subpath) on a leaf grants no access to its
# parents; without these literals, directory traversal fails with EPERM.
HOME_TRAVERSE_PATHS=(
  "$HOME/.cache"
  "$HOME/.config"
  "$HOME/.local"
  "$HOME/.local/share"
)
HOME_TRAVERSE_RULES=""
for i in "${!HOME_TRAVERSE_PATHS[@]}"; do
  p="${HOME_TRAVERSE_PATHS[$i]}"
  [[ -e "$p" ]] || continue
  PARAM_NAME="HOME_TRAVERSE_$i"
  HOME_TRAVERSE_RULES+="  (literal (param \"$PARAM_NAME\"))"$'\n'
  SANDBOX_PARAMS+=("-D$PARAM_NAME=$p")
done
[[ -n "$HOME_TRAVERSE_RULES" ]] && PROFILE_CONTENT+=$'\n(allow file-read*\n'"$HOME_TRAVERSE_RULES"')'

SANDBOX_RW_RULES=""
for i in "${!SANDBOX_MOUNTS_RW[@]}"; do
  p="${SANDBOX_MOUNTS_RW[$i]}"
  [[ -e "$p" ]] || continue
  PARAM_NAME="SANDBOX_RW_$i"
  SANDBOX_RW_RULES+="  (subpath (param \"$PARAM_NAME\"))"$'\n'
  SANDBOX_PARAMS+=("-D$PARAM_NAME=$p")
done
[[ -n "$SANDBOX_RW_RULES" ]] && PROFILE_CONTENT+=$'\n(allow file-read* file-write*\n'"$SANDBOX_RW_RULES"')'

if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  SANDBOX_PARAMS+=("-DHOME_FULL=$HOME")
  PROFILE_CONTENT+=$'\n(allow file-write* (subpath (param "HOME_FULL")))'
fi

if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]]; then
  PROFILE_CONTENT+=$'\n(allow file-read* file-write* (subpath (param "HOME_SSH")))'
fi

export AGENT_WORK_DIR="$WORK_DIR_CANONICAL"
export IN_AGENT_SANDBOX="1"

if [[ "${AGENT_SANDBOX_DEBUG:-false}" == "true" ]]; then
  echo "=== Sandbox Profile ===" >&2
  echo "$PROFILE_CONTENT" >&2
  echo "=== Parameters ===" >&2
  printf '%s\n' "${SANDBOX_PARAMS[@]}" >&2
  echo "======================" >&2
fi

exec sandbox-exec -p "$PROFILE_CONTENT" "${SANDBOX_PARAMS[@]}" -- "$@"
