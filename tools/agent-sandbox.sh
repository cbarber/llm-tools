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

# Detect and report sandbox blockers with OS-specific instructions
detect_sandbox_blocker() {
  # Quick test - if bwrap works, no blocker
  if "$BWRAP" --ro-bind / / true 2>/dev/null; then
    return 0
  fi

  # AppArmor userns restriction (Ubuntu 23.10+, Debian 12+)
  if [[ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)" == "1" ]]; then
    echo "apparmor_userns"
    return 1
  fi

  # Kernel disables unprivileged userns
  if [[ "$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null)" == "0" ]]; then
    echo "kernel_userns"
    return 1
  fi

  # SELinux enforcing
  if command -v getenforce &>/dev/null && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
    echo "selinux"
    return 1
  fi

  # Inside container
  if [[ -f /.dockerenv ]] || grep -qE 'docker|lxc|kubepods' /proc/1/cgroup 2>/dev/null; then
    echo "container"
    return 1
  fi

  echo "unknown"
  return 1
}

print_blocker_instructions() {
  local blocker="$1"
  local bwrap_path="$BWRAP"

  echo "" >&2
  echo "═══════════════════════════════════════════════════════════════════" >&2
  echo "  Sandbox Setup Required" >&2
  echo "═══════════════════════════════════════════════════════════════════" >&2
  echo "" >&2

  case "$blocker" in
  apparmor_userns)
    cat >&2 <<EOF
Your system uses AppArmor to restrict user namespaces (Ubuntu 23.10+).
bubblewrap needs an AppArmor profile to create sandboxes.

Option 1: Create AppArmor profile for bwrap (recommended)
─────────────────────────────────────────────────────────
  sudo tee /etc/apparmor.d/bwrap << 'PROFILE'
abi <abi/4.0>,
include <tunables/global>

profile bwrap $bwrap_path flags=(unconfined) {
  userns,
}
PROFILE

  sudo apparmor_parser -r /etc/apparmor.d/bwrap

Note: The Nix store path changes on updates. You may need to update
the profile path after running 'nix flake update'. A wildcard profile
for /nix/store/*/bin/bwrap is more maintainable:

  sudo tee /etc/apparmor.d/nix-bwrap << 'PROFILE'
abi <abi/4.0>,
include <tunables/global>

profile nix-bwrap /nix/store/*/bin/bwrap flags=(unconfined) {
  userns,
}
PROFILE

  sudo apparmor_parser -r /etc/apparmor.d/nix-bwrap

Option 2: Run without sandbox
─────────────────────────────
  AGENT_SANDBOX=false nix develop .#claude-code

EOF
    ;;

  kernel_userns)
    cat >&2 <<EOF
Your kernel has unprivileged user namespaces disabled.
bubblewrap requires this feature for sandboxing.

Enable user namespaces:
───────────────────────
  sudo sysctl -w kernel.unprivileged_userns_clone=1

To persist across reboots:
  echo 'kernel.unprivileged_userns_clone=1' | sudo tee /etc/sysctl.d/50-userns.conf
  sudo sysctl --system

Or run without sandbox:
  AGENT_SANDBOX=false nix develop .#claude-code

EOF
    ;;

  selinux)
    cat >&2 <<EOF
SELinux is blocking bubblewrap from creating user namespaces.

Option 1: Create SELinux policy for bwrap
─────────────────────────────────────────
  # Generate policy module (requires policycoreutils-python-utils)
  sudo ausearch -c bwrap --raw | audit2allow -M bwrap-sandbox
  sudo semodule -i bwrap-sandbox.pp

Option 2: Set bwrap to permissive (less secure)
───────────────────────────────────────────────
  sudo semanage permissive -a bwrap_t

Or run without sandbox:
  AGENT_SANDBOX=false nix develop .#claude-code

EOF
    ;;

  container)
    cat >&2 <<EOF
You're running inside a container (Docker/LXC/Kubernetes).
Nested user namespaces are typically restricted by the container runtime.

Options:
────────
1. Run the container with --privileged (not recommended)
2. Add specific capabilities: --cap-add SYS_ADMIN --security-opt seccomp=unconfined
3. Run without sandbox (agent will have container-level isolation):
   AGENT_SANDBOX=false nix develop .#claude-code

EOF
    ;;

  *)
    cat >&2 <<EOF
bubblewrap failed to create a sandbox for an unknown reason.

Debug information:
──────────────────
  bwrap path: $bwrap_path
  Error: $("$BWRAP" --ro-bind / / true 2>&1 || true)

Run without sandbox:
  AGENT_SANDBOX=false nix develop .#claude-code

Please report this issue with the above details at:
  https://github.com/cbarber/llm-tools/issues

EOF
    ;;
  esac

  echo "═══════════════════════════════════════════════════════════════════" >&2
  echo "" >&2
}

# Test if bwrap actually works before proceeding
if ! blocker=$(detect_sandbox_blocker); then
  print_blocker_instructions "$blocker"
  exit 1
fi

# Initialize mount arrays (Docker-style source:dest syntax)
# Format: "source" or "source:dest" (if dest is omitted, uses source as dest)
SANDBOX_MOUNTS_RO=()
SANDBOX_MOUNTS_RW=()

# Build bwrap command
BWRAP_ARGS=(
  # Essential system directories
  --dev-bind /dev /dev
  --proc /proc

  # Namespace isolation
  --unshare-all
  --share-net # Allow network access

  # Die with parent (cleanup if parent dies)
  --die-with-parent

  # Preserve PATH and mark that we're in sandbox
  --setenv PATH "$PATH"
  --setenv IN_AGENT_SANDBOX "1"
  --setenv AGENT_WORK_DIR /tmp
)

# Core read-only system mounts
SANDBOX_MOUNTS_RO+=("/nix")

# Core read-write mounts
SANDBOX_MOUNTS_RW+=("$(pwd)")
SANDBOX_MOUNTS_RW+=("/tmp")

# Git directory discovery and mounting
# Use git commands to discover git directories, then mount repo root + git directories
# This allows git to traverse from CWD up to the repository without hitting filesystem boundaries
if git rev-parse --git-dir >/dev/null 2>&1; then
  debug_sandbox "Git repository detected"

  # Get the git directory for this worktree/repo
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  if [[ -n "$git_dir" ]]; then
    # Resolve to absolute path (may be relative like ".git")
    git_dir_abs=$(cd "$(pwd)" && cd "$git_dir" && pwd)
    debug_sandbox "Git dir: $git_dir_abs"

    # Mount the git directory (read-write for commit/push/pull)
    if [[ -d "$git_dir_abs" ]]; then
      SANDBOX_MOUNTS_RW+=("$git_dir_abs")
      debug_sandbox "Mounted git dir (RW): $git_dir_abs"

      # Get the common git dir (shared objects, refs, config for worktrees)
      # For regular repos, this equals git_dir. For worktrees, points to main repo's .git/
      common_git_dir=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
      if [[ -n "$common_git_dir" ]]; then
        common_git_dir_abs=$(cd "$(pwd)" && cd "$common_git_dir" && pwd)
        debug_sandbox "Common git dir: $common_git_dir_abs"

        # Only mount if different from worktree's git dir
        if [[ "$common_git_dir_abs" != "$git_dir_abs" ]] && [[ -d "$common_git_dir_abs" ]]; then
          SANDBOX_MOUNTS_RW+=("$common_git_dir_abs")
          debug_sandbox "Mounted common git dir (RW): $common_git_dir_abs"

          # Mount the repo root (parent of the bare/common repo)
          # This allows git to traverse from worktree to bare repo
          repo_root=$(dirname "$common_git_dir_abs")
          pwd_path="$(pwd)"
          if [[ "$repo_root" != "$pwd_path" ]]; then
            SANDBOX_MOUNTS_RO+=("$repo_root")
            debug_sandbox "Mounted repo root (RO): $repo_root"
          fi
        fi
      fi
    fi
  fi
fi

# Nix configuration (required for nix-shell, flakes, etc.)
# NixOS uses /etc/static/nix with symlinks from /etc/nix
[[ -d /etc/static/nix ]] && SANDBOX_MOUNTS_RO+=("/etc/static/nix")
[[ -d /etc/nix ]] && SANDBOX_MOUNTS_RO+=("/etc/nix")

# SSL/TLS certificates (required for HTTPS and nix operations)
[[ -d /etc/ssl ]] && SANDBOX_MOUNTS_RO+=("/etc/ssl")
[[ -d /etc/pki ]] && SANDBOX_MOUNTS_RO+=("/etc/pki")
[[ -d /etc/static/ssl ]] && SANDBOX_MOUNTS_RO+=("/etc/static/ssl")

# DNS resolution (required for network operations)
[[ -f /etc/resolv.conf ]] && SANDBOX_MOUNTS_RO+=("/etc/resolv.conf")
[[ -f /etc/hosts ]] && SANDBOX_MOUNTS_RO+=("/etc/hosts")

# Mount /usr/bin if it exists (required for shebangs like #!/usr/bin/env)
[[ -d /usr/bin ]] && SANDBOX_MOUNTS_RO+=("/usr/bin")

# User/group information (needed for SSH username lookup)
[[ -f /etc/passwd ]] && SANDBOX_MOUNTS_RO+=("/etc/passwd")
[[ -f /etc/group ]] && SANDBOX_MOUNTS_RO+=("/etc/group")

# Bind mount all directories in PATH (read-only)
# This ensures all commands available to the parent are available in the sandbox
IFS=':' read -ra PATH_DIRS <<<"$PATH"
for dir in "${PATH_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    # Skip if already covered by /nix bind or if in HOME directory
    if [[ ! "$dir" =~ ^/nix/ ]] && [[ ! "$dir" =~ ^$HOME ]]; then
      SANDBOX_MOUNTS_RO+=("$dir")
    fi
  fi
done

# System library directories (required for dynamic linking of system binaries)
for lib_dir in /lib /lib64 /lib32 /usr/lib /usr/lib64 /usr/lib32; do
  [[ -d "$lib_dir" ]] && SANDBOX_MOUNTS_RO+=("$lib_dir")
done

# Create nixsmith config directory (always needed for agent auth)
mkdir -p "$HOME/.config/nixsmith" 2>/dev/null || true

# Git config (resolve symlinks to actual target)
# Git reads both XDG and legacy configs if both exist, in that order
if [[ -e "$HOME/.config/git/config" ]]; then
  xdg_gitconfig_target=$(readlink -f "$HOME/.config/git/config")
  SANDBOX_MOUNTS_RO+=("$xdg_gitconfig_target:$HOME/.config/git/config")
fi
if [[ -e "$HOME/.gitconfig" ]]; then
  gitconfig_target=$(readlink -f "$HOME/.gitconfig")
  gitconfig_dir=$(dirname "$gitconfig_target")
  SANDBOX_MOUNTS_RO+=("$gitconfig_target:$HOME/.gitconfig")

  # Mount files referenced by includeIf directives
  while IFS= read -r include_path; do
    # Expand tilde to $HOME
    expanded_path="${include_path/#\~/$HOME}"

    # If path is relative, resolve it relative to gitconfig's directory
    if [[ "$expanded_path" != /* ]]; then
      expanded_path="$gitconfig_dir/$expanded_path"
    fi

    resolved_path=$(readlink -f "$expanded_path" 2>/dev/null || echo "$expanded_path")

    [[ -f "$resolved_path" ]] && SANDBOX_MOUNTS_RO+=("$resolved_path")
  done < <(grep -A1 '^\[includeIf' "$gitconfig_target" 2>/dev/null | grep 'path =' | sed 's/.*path = //' | tr -d ' ')
fi

# Config directories
debug_sandbox "Checking config directories..."
for config_dir in "$HOME/.config/opencode" "$HOME/.config/nixsmith"; do
  if [[ -d "$config_dir" ]]; then
    debug_sandbox "  Mounting $config_dir"
    SANDBOX_MOUNTS_RW+=("$config_dir")
  else
    debug_sandbox "  SKIP: $config_dir does not exist"
  fi
done

[[ -f "$HOME/.claude.json" ]] && SANDBOX_MOUNTS_RW+=("$HOME/.claude.json")
[[ -d "$HOME/.claude" ]] && SANDBOX_MOUNTS_RW+=("$HOME/.claude")

# Cache directories
[[ -d "$HOME/.cache/opencode" ]] && SANDBOX_MOUNTS_RW+=("$HOME/.cache/opencode")
[[ -d "$HOME/.cache/claude" ]] && SANDBOX_MOUNTS_RW+=("$HOME/.cache/claude")

# Data/state directories (sessions stored here)
[[ -d "$HOME/.local/share/opencode" ]] && SANDBOX_MOUNTS_RW+=("$HOME/.local/share/opencode")
[[ -d "$HOME/.local/share/claude" ]] && SANDBOX_MOUNTS_RW+=("$HOME/.local/share/claude")

# Agent SSH keys for git operations
[[ -f "$HOME/.ssh/agent-github" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/agent-github" "$HOME/.ssh/agent-github.pub")
[[ -f "$HOME/.ssh/agent-gitlab" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/agent-gitlab" "$HOME/.ssh/agent-gitlab.pub")
[[ -f "$HOME/.ssh/agent-gitea" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/agent-gitea" "$HOME/.ssh/agent-gitea.pub")

# SSH config for agent keys (mount agent config AS the SSH config)
[[ -f "$HOME/.ssh/config.agent" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/config.agent:$HOME/.ssh/config")

# SSH known_hosts for host key verification
[[ -f "$HOME/.ssh/known_hosts" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/known_hosts")

# Optional: bind mount SSH keys for git authentication
if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]] && [[ -d "$HOME/.ssh" ]]; then
  SANDBOX_MOUNTS_RO+=("$HOME/.ssh")
fi

# Optional: bind mount entire home (breaks isolation, use with caution)
if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  echo "Warning: Binding \$HOME breaks sandbox isolation" >&2
  SANDBOX_MOUNTS_RW+=("$HOME")
fi

# Common language tooling cache directories
for cache_path in "$HOME/.cache/go-build" "$HOME/.cargo" "$HOME/.cache/pip" "$HOME/.gem" "$HOME/.cache/yarn" "$HOME/.npm" "$HOME/.local/share/pnpm" "$HOME/.bun"; do
  [[ -d "$cache_path" ]] && SANDBOX_MOUNTS_RW+=("$cache_path")
done

# User customization via env vars (Docker-style syntax)
# SANDBOX_EXTRA_RO="/path/one:/path/two:~/path/three"
# SANDBOX_EXTRA_RW="/workspace:/data"
if [[ -n "${SANDBOX_EXTRA_RO:-}" ]]; then
  IFS=':' read -ra EXTRA_RO <<<"$SANDBOX_EXTRA_RO"
  SANDBOX_MOUNTS_RO+=("${EXTRA_RO[@]}")
fi

if [[ -n "${SANDBOX_EXTRA_RW:-}" ]]; then
  IFS=':' read -ra EXTRA_RW <<<"$SANDBOX_EXTRA_RW"
  SANDBOX_MOUNTS_RW+=("${EXTRA_RW[@]}")
fi

# Backward compatibility: BWRAP_EXTRA_PATHS (deprecated, use SANDBOX_EXTRA_RW)
if [[ -n "${BWRAP_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -ra EXTRA_PATHS <<<"$BWRAP_EXTRA_PATHS"
  SANDBOX_MOUNTS_RW+=("${EXTRA_PATHS[@]}")
fi

# Workaround: Agent hook systems may spawn /bin/sh which doesn't exist on NixOS
# Add /bin/sh mount if needed (cross-platform via mount array)
if [[ "${CLAUDECODE:-}" == "1" ]] || [[ "${OPENCODE:-}" == "1" ]]; then
  SH_PATH="$(command -v sh)"
  if [[ -n "$SH_PATH" && -x "$SH_PATH" ]]; then
    SANDBOX_MOUNTS_RO+=("$SH_PATH:/bin/sh")
  fi
fi

# Build mount arguments from arrays (Docker-style source:dest syntax)
build_mounts() {
  local mode=$1
  shift
  local mounts=("$@")
  local pwd_path="$(pwd)"

  for mount in "${mounts[@]}"; do
    # Skip empty entries
    [[ -z "$mount" ]] && continue

    # Parse source:dest (if no colon, dest = source)
    IFS=':' read -r src dest <<<"$mount"
    [[ -z "$dest" ]] && dest="$src"

    # Expand tilde in paths
    src="${src/#\~/$HOME}"
    dest="${dest/#\~/$HOME}"

    # Skip if source doesn't exist
    [[ ! -e "$src" ]] && continue

    # Create parent directory if needed for remapped paths
    # Only needed when src != dest (remapped paths like gitconfig)
    if [[ "$src" != "$dest" ]]; then
      local parent=$(dirname "$dest")
      BWRAP_ARGS+=(--dir "$parent")
    fi

    # Add the mount
    if [[ "$mode" == "rw" ]]; then
      BWRAP_ARGS+=(--bind "$src" "$dest")
    else
      BWRAP_ARGS+=(--ro-bind "$src" "$dest")
    fi
  done
}

# Build all mounts
build_mounts ro "${SANDBOX_MOUNTS_RO[@]}"
build_mounts rw "${SANDBOX_MOUNTS_RW[@]}"

# Run command in sandbox
exec "$BWRAP" "${BWRAP_ARGS[@]}" "$@"
