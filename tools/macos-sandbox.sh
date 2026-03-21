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

# Pass the canonical path so the (literal) deny rule matches regardless of
# whether the caller is inside a symlinked path.
GIT_CONFIG_PATH="$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null)/config" || true
if [[ -f "$GIT_CONFIG_PATH" ]]; then
  GIT_CONFIG_CANONICAL="$(cd "$(dirname "$GIT_CONFIG_PATH")" && pwd -P)/config"
  SANDBOX_PARAMS+=("-DGIT_CONFIG=$GIT_CONFIG_CANONICAL")
else
  # No git repo — point at a non-existent path so the param is always defined.
  SANDBOX_PARAMS+=("-DGIT_CONFIG=$PROJECT_DIR/.git/config")
fi

# sandbox-exec SIGABRTs when (subpath ...) references a non-existent path,
# so only emit rules for paths that exist on disk.

append_gitconfig_read_paths() {
  local canonical="$1"
  local real dir
  real=$(readlink -f "$canonical")
  dir=$(dirname "$real")

  HOME_READ_PATHS+=("$real")

  while IFS= read -r include_path; do
    local expanded="${include_path/#\~/$HOME}"
    [[ "$expanded" != /* ]] && expanded="$dir/$expanded"
    local resolved
    resolved=$(readlink -f "$expanded" 2>/dev/null || echo "$expanded")
    [[ -f "$resolved" ]] && HOME_READ_PATHS+=("$resolved")
  done < <(grep -A1 '^\[include' "$real" 2>/dev/null | grep 'path =' | sed 's/.*path = //' | tr -d ' ')
}

# Read access: git identity files and agent-specific keys (mirrors bwrap RO mounts).
HOME_READ_PATHS=(
  "$HOME/.gitconfig"
  "$HOME/.config/git/config"
  "$HOME/.ssh/known_hosts"
  "$HOME/.ssh/config.agent"
  "$HOME/.ssh/agent-github"
  "$HOME/.ssh/agent-github.pub"
  "$HOME/.ssh/agent-gitlab"
  "$HOME/.ssh/agent-gitlab.pub"
  "$HOME/.ssh/agent-gitea"
  "$HOME/.ssh/agent-gitea.pub"
  "$HOME/.config/nix"
  "$HOME/.local/share/nix"
)

[[ -e "$HOME/.config/git/config" ]] && append_gitconfig_read_paths "$HOME/.config/git/config"
[[ -e "$HOME/.gitconfig" ]]         && append_gitconfig_read_paths "$HOME/.gitconfig"
HOME_READ_RULES=""
for i in "${!HOME_READ_PATHS[@]}"; do
  p="${HOME_READ_PATHS[$i]}"
  [[ -e "$p" ]] || continue
  PARAM_NAME="HOME_READ_$i"
  HOME_READ_RULES+="  (subpath (param \"$PARAM_NAME\"))"$'\n'
  SANDBOX_PARAMS+=("-D$PARAM_NAME=$p")
done
if [[ -n "$HOME_READ_RULES" ]]; then
  PROFILE_CONTENT+=$'\n(allow file-read*\n'"$HOME_READ_RULES"')'
fi

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
if [[ -n "$HOME_TRAVERSE_RULES" ]]; then
  PROFILE_CONTENT+=$'\n(allow file-read*\n'"$HOME_TRAVERSE_RULES"')'
fi

# Write access: agent config and cache dirs.
HOME_WRITE_PATHS=(
  "$HOME/.config/opencode"
  "$HOME/.config/nixsmith"
  "$HOME/.claude.json"
  "$HOME/.claude"
  "$HOME/.cache/opencode"
  "$HOME/.cache/claude"
  "$HOME/.cache/nix"
  "$HOME/.local/share/opencode"
  "$HOME/.local/share/claude"
  "$HOME/go"
  "$HOME/.cache/go-build"
  "$HOME/.cargo"
  "$HOME/.cache/pip"
  "$HOME/.gem"
  "$HOME/.cache/yarn"
  "$HOME/.npm"
  "$HOME/.local/share/pnpm"
  "$HOME/.bun"
  "$HOME/.gradle"
  "$HOME/.m2"
  "$HOME/.composer"
  "$HOME/.cache/composer"
  "$HOME/.nuget/packages"
  "$HOME/.vcpkg"
  "$HOME/.pub-cache"
  "$HOME/.swiftpm"
  "$HOME/.hex"
  "$HOME/.mix"
)
HOME_WRITE_RULES=""
for i in "${!HOME_WRITE_PATHS[@]}"; do
  p="${HOME_WRITE_PATHS[$i]}"
  [[ -e "$p" ]] || continue
  PARAM_NAME="HOME_WRITE_$i"
  HOME_WRITE_RULES+="  (subpath (param \"$PARAM_NAME\"))"$'\n'
  SANDBOX_PARAMS+=("-D$PARAM_NAME=$p")
done
if [[ -n "$HOME_WRITE_RULES" ]]; then
  # Agents must be able to read the dirs they write (e.g. load config before updating it).
  PROFILE_CONTENT+=$'\n(allow file-read* file-write*\n'"$HOME_WRITE_RULES"')'
fi

_append_path_rules() {
  local permission="$1" var="$2"
  [[ -z "${!var:-}" ]] && return
  local rules="" i=0 path expanded
  IFS=':' read -ra paths <<< "${!var}"
  for path in "${paths[@]}"; do
    expanded="${path/#\~/$HOME}"
    [[ -z "$expanded" ]] && continue
    [[ -e "$expanded" ]] || continue
    local pname="${var}_$i"
    rules+="  (subpath (param \"$pname\"))"$'\n'
    SANDBOX_PARAMS+=("-D$pname=$expanded")
    (( i++ )) || true
  done
  [[ -n "$rules" ]] && PROFILE_CONTENT+=$'\n('"$permission"$'\n'"$rules"')'
}

_append_path_rules "allow file-read*" SANDBOX_EXTRA_RO
_append_path_rules "allow file-read* file-write*" SANDBOX_EXTRA_RW
# Backward compatibility
_append_path_rules "allow file-read* file-write*" BWRAP_EXTRA_PATHS

if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  echo "Warning: AGENT_SANDBOX_BIND_HOME=true grants full home directory write access (breaks isolation)" >&2
  SANDBOX_PARAMS+=("-DHOME_FULL=$HOME")
  PROFILE_CONTENT+=$'\n(allow file-write* (subpath (param "HOME_FULL")))'
fi

# AGENT_SANDBOX_SSH overrides the profile's deny on ~/.ssh, restoring both
# reads and writes so git operations that require the SSH key can work.
if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]]; then
  echo "Warning: AGENT_SANDBOX_SSH=true grants full ~/.ssh read+write access" >&2
  PROFILE_CONTENT+=$'\n(allow file-read* file-write* (subpath (param "HOME_SSH")))'
fi

# Create agent config directories if they don't exist
mkdir -p "$HOME/.config/opencode" "$HOME/.config/claude" "$HOME/.claude" \
         "$HOME/.config/nixsmith" \
         "$HOME/.cache/opencode" "$HOME/.cache/claude" \
         "$HOME/.local/share/opencode" "$HOME/.local/share/claude" 2>/dev/null || true

export AGENT_WORK_DIR="$WORK_DIR_CANONICAL"
export IN_AGENT_SANDBOX="1"

# Export token eagerly so all git operations can use it, not just spr
GITHUB_TOKEN_FILE="$HOME/.config/nixsmith/github-token"
if [[ -f "$GITHUB_TOKEN_FILE" ]]; then
  GITHUB_TOKEN=$(<"$GITHUB_TOKEN_FILE")
  export GITHUB_TOKEN
fi

# Generate a session gitconfig that routes GitHub traffic through the PAT credential
# helper instead of SSH. Our url rules are defined before the includes so they win
# the insteadOf tiebreak when the user's config defines a competing SSH rewrite.
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AGENT_GITCONFIG="$WORK_DIR/agent-gitconfig"
  {
    cat <<EOF
[url "https://github.com/"]
	insteadOf = https://github.com/
	insteadOf = git@github.com:

[credential "https://github.com"]
	helper = !printf 'username=x-access-token\npassword=${GITHUB_TOKEN}\n'

EOF
    [[ -f "$HOME/.config/git/config" ]] && printf '[include]\n\tpath = %s\n' "$HOME/.config/git/config"
    [[ -f "$HOME/.gitconfig" ]]         && printf '[include]\n\tpath = %s\n' "$HOME/.gitconfig"
  } > "$AGENT_GITCONFIG"
  export GIT_CONFIG_GLOBAL="$AGENT_GITCONFIG"
fi

# sandbox-exec cannot remap mounts, so we cannot replace ~/.ssh/config with
# config.agent the way bubblewrap does on Linux. Instead, point GIT_SSH_COMMAND
# at config.agent directly so git uses the agent key without reading ~/.ssh/config.
if [[ -f "$HOME/.ssh/config.agent" ]] && [[ "${AGENT_SANDBOX_SSH:-false}" != "true" ]]; then
  export GIT_SSH_COMMAND="ssh -F $HOME/.ssh/config.agent"
fi

if [[ "${AGENT_SANDBOX_DEBUG:-false}" == "true" ]]; then
  echo "=== Sandbox Profile ===" >&2
  echo "$PROFILE_CONTENT" >&2
  echo "=== Parameters ===" >&2
  printf '%s\n' "${SANDBOX_PARAMS[@]}" >&2
  echo "======================" >&2
fi

exec sandbox-exec -p "$PROFILE_CONTENT" "${SANDBOX_PARAMS[@]}" -- "$@"
