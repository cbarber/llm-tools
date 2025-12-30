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
#   BWRAP_EXTRA_PATHS       - Colon-separated agent/project-specific paths (e.g., ~/.config/myagent)

set -euo pipefail

# Debug logging (controlled by AGENT_DEBUG env var)
debug_sandbox() {
  if [[ "${AGENT_DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG $(date +%H:%M:%S)] agent-sandbox: $*" >&2
  fi
}

debug_sandbox "=========================================="
debug_sandbox "Sandbox script started"
debug_sandbox "Command: $*"
debug_sandbox "HOME: $HOME"
debug_sandbox "PWD: $(pwd)"
debug_sandbox "=========================================="

# Platform detection
PLATFORM="$(uname -s)"

if [[ "$PLATFORM" == "Darwin" ]]; then
  # macOS: use sandbox-exec
  source "$(dirname "${BASH_SOURCE[0]}")/macos-sandbox.sh"
  exit $?
elif [[ "$PLATFORM" != "Linux" ]]; then
  # Unsupported platform: run command directly without sandboxing
  echo "Warning: Sandboxing not supported on $PLATFORM, running without isolation" >&2
  exec "$@"
fi

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

# SSL/TLS certificates (required for HTTPS and nix operations)
if [[ -d /etc/ssl ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/ssl /etc/ssl)
fi
if [[ -d /etc/pki ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/pki /etc/pki)
fi
if [[ -d /etc/static/ssl ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/static/ssl /etc/static/ssl)
fi

# DNS resolution (required for network operations)
# Note: macOS sandbox allows global file-read* which includes these files
if [[ -f /etc/resolv.conf ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/resolv.conf /etc/resolv.conf)
fi
if [[ -f /etc/hosts ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/hosts /etc/hosts)
fi

# User/group information (needed for SSH username lookup)
if [[ -f /etc/passwd ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/passwd /etc/passwd)
fi
if [[ -f /etc/group ]]; then
  BWRAP_ARGS+=(--ro-bind /etc/group /etc/group)
fi

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

# Create nixsmith config directory (always needed for agent auth)
mkdir -p "$HOME/.config/nixsmith" 2>/dev/null || true

# Config directories
debug_sandbox "Checking config directories..."
if [[ -d "$HOME/.config/opencode" ]]; then
  debug_sandbox "  Mounting $HOME/.config/opencode"
  BWRAP_ARGS+=(--bind "$HOME/.config/opencode" "$HOME/.config/opencode")
else
  debug_sandbox "  SKIP: $HOME/.config/opencode does not exist"
fi
if [[ -f "$HOME/.claude.json" ]]; then
  debug_sandbox "  Mounting $HOME/.claude.json"
  BWRAP_ARGS+=(--bind "$HOME/.claude.json" "$HOME/.claude.json")
else
  debug_sandbox "  SKIP: $HOME/.config/claude does not exist"
fi
if [[ -d "$HOME/.claude" ]]; then
  debug_sandbox "  Mounting $HOME/.claude"
  BWRAP_ARGS+=(--bind "$HOME/.claude" "$HOME/.claude")
else
  debug_sandbox "  SKIP: $HOME/.claude does not exist"
fi
if [[ -d "$HOME/.config/nixsmith" ]]; then
  debug_sandbox "  Mounting $HOME/.config/nixsmith"
  BWRAP_ARGS+=(--bind "$HOME/.config/nixsmith" "$HOME/.config/nixsmith")
else
  debug_sandbox "  SKIP: $HOME/.config/nixsmith does not exist"
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

# Agent SSH keys for git operations
if [[ -f "$HOME/.ssh/agent-github" ]]; then
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-github" "$HOME/.ssh/agent-github")
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-github.pub" "$HOME/.ssh/agent-github.pub")
fi
if [[ -f "$HOME/.ssh/agent-gitlab" ]]; then
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitlab" "$HOME/.ssh/agent-gitlab")
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitlab.pub" "$HOME/.ssh/agent-gitlab.pub")
fi
if [[ -f "$HOME/.ssh/agent-gitea" ]]; then
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitea" "$HOME/.ssh/agent-gitea")
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitea.pub" "$HOME/.ssh/agent-gitea.pub")
fi

# SSH config for agent keys
# Mount agent config AS the SSH config (replaces personal config in sandbox)
# This keeps your personal SSH config private and prevents conflicts
if [[ -f "$HOME/.ssh/config.agent" ]]; then
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/config.agent" "$HOME/.ssh/config")
fi

# SSH known_hosts for host key verification
if [[ -f "$HOME/.ssh/known_hosts" ]]; then
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts")
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

# Common language tooling cache directories (only mount if they exist)
# These are shared across all agents for build caching
LANGUAGE_CACHE_PATHS=(
  "$HOME/.cache/go-build"
  "$HOME/.cargo"
  "$HOME/.cache/pip"
  "$HOME/.gem"
  "$HOME/.cache/yarn"
  "$HOME/.npm"
  "$HOME/.local/share/pnpm"
  "$HOME/.bun"
)

for cache_path in "${LANGUAGE_CACHE_PATHS[@]}"; do
  if [[ -d "$cache_path" ]]; then
    BWRAP_ARGS+=(--bind "$cache_path" "$cache_path")
  fi
done

# Extra paths for agent-specific or project-specific needs
# Format: BWRAP_EXTRA_PATHS="/path/one:/path/two:~/path/three"
# Only mounts paths that already exist (does not create them)
if [[ -n "${BWRAP_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -ra EXTRA_PATHS <<< "$BWRAP_EXTRA_PATHS"
  for path in "${EXTRA_PATHS[@]}"; do
    # Expand tilde to home directory
    expanded_path="${path/#\~/$HOME}"
    
    # Skip empty paths
    [[ -z "$expanded_path" ]] && continue
    
    # Bind mount only if directory exists
    if [[ -d "$expanded_path" ]]; then
      BWRAP_ARGS+=(--bind "$expanded_path" "$expanded_path")
    fi
  done
fi

# Run command in sandbox
exec "$BWRAP" "${BWRAP_ARGS[@]}" "$@"
