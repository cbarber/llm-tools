#!/usr/bin/env bash
# Agent Sandbox Wrapper
#
# Usage: agent-sandbox <command> [args...]
#
# Runs the given command in a sandboxed environment using bubblewrap.
# The sandbox restricts access to:
# - Current project directory (read-write)
# - /nix store (read-only)
# - Temporary workspace (read-write, auto-cleaned)
#
# Environment variables:
#   AGENT_SANDBOX_BIND_HOME - Set to "true" to bind mount $HOME (breaks isolation)
#   AGENT_SANDBOX_SSH       - Set to "true" to bind mount ~/.ssh (for git auth)

set -euo pipefail

if ! command -v bwrap &>/dev/null; then
  echo "Error: bubblewrap (bwrap) not found. Install it to use agent sandboxing." >&2
  exit 1
fi

# Create temporary workspace
WORK_DIR=$(mktemp -d -t agent-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# Build bwrap command
BWRAP_ARGS=(
  # Core system access (read-only)
  --ro-bind /nix /nix
  
  # Current project directory (read-write)
  --bind "$(pwd)" "$(pwd)"
  
  # Temporary workspace
  --bind "$WORK_DIR" /tmp/agent-work
  --setenv AGENT_WORK_DIR /tmp/agent-work
  
  # Essential system directories
  --dev-bind /dev /dev
  --proc /proc
  --tmpfs /tmp
  
  # Namespace isolation
  --unshare-all
  --share-net  # Allow network access
  
  # Die with parent (cleanup if parent dies)
  --die-with-parent
)

# Optional: bind mount SSH keys for git authentication
if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]] && [[ -d "$HOME/.ssh" ]]; then
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh" "$HOME/.ssh")
fi

# Optional: bind mount entire home (breaks isolation, use with caution)
if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  echo "Warning: Binding \$HOME breaks sandbox isolation" >&2
  BWRAP_ARGS+=(--bind "$HOME" "$HOME")
fi

# Run command in sandbox
exec bwrap "${BWRAP_ARGS[@]}" "$@"
