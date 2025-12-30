#!/usr/bin/env bash
# macOS Sandbox Implementation
#
# This script implements sandboxing for macOS using sandbox-exec.
# It should be sourced from agent-sandbox.sh, not executed directly.
#
# Environment variables (inherited from agent-sandbox.sh):
#   AGENT_SANDBOX_BIND_HOME - Set to "true" to allow full home access (breaks isolation)
#   AGENT_SANDBOX_SSH       - Set to "true" to allow full SSH directory access
#   BWRAP_EXTRA_PATHS       - Colon-separated agent/project-specific paths

set -euo pipefail

# Ensure sandbox-exec is available
if ! command -v sandbox-exec &>/dev/null; then
  echo "Error: sandbox-exec not found. This script requires macOS." >&2
  exit 1
fi

# Create temporary workspace
WORK_DIR=$(mktemp -d -t agent-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# Find the sandbox profile template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_TEMPLATE="$SCRIPT_DIR/macos-sandbox-profile.sb"

if [[ ! -f "$PROFILE_TEMPLATE" ]]; then
  echo "Error: Sandbox profile template not found at $PROFILE_TEMPLATE" >&2
  exit 1
fi

# Read the profile template (no variable substitution needed - using -D params)
PROFILE_CONTENT=$(<"$PROFILE_TEMPLATE")

# Collect -D parameters for sandbox-exec (Codex-style parameterized paths)
SANDBOX_PARAMS=()
PROJECT_DIR="$(pwd)"
SANDBOX_PARAMS+=("-DPROJECT_DIR=$PROJECT_DIR")

# Canonicalize WORK_DIR (resolves symlinks like /var -> /private/var)
WORK_DIR_CANONICAL="$(cd "$WORK_DIR" && pwd -P)"
SANDBOX_PARAMS+=("-DWORK_DIR=$WORK_DIR_CANONICAL")

# Add TMPDIR (macOS sets this to /var/folders/.../T/ by default)
# Following Codex's approach: include TMPDIR as writable (needed for mktemp, nix, etc.)
# CRITICAL: Canonicalize TMPDIR to handle /var -> /private/var symlink on macOS
if [[ -n "${TMPDIR:-}" ]]; then
  # Use realpath to canonicalize (resolves /var/folders -> /private/var/folders)
  TMPDIR_CANONICAL="$(cd "$TMPDIR" && pwd -P 2>/dev/null || echo "$TMPDIR")"
  SANDBOX_PARAMS+=("-DTMPDIR=$TMPDIR_CANONICAL")
else
  # Fallback to /tmp if TMPDIR not set (shouldn't happen on macOS, but be safe)
  SANDBOX_PARAMS+=("-DTMPDIR=/tmp")
fi

# Add home directory parameters for writable paths
SANDBOX_PARAMS+=("-DHOME_CONFIG_OPENCODE=$HOME/.config/opencode")
SANDBOX_PARAMS+=("-DHOME_CONFIG_NIXSMITH=$HOME/.config/nixsmith")
SANDBOX_PARAMS+=("-DHOME_CLAUDE_JSON=$HOME/.claude.json")
SANDBOX_PARAMS+=("-DHOME_CLAUDE=$HOME/.claude")
SANDBOX_PARAMS+=("-DHOME_CACHE_OPENCODE=$HOME/.cache/opencode")
SANDBOX_PARAMS+=("-DHOME_CACHE_CLAUDE=$HOME/.cache/claude")
SANDBOX_PARAMS+=("-DHOME_CACHE_NIX=$HOME/.cache/nix")
SANDBOX_PARAMS+=("-DHOME_SHARE_OPENCODE=$HOME/.local/share/opencode")
SANDBOX_PARAMS+=("-DHOME_SHARE_CLAUDE=$HOME/.local/share/claude")
SANDBOX_PARAMS+=("-DHOME_CACHE_GO=$HOME/.cache/go-build")
SANDBOX_PARAMS+=("-DHOME_CARGO=$HOME/.cargo")
SANDBOX_PARAMS+=("-DHOME_CACHE_PIP=$HOME/.cache/pip")
SANDBOX_PARAMS+=("-DHOME_GEM=$HOME/.gem")
SANDBOX_PARAMS+=("-DHOME_CACHE_YARN=$HOME/.cache/yarn")
SANDBOX_PARAMS+=("-DHOME_NPM=$HOME/.npm")
SANDBOX_PARAMS+=("-DHOME_SHARE_PNPM=$HOME/.local/share/pnpm")
SANDBOX_PARAMS+=("-DHOME_BUN=$HOME/.bun")

# Handle BWRAP_EXTRA_PATHS by adding write permissions
if [[ -n "${BWRAP_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -ra EXTRA_PATHS <<< "$BWRAP_EXTRA_PATHS"
  EXTRA_WRITE_RULES=""
  for i in "${!EXTRA_PATHS[@]}"; do
    path="${EXTRA_PATHS[$i]}"
    # Expand tilde to home directory
    expanded_path="${path/#\~/$HOME}"
    
    # Skip empty paths
    [[ -z "$expanded_path" ]] && continue
    
    # Add write permission if directory exists
    if [[ -d "$expanded_path" ]]; then
      PARAM_NAME="EXTRA_PATH_$i"
      EXTRA_WRITE_RULES+="  (subpath (param \"$PARAM_NAME\"))"$'\n'
      SANDBOX_PARAMS+=("-D$PARAM_NAME=$expanded_path")
    fi
  done
  
  # Append extra write rules to profile
  if [[ -n "$EXTRA_WRITE_RULES" ]]; then
    PROFILE_CONTENT+=$'\n;; Extra paths from BWRAP_EXTRA_PATHS\n'
    PROFILE_CONTENT+="(allow file-write*"$'\n'
    PROFILE_CONTENT+="$EXTRA_WRITE_RULES"
    PROFILE_CONTENT+=")"
  fi
fi

# Handle AGENT_SANDBOX_BIND_HOME
if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  echo "Warning: AGENT_SANDBOX_BIND_HOME=true allows full home directory access (breaks isolation)" >&2
  #Override: allow writes to entire home directory
  SANDBOX_PARAMS+=("-DHOME_FULL=$HOME")
  PROFILE_CONTENT+=$'\n(allow file-write* (subpath (param "HOME_FULL")))'
fi

# Handle AGENT_SANDBOX_SSH
if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]]; then
  echo "Warning: AGENT_SANDBOX_SSH=true allows full SSH directory access" >&2
  SANDBOX_PARAMS+=("-DHOME_SSH=$HOME/.ssh")
  PROFILE_CONTENT+=$'\n(allow file-write* (subpath (param "HOME_SSH")))'
fi

# Create agent config directories if they don't exist
mkdir -p "$HOME/.config/opencode" "$HOME/.config/claude" "$HOME/.claude" \
         "$HOME/.config/nixsmith" \
         "$HOME/.cache/opencode" "$HOME/.cache/claude" \
         "$HOME/.local/share/opencode" "$HOME/.local/share/claude" 2>/dev/null || true

# Set environment variables for the sandboxed process
export AGENT_WORK_DIR="$WORK_DIR"
export IN_AGENT_SANDBOX="1"

# SSH config handling for git operations
# On Linux, bubblewrap mounts config.agent AS config (complete remapping)
# On macOS, sandbox-exec can't do mount remapping, so we:
# 1. Block access to personal ~/.ssh/config in the sandbox profile
# 2. Allow access to ~/.ssh/config.agent
# 3. Set GIT_SSH_COMMAND to use config.agent explicitly
if [[ -f "$HOME/.ssh/config.agent" ]] && [[ "${AGENT_SANDBOX_SSH:-false}" != "true" ]]; then
  export GIT_SSH_COMMAND="ssh -F $HOME/.ssh/config.agent"
fi

# Debug: show profile and params if AGENT_SANDBOX_DEBUG is set
if [[ "${AGENT_SANDBOX_DEBUG:-false}" == "true" ]]; then
  echo "=== Sandbox Profile ===" >&2
  echo "$PROFILE_CONTENT" >&2
  echo "=== Parameters ===" >&2
  printf '%s\n' "${SANDBOX_PARAMS[@]}" >&2
  echo "======================" >&2
fi

# Run command in sandbox using Codex-style invocation:
# sandbox-exec -p <profile> -DVAR=value ... -- <command> [args...]
# Note: Using -p with profile string directly (more reliable than -f with temp file)
exec sandbox-exec -p "$PROFILE_CONTENT" "${SANDBOX_PARAMS[@]}" -- "$@"
