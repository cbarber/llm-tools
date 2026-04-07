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
#   AGENT_SANDBOX_BIND_HOME - "true" to allow writes to entire home dir (breaks isolation)
#   AGENT_SANDBOX_SSH       - "true" to allow reads+writes to ~/.ssh (for git operations)
#   SANDBOX_EXTRA_RO        - colon-separated additional read-only paths
#   SANDBOX_EXTRA_RW        - colon-separated additional read-write paths
#   BWRAP_EXTRA_PATHS       - deprecated alias for SANDBOX_EXTRA_RW

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

SANDBOX_MOUNTS_RO=()
SANDBOX_MOUNTS_RW=()

AGENT_GITCONFIG_PATH=$(mktemp /tmp/agent-gitconfig-XXXXXX)
mkdir -p "$HOME/.config/nixsmith" 2>/dev/null || true
# shellcheck source=common-helpers.sh
source "${TOOLS_DIR:-$(dirname "$0")}/common-helpers.sh"
# shellcheck source=setup-sandbox-paths.sh
source "${TOOLS_DIR:-$(dirname "$0")}/setup-sandbox-paths.sh"

BWRAP_ARGS=(
  --dev-bind /dev /dev
  --proc /proc
  --unshare-all
  --share-net
  --die-with-parent
  --setenv PATH "$PATH"
  --setenv IN_AGENT_SANDBOX "1"
  --setenv AGENT_WORK_DIR /tmp
  --setenv GITHUB_TOKEN_FILE "${GITHUB_TOKEN_FILE:-}"
  --setenv NIXSMITH_SANDBOX_RO "${NIXSMITH_SANDBOX_RO:-}"
  --setenv NIXSMITH_SANDBOX_RW "${NIXSMITH_SANDBOX_RW:-}"
)

add_mount_ro "/nix"
add_mount_rw "$(pwd)"
add_mount_rw "/tmp"

if git rev-parse --git-dir >/dev/null 2>&1; then
  debug_sandbox "Git repository detected"

  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  if [[ -n "$git_dir" ]]; then
    git_dir_abs=$(cd "$(pwd)" && cd "$git_dir" && pwd)
    debug_sandbox "Git dir: $git_dir_abs"

    if [[ -d "$git_dir_abs" ]]; then
      add_mount_rw "$git_dir_abs"
      debug_sandbox "Mounted git dir (RW): $git_dir_abs"

      common_git_dir=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
      if [[ -n "$common_git_dir" ]]; then
        common_git_dir_abs=$(cd "$(pwd)" && cd "$common_git_dir" && pwd)
        debug_sandbox "Common git dir: $common_git_dir_abs"

        if [[ "$common_git_dir_abs" != "$git_dir_abs" ]] && [[ -d "$common_git_dir_abs" ]]; then
          add_mount_rw "$common_git_dir_abs"
          debug_sandbox "Mounted common git dir (RW): $common_git_dir_abs"

          repo_root=$(dirname "$common_git_dir_abs")
          pwd_path="$(pwd)"
          if [[ "$repo_root" != "$pwd_path" ]]; then
            add_mount_ro "$repo_root"
            debug_sandbox "Mounted repo root (RO): $repo_root"
          fi
        fi
      fi
    fi
  fi
fi

[[ -d /etc/static/nix ]] && add_mount_ro "/etc/static/nix"
[[ -d /etc/nix ]] && add_mount_ro "/etc/nix"
[[ -d /etc/ssl ]] && add_mount_ro "/etc/ssl"
[[ -d /etc/pki ]] && add_mount_ro "/etc/pki"
[[ -d /etc/static/ssl ]] && add_mount_ro "/etc/static/ssl"
[[ -f /etc/resolv.conf ]] && add_mount_ro "/etc/resolv.conf"
[[ -f /etc/hosts ]] && add_mount_ro "/etc/hosts"
[[ -d /usr/bin ]] && add_mount_ro "/usr/bin"
[[ -f /etc/passwd ]] && add_mount_ro "/etc/passwd"
[[ -f /etc/group ]] && add_mount_ro "/etc/group"

IFS=':' read -ra PATH_DIRS <<<"$PATH"
for dir in "${PATH_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    if [[ ! "$dir" =~ ^/nix/ ]] && [[ ! "$dir" =~ ^$HOME ]]; then
      SANDBOX_MOUNTS_RO+=("$dir")
    fi
  fi
done

if [[ -d /bin ]]; then
  path_has_bin=false
  for dir in "${PATH_DIRS[@]}"; do
    [[ "$dir" == "/bin" ]] && path_has_bin=true && break
  done
  [[ "$path_has_bin" == "false" ]] && add_mount_ro "/bin"
fi

for lib_dir in /lib /lib64 /lib32 /usr/lib /usr/lib64 /usr/lib32; do
  [[ -d "$lib_dir" ]] && add_mount_ro "$lib_dir"
done



build_mounts() {
  local mode=$1
  shift
  local mounts=("$@")

  for mount in "${mounts[@]}"; do
    [[ -z "$mount" ]] && continue

    IFS=':' read -r src dest <<<"$mount"
    [[ -z "$dest" ]] && dest="$src"

    src="${src/#\~/$HOME}"
    dest="${dest/#\~/$HOME}"

    [[ ! -e "$src" ]] && continue

    if [[ "$src" != "$dest" ]]; then
      local parent
      parent=$(dirname "$dest")
      BWRAP_ARGS+=(--dir "$parent")
    fi

    if [[ "$mode" == "rw" ]]; then
      BWRAP_ARGS+=(--bind "$src" "$dest")
    else
      BWRAP_ARGS+=(--ro-bind "$src" "$dest")
    fi
  done
}

build_mounts ro "${SANDBOX_MOUNTS_RO[@]}"
build_mounts rw "${SANDBOX_MOUNTS_RW[@]}"

# RO overlay after RW mounts so it takes precedence — agents must not override identity
if [[ -n "${common_git_dir_abs:-}" ]] && [[ -f "$common_git_dir_abs/config" ]]; then
  BWRAP_ARGS+=(--ro-bind "$common_git_dir_abs/config" "$common_git_dir_abs/config")
  debug_sandbox "Overlaid git config read-only: $common_git_dir_abs/config"
elif [[ -n "${git_dir_abs:-}" ]] && [[ -f "$git_dir_abs/config" ]]; then
  BWRAP_ARGS+=(--ro-bind "$git_dir_abs/config" "$git_dir_abs/config")
  debug_sandbox "Overlaid git config read-only: $git_dir_abs/config"
fi

exec "$BWRAP" "${BWRAP_ARGS[@]}" "$@"
