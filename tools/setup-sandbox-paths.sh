#!/usr/bin/env bash
# Shared path discovery for agent sandboxes.
#
# Populates SANDBOX_MOUNTS_RO and SANDBOX_MOUNTS_RW with paths that need to
# be accessible inside the sandbox. Callers mount or permit those paths using
# their platform-specific mechanism (bwrap on Linux, sandbox-exec on macOS).
#
# Also generates the session gitconfig (GIT_CONFIG_GLOBAL) pointing to the
# git-credential-nixsmith helper, which reads GITHUB_TOKEN_FILE env var.
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

# Resolve the per-org token file for the current repo's GitHub owner.
# Falls back to the deprecated single-token path so that old installs that
# have not yet migrated still get a credential helper injected (the migration
# warning/block is in setup-agent-api-tokens.sh; here we stay permissive so
# the sandbox can still open while the user reads the warning).
_github_token_file=$(nixsmith_github_token_file 2>/dev/null || true)
if [[ -n "$_github_token_file" ]]; then
  GITHUB_TOKEN_FILE="${_github_token_file}"
  # Fall back to legacy path only for gitconfig injection — the credential
  # helper will fail at runtime if the file is missing, which is the right UX.
  [[ ! -f "$GITHUB_TOKEN_FILE" ]] && GITHUB_TOKEN_FILE="$HOME/.config/nixsmith/github-token"
else
  GITHUB_TOKEN_FILE="$HOME/.config/nixsmith/github-token"
fi
export GITHUB_TOKEN_FILE

if [[ -f "$GITHUB_TOKEN_FILE" ]]; then
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

if [[ "${AGENT_SANDBOX_SSH:-false}" == "true" ]]; then
  [[ -d "$HOME/.ssh" ]] && SANDBOX_MOUNTS_RO+=("$HOME/.ssh")
else
  [[ -f "$HOME/.ssh/known_hosts" ]]     && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/known_hosts")
  [[ -f "$HOME/.ssh/config.agent" ]]    && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/config.agent")
  [[ -f "$HOME/.ssh/agent-github" ]]    && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/agent-github" "$HOME/.ssh/agent-github.pub")
  [[ -f "$HOME/.ssh/agent-gitlab" ]]    && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/agent-gitlab" "$HOME/.ssh/agent-gitlab.pub")
  [[ -f "$HOME/.ssh/agent-gitea" ]]     && SANDBOX_MOUNTS_RO+=("$HOME/.ssh/agent-gitea" "$HOME/.ssh/agent-gitea.pub")
fi

# shellcheck disable=SC2066
for ro_path in \
  "$HOME/.agents"; do
  [[ -e "$ro_path" ]] && SANDBOX_MOUNTS_RO+=("$ro_path")
done

for rw_path in \
  "$HOME/.config/opencode" \
  "$HOME/.config/nixsmith" \
  "$HOME/.claude.json" \
  "$HOME/.claude" \
  "$HOME/.cache/opencode" \
  "$HOME/.cache/claude" \
  "$HOME/.local/share/opencode" \
  "$HOME/.local/share/claude"; do
  [[ -e "$rw_path" ]] && SANDBOX_MOUNTS_RW+=("$rw_path")
done

for cache_path in \
  "$HOME/go" \
  "$HOME/.cache/go-build" \
  "$HOME/.cargo" \
  "$HOME/.cache/pip" \
  "$HOME/.gem" \
  "$HOME/.cache/yarn" \
  "$HOME/.npm" \
  "$HOME/.local/share/pnpm" \
  "$HOME/.bun" \
  "$HOME/.gradle" \
  "$HOME/.m2" \
  "$HOME/.composer" \
  "$HOME/.cache/composer" \
  "$HOME/.nuget/packages" \
  "$HOME/.vcpkg" \
  "$HOME/.pub-cache" \
  "$HOME/.swiftpm" \
  "$HOME/.hex" \
  "$HOME/.mix"; do
  [[ -d "$cache_path" ]] && SANDBOX_MOUNTS_RW+=("$cache_path")
done

if [[ -n "${SANDBOX_EXTRA_RO:-}" ]]; then
  IFS=':' read -ra EXTRA_RO <<<"$SANDBOX_EXTRA_RO"
  for path in "${EXTRA_RO[@]}"; do add_mount_ro "$path"; done
fi
if [[ -n "${SANDBOX_EXTRA_RW:-}" ]]; then
  IFS=':' read -ra EXTRA_RW <<<"$SANDBOX_EXTRA_RW"
  for path in "${EXTRA_RW[@]}"; do add_mount_rw "$path"; done
fi
if [[ -n "${BWRAP_EXTRA_PATHS:-}" ]]; then
  IFS=':' read -ra EXTRA_PATHS <<<"$BWRAP_EXTRA_PATHS"
  for path in "${EXTRA_PATHS[@]}"; do add_mount_rw "$path"; done
fi

if [[ "${AGENT_SANDBOX_SSH:-false}" != "true" ]] && [[ -f "$HOME/.ssh/config.agent" ]]; then
  export GIT_SSH_COMMAND="ssh -F $HOME/.ssh/config.agent"
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
# Longest paths prefix wins. Vars are passed to bwrap via --setenv and
# never touch the outer shell.

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

