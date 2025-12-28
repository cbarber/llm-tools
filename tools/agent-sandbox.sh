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

# Find bwrap - try BWRAP_PATH env var first, then PATH, then nix store
BWRAP=""
if [[ -n "${BWRAP_PATH:-}" ]] && [[ -x "$BWRAP_PATH" ]]; then
  BWRAP="$BWRAP_PATH"
elif command -v bwrap &>/dev/null; then
  BWRAP="bwrap"
else
  # Search for bwrap in nix store
  for candidate in /nix/store/*-bubblewrap-*/bin/bwrap; do
    if [[ -x "$candidate" ]]; then
      BWRAP="$candidate"
      break
    fi
  done
fi

if [[ -z "$BWRAP" ]] || [[ ! -x "$BWRAP" ]]; then
  echo "Error: bubblewrap (bwrap) not found. Install it to use agent sandboxing." >&2
  echo "Searched: BWRAP_PATH=${BWRAP_PATH:-unset}, PATH, and /nix/store/*-bubblewrap-*/bin/bwrap" >&2
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
  
  # Namespace isolation
  --unshare-all
  --share-net  # Allow network access
  
  # Die with parent (cleanup if parent dies)
  --die-with-parent
  
  # Preserve PATH and mark that we're in sandbox
  --setenv PATH "$PATH"
  --setenv IN_AGENT_SANDBOX "1"
)

# Bind mount all directories in PATH (read-only)
# This ensures all commands available to the parent are available in the sandbox
IFS=':' read -ra PATH_DIRS <<< "$PATH"
for dir in "${PATH_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    # Skip if already covered by /nix bind or if in HOME directory
    if [[ ! "$dir" =~ ^/nix/ ]] && [[ ! "$dir" =~ ^$HOME ]]; then
      BWRAP_ARGS+=(--ro-bind "$dir" "$dir")
    fi
  fi
done

# Agent config directories (needed for sessions, settings, etc.)
# These need to be accessible for agent settings, sessions, etc.
mkdir -p "$HOME/.config/opencode" "$HOME/.config/claude" "$HOME/.claude" \
         "$HOME/.cache/opencode" "$HOME/.cache/claude" \
         "$HOME/.local/share/opencode" "$HOME/.local/share/claude" 2>/dev/null || true

# Config directories
if [[ -d "$HOME/.config/opencode" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.config/opencode" "$HOME/.config/opencode")
fi
if [[ -d "$HOME/.config/claude" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.config/claude" "$HOME/.config/claude")
fi
if [[ -d "$HOME/.claude" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.claude" "$HOME/.claude")
fi

# Cache directories
if [[ -d "$HOME/.cache/opencode" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.cache/opencode" "$HOME/.cache/opencode")
fi
if [[ -d "$HOME/.cache/claude" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.cache/claude" "$HOME/.cache/claude")
fi

# Data/state directories (sessions stored here)
if [[ -d "$HOME/.local/share/opencode" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.local/share/opencode" "$HOME/.local/share/opencode")
fi
if [[ -d "$HOME/.local/share/claude" ]]; then
  BWRAP_ARGS+=(--bind "$HOME/.local/share/claude" "$HOME/.local/share/claude")
fi

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
exec "$BWRAP" "${BWRAP_ARGS[@]}" "$@"
