#!/usr/bin/env bash
# Shared path discovery for agent sandboxes.
#
# Populates SANDBOX_MOUNTS_RO and SANDBOX_MOUNTS_RW with paths that need to
# be accessible inside the sandbox. The caller (agent-sandbox.sh) turns these
# into fence's allowRead/allowWrite config entries.
#
# Also exports GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n/GIT_CONFIG_VALUE_n so the
# sandboxed git forces GitHub remotes through HTTPS + the git-credential-
# nixsmith helper (which reads the GH_TOKEN env var) — no synthetic gitconfig
# file or [include] of the user's real config is needed.
#
# Required by caller before sourcing:
#   nixsmith_repo_scope_key — function from common-helpers.sh (sourced by caller)

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

# Force GitHub remotes through HTTPS + the token credential helper — no SSH
# key exists inside the sandbox. Injected via git's native env-config
# mechanism (GIT_CONFIG_COUNT/GIT_CONFIG_KEY_n/GIT_CONFIG_VALUE_n) rather than
# a synthetic gitconfig file: it needs no RO mount or [include] resolution,
# applies above every config file, and is unconditional — it doesn't depend
# on a token already being present in secrets.json.
_git_cfg_keys=()
_git_cfg_values=()
_add_git_cfg() { _git_cfg_keys+=("$1"); _git_cfg_values+=("$2"); }

_add_git_cfg "url.https://github.com/.insteadOf" "git@github.com:"
_add_git_cfg "credential.https://github.com.helper" "!git-credential-nixsmith"

# Allowlisted identity/preference passthrough from the user's real gitconfig.
# Deliberately narrow — the rest of the user's config is never read into the
# sandbox; it can carry directives (an https->ssh url.insteadOf, diff.external,
# filter.lfs, etc.) that would fight or break the sandbox's own config above.
for _key in user.name user.email push.default push.autoSetupRemote init.defaultBranch; do
  # --includes: `--global --get` doesn't follow [include]/[includeIf] unless
  # asked — many gitconfigs (e.g. split work/personal identity) rely on it.
  _val=$(git config --global --includes --get "$_key" 2>/dev/null || true)
  [[ -n "$_val" ]] && _add_git_cfg "$_key" "$_val"
done
unset _key _val

GIT_CONFIG_COUNT="${#_git_cfg_keys[@]}"
export GIT_CONFIG_COUNT
for _i in "${!_git_cfg_keys[@]}"; do
  export "GIT_CONFIG_KEY_${_i}=${_git_cfg_keys[$_i]}"
  export "GIT_CONFIG_VALUE_${_i}=${_git_cfg_values[$_i]}"
done
unset _git_cfg_keys _git_cfg_values _i

# shellcheck disable=SC2066
for ro_path in \
  "$HOME/.agents"; do
  [[ -e "$ro_path" ]] && SANDBOX_MOUNTS_RO+=("$ro_path")
done

mkdir -p "$HOME/.local/state/opencode" 2>/dev/null || true

mkdir -p "$HOME/.config/nixsmith/iron-proxy" 2>/dev/null || true

for rw_path in \
  "$HOME/.bun" \
  "$HOME/.cache/claude" \
  "$HOME/.cache/composer" \
  "$HOME/.cache/go-build" \
  "$HOME/.cache/golangci-lint" \
  "$HOME/.cache/nix" \
  "$HOME/.cache/opencode" \
  "$HOME/.cache/pip" \
  "$HOME/.cache/yarn" \
  "$HOME/.cargo" \
  "$HOME/.claude" \
  "$HOME/.claude.json" \
  "$HOME/.composer" \
  "$HOME/.config/nixsmith/iron-proxy" \
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
#     "repos": { "host/owner": { "VAR": "value" } },
#     "paths": { "/path/prefix": { "VAR": "value" } }
#   }
# Longest repo URL prefix wins over the longest path prefix.
# Vars are exported by the caller (agent-sandbox.sh)
# right before exec'ing fence, so the sandboxed process inherits them.

NIXSMITH_SECRETS_FILE="${HOME}/.config/nixsmith/secrets.json"
NIXSMITH_SECRETS_ENV=""
NIXSMITH_DERIVED_ENV=""
NIXSMITH_GITEA_HOST=""
NIXSMITH_OPENCODE_OAUTH_PROVIDERS="[]"

set_scoped_secrets() {
  local selected_scope="$1"
  local repo_url
  [[ -n "$selected_scope" ]] || return 0

  if ! jq -e '
    type == "object" and
    ([to_entries[] | select(.key != "_opencodeAuth") |
      (.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and (.value | type == "string")] | all) and
    (if has("_opencodeAuth") then
      (._opencodeAuth | type == "object" and
        ((.oauthProviders // []) | type == "array" and all(.[]; type == "string" and length > 0)))
    else true end)
  ' <<< "$selected_scope" >/dev/null; then
    echo "Invalid entry in ${NIXSMITH_SECRETS_FILE}: environment keys must be variable names, values must be strings, and _opencodeAuth.oauthProviders must be an array of provider IDs." >&2
    return 1
  fi

  NIXSMITH_SECRETS_ENV=$(jq -r 'to_entries[] | select(.key != "_opencodeAuth" and .key != "GITEA_INSTANCE_URL") | "\(.key)=\(.value)"' <<< "$selected_scope")
  [[ -z "$NIXSMITH_SECRETS_ENV" ]] || NIXSMITH_SECRETS_ENV+=$'\n'
  NIXSMITH_OPENCODE_OAUTH_PROVIDERS=$(jq -c '._opencodeAuth.oauthProviders // [] | unique' <<< "$selected_scope")

  if jq -e 'has("GITEA_TOKEN")' <<< "$selected_scope" >/dev/null; then
    repo_url=$(extract_repo_url 2>/dev/null || true)
    if [[ -z "$repo_url" ]]; then
      echo "Cannot use GITEA_TOKEN from ${NIXSMITH_SECRETS_FILE} without a repository origin." >&2
      return 1
    fi
    NIXSMITH_GITEA_HOST="${repo_url%%/*}"
    NIXSMITH_DERIVED_ENV="GITEA_INSTANCE_URL=https://${NIXSMITH_GITEA_HOST}"$'\n'
  fi
}

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
    _selected_scope=""

    _repo_key=$(nixsmith_repo_scope_key "$NIXSMITH_SECRETS_FILE" 2>/dev/null || true)
    if [[ -n "$_repo_key" ]]; then
      _selected_scope=$(jq -c --arg k "$_repo_key" '.repos[$k] // empty | select(type == "object" and length > 0)' "$NIXSMITH_SECRETS_FILE" 2>/dev/null || true)
    fi

    # paths match: longest prefix of pwd wins; only used when no repos match
    if [[ -z "$_selected_scope" ]]; then
      _current_pwd="$(pwd)"
      while IFS= read -r _prefix; do
        if [[ "$_prefix" == "/" || "$_current_pwd" == "$_prefix" || "$_current_pwd" == "$_prefix"/* ]]; then
          _selected_scope=$(jq -c --arg p "$_prefix" '.paths[$p] // empty | select(type == "object")' "$NIXSMITH_SECRETS_FILE" 2>/dev/null || true)
          break
        fi
      done < <(jq -r '(.paths // {}) | keys[] | [., length] | @tsv' "$NIXSMITH_SECRETS_FILE" 2>/dev/null | sort -t$'\t' -k2 -rn | cut -f1)
      unset _current_pwd _prefix
    fi

    set_scoped_secrets "$_selected_scope"

    unset _repo_key _selected_scope
  fi
  unset _secrets_valid
fi

export NIXSMITH_SECRETS_ENV NIXSMITH_DERIVED_ENV NIXSMITH_GITEA_HOST NIXSMITH_OPENCODE_OAUTH_PROVIDERS
unset -f set_scoped_secrets

if [[ "${AGENT_SANDBOX_BIND_HOME:-false}" == "true" ]]; then
  SANDBOX_MOUNTS_RW+=("$HOME")
fi

# Serialize mount lists into env vars so forge doctor can display them inside
# the sandbox. Colon-separated, matching the SANDBOX_EXTRA_RO/RW convention.
# These are injected via bwrap --setenv by the caller (agent-sandbox.sh).
NIXSMITH_SANDBOX_RO=$(IFS=:; echo "${SANDBOX_MOUNTS_RO[*]}")
NIXSMITH_SANDBOX_RW=$(IFS=:; echo "${SANDBOX_MOUNTS_RW[*]}")
export NIXSMITH_SANDBOX_RO NIXSMITH_SANDBOX_RW
