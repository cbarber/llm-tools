#!/usr/bin/env bash
# Shared path discovery for agent sandboxes.
#
# Populates SANDBOX_MOUNTS_RO and SANDBOX_MOUNTS_RW with paths that need to
# be accessible inside the sandbox. The caller (agent-sandbox.sh) turns these
# into fence's allowRead/allowWrite config entries.
#
# Also generates the session gitconfig (GIT_CONFIG_GLOBAL) pointing to the
# git-credential-nixsmith helper, which reads GH_TOKEN env var.
#
# Required by caller before sourcing:
#   AGENT_GITCONFIG_PATH  — where to write the generated gitconfig file
#   extract_github_owner  — function from common-helpers.sh (sourced by caller)

# bwrap bind-mounts paths literally — symlinks must exist inside the sandbox
# at every step of the chain or traversal fails. Mount each link and the target.
add_mount_ro() {
  local target="$1"
  while [[ -L "$target" ]]; do
    SANDBOX_MOUNTS_RO+=("$target")
    target=$(readlink -f "$target" 2>/dev/null) || return 0
  done
  [[ -e "$target" ]] && SANDBOX_MOUNTS_RO+=("$target")
}

add_mount_rw() {
  local target="$1"
  while [[ -L "$target" ]]; do
    SANDBOX_MOUNTS_RW+=("$target")
    target=$(readlink -f "$target" 2>/dev/null) || return 0
  done
  [[ -e "$target" ]] && SANDBOX_MOUNTS_RW+=("$target")
}

add_mount_rw "$(pwd)"

# Git directory discovery — resolved relative to $(pwd) so this works from a
# repository subdirectory, and worktree-aware so linked worktrees (whose
# .git is a file pointing outside the worktree) still get their real git
# dir mounted. Mirrors `git rev-parse --git-dir` / `--git-common-dir`.
if git rev-parse --git-dir >/dev/null 2>&1; then
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  if [[ -n "$git_dir" ]]; then
    git_dir_abs=$(cd "$(pwd)" && cd "$git_dir" && pwd)

    if [[ -d "$git_dir_abs" ]]; then
      add_mount_rw "$git_dir_abs"

      common_git_dir=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
      if [[ -n "$common_git_dir" ]]; then
        common_git_dir_abs=$(cd "$(pwd)" && cd "$common_git_dir" && pwd)

        if [[ "$common_git_dir_abs" != "$git_dir_abs" ]] && [[ -d "$common_git_dir_abs" ]]; then
          add_mount_rw "$common_git_dir_abs"

          repo_root=$(dirname "$common_git_dir_abs")
          pwd_path="$(pwd)"
          if [[ "$repo_root" != "$pwd_path" ]]; then
            add_mount_ro "$repo_root"
          fi
        fi
      fi
    fi
  fi
fi

# Expose PATH directories that live outside /nix and $HOME so commands
# resolved via PATH remain runnable inside the sandbox. /nix is already
# covered by the broader /nix read-only mount; $HOME entries are handled
# by the explicit allow-lists below.
IFS=':' read -ra PATH_DIRS <<<"$PATH"
for path_dir in "${PATH_DIRS[@]}"; do
  if [[ -d "$path_dir" ]] && [[ ! "$path_dir" =~ ^/nix/ ]] && [[ ! "$path_dir" =~ ^$HOME ]]; then
    SANDBOX_MOUNTS_RO+=("$path_dir")
  fi
done
unset PATH_DIRS path_dir

append_gitconfig_mounts() {
  local canonical="$1"
  local real dir
  real=$(readlink -f "$canonical")
  dir=$(dirname "$real")

  [[ "$canonical" != "$real" ]] && SANDBOX_MOUNTS_RO+=("$canonical")
  SANDBOX_MOUNTS_RO+=("$real")

  while IFS= read -r include_path; do
    local expanded="${include_path/#\~/$HOME}"
    [[ "$expanded" != /* ]] && expanded="$dir/$expanded"
    local resolved
    resolved=$(readlink -f "$expanded" 2>/dev/null || echo "$expanded")
    [[ -f "$resolved" ]] && SANDBOX_MOUNTS_RO+=("$resolved")
  done < <(grep -A1 '^\[include' "$real" 2>/dev/null | grep 'path =' | sed 's/.*path = //' | tr -d ' ')
}

xdg_gitconfig_target=""
gitconfig_target=""
[[ -e "$HOME/.config/git/config" ]] && xdg_gitconfig_target="$HOME/.config/git/config"
[[ -e "$HOME/.gitconfig" ]]         && gitconfig_target="$HOME/.gitconfig"

[[ -n "$xdg_gitconfig_target" ]] && append_gitconfig_mounts "$xdg_gitconfig_target"
[[ -n "$gitconfig_target" ]]     && append_gitconfig_mounts "$gitconfig_target"

# Resolve the GitHub token for the current repo's owner.
# Primary source: secrets.json repos entry (GH_TOKEN value).
#
# When the token comes from secrets.json it flows through NIXSMITH_SECRETS_ENV
# as GH_TOKEN; git-credential-nixsmith uses the GH_TOKEN env var.

_nixsmith_secrets_file="${HOME}/.config/nixsmith/secrets.json"
_github_owner=$(extract_github_owner 2>/dev/null || true)
_gh_token_in_secrets=false

if [[ -n "$_github_owner" ]] && [[ -f "$_nixsmith_secrets_file" ]] && command -v jq >/dev/null 2>&1; then
  if jq -e 'has("repos")' "$_nixsmith_secrets_file" >/dev/null 2>&1; then
    _gh_secret=$(jq -r --arg k "github:${_github_owner}" '.repos[$k].GH_TOKEN // empty' "$_nixsmith_secrets_file" 2>/dev/null || true)
    [[ -n "$_gh_secret" ]] && _gh_token_in_secrets=true
    unset _gh_secret
  fi
fi

# Inject synthetic gitconfig when either a token file or secrets.json GH_TOKEN
# is available. The credential helper uses GH_TOKEN env var injected via 
# --setenv by agent-sandbox.sh.
if [[ "$_gh_token_in_secrets" == "true" ]]; then
  {
    cat <<EOF
[url "https://github.com/"]
       insteadOf = https://github.com/
       insteadOf = git@github.com:

[credential "https://github.com"]
       helper = !git-credential-nixsmith

EOF
    [[ -n "$xdg_gitconfig_target" ]] && printf '[include]\n\tpath = %s\n' "$xdg_gitconfig_target"
    [[ -n "$gitconfig_target" ]]     && printf '[include]\n\tpath = %s\n' "$gitconfig_target"
  } > "$AGENT_GITCONFIG_PATH"
  export GIT_CONFIG_GLOBAL="$AGENT_GITCONFIG_PATH"
fi
unset _github_owner _nixsmith_secrets_file _gh_token_in_secrets

if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]]; then
  [[ -d "$HOME/.ssh" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh")
fi

# shellcheck disable=SC2066
for ro_path in \
  "$HOME/.agents"; do
  [[ -e "$ro_path" ]] && SANDBOX_MOUNTS_RO+=("$ro_path")
done

mkdir -p "$HOME/.local/state/opencode" 2>/dev/null || true

for rw_path in \
  "$HOME/.config/opencode" \
  "$HOME/.config/nixsmith" \
  "$HOME/.claude.json" \
  "$HOME/.claude" \
  "$HOME/.cache/opencode" \
  "$HOME/.cache/claude" \
  "$HOME/.cache/composer" \
  "$HOME/.cache/go-build" \
  "$HOME/.cache/nix" \
  "$HOME/.cache/opencode" \
  "$HOME/.cache/pip" \
  "$HOME/.cache/yarn" \
  "$HOME/.cargo" \
  "$HOME/.claude" \
  "$HOME/.claude.json" \
  "$HOME/.composer" \
  "$HOME/.config/nixsmith/iron-proxy" \
  "$HOME/.config/nixsmith/tea" \
  "$HOME/.config/opencode" \
  "$HOME/.gem" \
  "$HOME/.gradle" \
  "$HOME/.hex" \
  "$HOME/.local/share/claude" \
  "$HOME/.local/share/direnv" \
  "$HOME/.local/share/opencode" \
  "$HOME/.local/share/pnpm" \
  "$HOME/.local/state/opencode" \
  "$HOME/.m2" \
  "$HOME/.mix" \
  "$HOME/.npm" \
  "$HOME/.nuget/packages" \
  "$HOME/.pub-cache" \
  "$HOME/.swiftpm" \
  "$HOME/.vcpkg" \
  "$HOME/go" ; do
  [[ -e "$rw_path" ]] && SANDBOX_MOUNTS_RW+=("$rw_path")
done

if [[ -n "${SANDBOX_EXTRA_RO:-}" ]]; then
  IFS=':' read -ra EXTRA_RO <<<"$SANDBOX_EXTRA_RO"
  for path in "${EXTRA_RO[@]}"; do add_mount_ro "$path"; done
fi
if [[ -n "${SANDBOX_EXTRA_RW:-}" ]]; then
  IFS=':' read -ra EXTRA_RW <<<"$SANDBOX_EXTRA_RW"
  for path in "${EXTRA_RW[@]}"; do add_mount_rw "$path"; done
fi

# ---------------------------------------------------------------------------
# secrets.json — path- and repo-matched env vars injected into the sandbox
# ---------------------------------------------------------------------------
# File: ~/.config/nixsmith/secrets.json (mode 600)
# Format:
#   {
#     "repos": { "github:<owner>": { "VAR": "value" } },
#     "paths": { "/path/prefix": { "VAR": "value" } }
#   }
# repos match (derived from git remote owner) wins over paths match.
# Longest paths prefix wins. Vars are exported by the caller (agent-sandbox.sh)
# right before exec'ing fence, so the sandboxed process inherits them.

NIXSMITH_SECRETS_FILE="${HOME}/.config/nixsmith/secrets.json"
NIXSMITH_SECRETS_ENV=""

if [[ -f "$NIXSMITH_SECRETS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  # Migration warning: flat top-level keys (old format has no "paths"/"repos")
  if jq -e 'has("paths") or has("repos")' "$NIXSMITH_SECRETS_FILE" >/dev/null 2>&1; then
    _secrets_valid=true
  else
    echo "WARNING: ${NIXSMITH_SECRETS_FILE} uses the old flat format." \
         "Wrap keys under \"paths\" or \"repos\". No secrets injected." >&2
    _secrets_valid=false
  fi

  if [[ "$_secrets_valid" == "true" ]]; then
    # repos match: derive github:<owner> from remote, check repos object
    _github_owner=$(extract_github_owner 2>/dev/null || true)
    if [[ -n "$_github_owner" ]]; then
      _repo_key="github:${_github_owner}"
      _repo_match=$(jq -r --arg k "$_repo_key" '.repos[$k] // empty | to_entries[] | "\(.key)=\(.value)"' "$NIXSMITH_SECRETS_FILE" 2>/dev/null || true)
      if [[ -n "$_repo_match" ]]; then
        NIXSMITH_SECRETS_ENV="$_repo_match"$'\n'
      fi
    fi

    # paths match: longest prefix of pwd wins; only used when no repos match
    if [[ -z "$NIXSMITH_SECRETS_ENV" ]]; then
      _current_pwd="$(pwd)"
      while IFS= read -r _prefix; do
        if [[ "$_current_pwd" == "$_prefix"* ]]; then
          while IFS= read -r _pair; do
            NIXSMITH_SECRETS_ENV="${NIXSMITH_SECRETS_ENV}${_pair}"$'\n'
          done < <(jq -r --arg p "$_prefix" '.paths[$p] | to_entries[] | "\(.key)=\(.value)"' "$NIXSMITH_SECRETS_FILE" 2>/dev/null)
          break
        fi
      done < <(jq -r '(.paths // {}) | keys[] | [., length] | @tsv' "$NIXSMITH_SECRETS_FILE" 2>/dev/null | sort -t$'\t' -k2 -rn | cut -f1)
      unset _current_pwd _prefix _pair
    fi

    unset _repo_key _repo_match _github_owner
  fi
  unset _secrets_valid
fi

export NIXSMITH_SECRETS_ENV

if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  SANDBOX_MOUNTS_RW+=("$HOME")
fi

# Serialize mount lists into env vars so forge doctor can display them inside
# the sandbox. Colon-separated, matching the SANDBOX_EXTRA_RO/RW convention.
# These are injected via bwrap --setenv by the caller (agent-sandbox.sh).
NIXSMITH_SANDBOX_RO=$(IFS=:; echo "${SANDBOX_MOUNTS_RO[*]}")
NIXSMITH_SANDBOX_RW=$(IFS=:; echo "${SANDBOX_MOUNTS_RW[*]}")
export NIXSMITH_SANDBOX_RO NIXSMITH_SANDBOX_RW

