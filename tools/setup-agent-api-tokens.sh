#!/usr/bin/env bash
# Setup Agent API Tokens for GitHub/Gitea
# Semi-automated: opens web UI, guides through token creation, stores tokens

set -euo pipefail

# Debug logging function (controlled by AGENT_DEBUG env var)
debug() {
  if [[ "${AGENT_DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG $(date +%H:%M:%S)] setup-agent-api-tokens: $*" >&2
  fi
}

debug "=========================================="
debug "Script started"
debug "PWD: $(pwd)"
debug "USER: $USER"
debug "HOME: $HOME"
debug "Shell interactive: $([[ $- == *i* ]] && echo 'yes' || echo 'no')"
debug "Stdin is terminal: $([[ -t 0 ]] && echo 'yes' || echo 'no')"
debug "Stdout is terminal: $([[ -t 1 ]] && echo 'yes' || echo 'no')"
debug "Stderr is terminal: $([[ -t 2 ]] && echo 'yes' || echo 'no')"
debug "TERM: ${TERM:-<unset>}"
debug "=========================================="

NIXSMITH_CONFIG="${HOME}/.config/nixsmith"

# shellcheck source=common-helpers.sh
source "$(dirname "$0")/common-helpers.sh"

debug "Config paths:"
debug "  NIXSMITH_CONFIG: $NIXSMITH_CONFIG"

# Check if setup is needed - exit early if tokens already exist
debug "Checking for git repository..."
if ! git remote -v &>/dev/null 2>&1; then
  debug "Not in git repository - exiting early"
  echo "✓ Agent API tokens verified (not a git repo)"
  exit 0
fi
debug "Git repository detected"

debug "Getting remote URL..."
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
debug "Remote URL: '$remote_url'"

# Exit if no remote configured
if [[ -z "$remote_url" ]]; then
  debug "No remote configured - exiting early"
  echo "✓ Agent API tokens verified (no remote configured)"
  exit 0
fi
debug "Remote URL found: $remote_url"

extract_gitea_url() {
  local repo_url
  repo_url=$(extract_repo_url) || return 1
  echo "https://${repo_url%%/*}"
}

SECRETS_FILE="${NIXSMITH_CONFIG}/secrets.json"

store_repo_token() {
  local repo_key="$1" token_name="$2" token="$3" tmp
  mkdir -p "${NIXSMITH_CONFIG}"
  chmod 700 "${NIXSMITH_CONFIG}"
  tmp=$(mktemp "${NIXSMITH_CONFIG}/secrets.json.XXXXXX")

  if [[ -f "$SECRETS_FILE" ]]; then
    if ! jq --arg k "$repo_key" --arg n "$token_name" --arg t "$token" \
      '.repos //= {} | .repos[$k] //= {} | .repos[$k][$n] = $t' \
      "$SECRETS_FILE" > "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
  else
    jq -n --arg k "$repo_key" --arg n "$token_name" --arg t "$token" \
      '{repos: {($k): {($n): $t}}, paths: {}}' > "$tmp"
  fi

  chmod 600 "$tmp"
  mv "$tmp" "$SECRETS_FILE"
}

remove_legacy_tea_config() {
  local tea_config="${NIXSMITH_CONFIG}/tea/config.yml"
  [[ -f "$tea_config" ]] || return 0
  rm -f "$tea_config"
  rmdir "${NIXSMITH_CONFIG}/tea" 2>/dev/null || true
  echo "✓ Removed legacy Tea credential config ${tea_config}"
}

migrate_legacy_github_scope() {
  local owner old_key new_key tmp
  [[ -f "$SECRETS_FILE" ]] || return 0
  owner=$(extract_github_owner 2>/dev/null || true)
  [[ -n "$owner" ]] || return 0
  old_key="github:${owner}"
  jq -e --arg k "$old_key" '.repos[$k] != null' "$SECRETS_FILE" >/dev/null 2>&1 || return 0
  new_key=$(extract_repo_owner_scope)
  tmp=$(mktemp "${NIXSMITH_CONFIG}/secrets.json.XXXXXX")

  if ! jq --arg old "$old_key" --arg new "$new_key" \
    '.repos[$new] = ((.repos[$old] // {}) + (.repos[$new] // {})) | del(.repos[$old])' \
    "$SECRETS_FILE" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  chmod 600 "$tmp"
  mv "$tmp" "$SECRETS_FILE"
  echo "✓ Migrated secrets.json repository scope ${old_key} to ${new_key}"
}

if [[ "$(detect_forge)" == "github" ]]; then
  migrate_legacy_github_scope
  repo_key=$(nixsmith_repo_scope_key "$SECRETS_FILE" 2>/dev/null || true)
  [[ -n "$repo_key" ]] || repo_key=$(extract_repo_owner_scope 2>/dev/null || true)
  debug "GitHub repo key: '$repo_key'"

  # Check secrets.json repos entry
  if [[ -f "$SECRETS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e 'has("repos")' "$SECRETS_FILE" >/dev/null 2>&1; then
      secrets_token=$(jq -r --arg k "$repo_key" '.repos[$k].GH_TOKEN // empty' "$SECRETS_FILE" 2>/dev/null || true)
      if [[ -n "$secrets_token" ]]; then
        debug "secrets.json repos entry exists — exiting early"
        echo "✓ Agent API tokens verified - ${SECRETS_FILE} (repos.${repo_key})"
        exit 0
      fi
    fi
  fi
fi

debug "No early exit conditions met - continuing with setup"

echo "======================================"
echo "Agent API Token Setup"
echo "======================================"
echo ""

# Detect hostname for token naming
HOSTNAME=$(hostname -s)

# Setup GitHub token
setup_github() {
  local owner
  owner=$(extract_github_owner 2>/dev/null || true)
  if [[ -z "$owner" ]]; then
    echo "Error: Could not determine GitHub owner from remote URL" >&2
    return 1
  fi

  local repo_key
  repo_key=$(nixsmith_repo_scope_key "$SECRETS_FILE" 2>/dev/null || true)
  [[ -n "$repo_key" ]] || repo_key=$(extract_repo_owner_scope)
  local token_name="nixsmith - ${HOSTNAME} - ${owner}"

  echo "GitHub API Token Setup"
  echo "======================"
  echo ""
  echo "Owner:      ${owner}"
  echo "Token name: ${token_name}"
  echo "Destination: ${SECRETS_FILE} (repos.${repo_key}.GH_TOKEN)"
  echo ""
  echo "Opening GitHub token creation page..."
  echo ""

  # Build URL with pre-filled parameters
  local encoded_name
  encoded_name=$(printf '%s' "$token_name" | sed 's/ /+/g')
  local url="https://github.com/settings/personal-access-tokens/new"
  url+="?name=${encoded_name}"
  url+="&description=Agent+token+for+PR+operations"

  # Open browser
  if command -v open >/dev/null 2>&1; then
    open "$url" 2>/dev/null || echo "Visit: $url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" 2>/dev/null || echo "Visit: $url"
  else
    echo "Visit: $url"
  fi

  echo ""
  echo "Configure the token:"
  echo "  1. Token name: ${token_name} (pre-filled)"
  echo "  2. Expiration: No expiration"
  echo "  3. Repository access: Select repositories owned by '${owner}'"
  echo "  4. Permissions:"
  echo "     - Contents: Read and write"
  echo "     - Pull requests: Read and write"
  echo "     - Workflows: Read and write (only if agent will modify .github/workflows/)"
  echo "  5. Generate token"
  echo ""

  read -p "Paste the generated token: " -rs token
  echo ""

  if [[ -z "$token" ]]; then
    echo "Error: No token provided" >&2
    return 1
  fi

  # Verify token works
  echo "Verifying token..."
  local verify_output
  if ! verify_output=$(GH_TOKEN="$token" gh auth status 2>&1); then
    echo "Error: Token verification failed" >&2
    echo "" >&2
    echo "GitHub CLI output:" >&2
    echo "$verify_output" >&2
    echo "" >&2
    echo "Common issues:" >&2
    echo "  - Token may not have correct permissions (needs: Contents: Read, PRs: Read+Write)" >&2
    echo "  - Token may not be a fine-grained PAT (classic PATs not recommended)" >&2
    echo "  - Token may have expired" >&2
    return 1
  fi

  if ! store_repo_token "$repo_key" GH_TOKEN "$token"; then
    echo "Error: Failed to update ${SECRETS_FILE}" >&2
    return 1
  fi

  echo "✓ GitHub token configured (${SECRETS_FILE})"
  echo ""
}

# Tea supports an in-memory login when both variables are present.
verify_gitea() {
  local gitea_url="$1" token="$2"
  local verify_output
  if ! verify_output=$(GITEA_INSTANCE_URL="$gitea_url" GITEA_TOKEN="$token" \
    tea api "/repos/{owner}/{repo}" --output /dev/null 2>&1); then
    echo "Tea CLI output:" >&2
    echo "$verify_output" >&2
    return 1
  fi
}

# Setup Gitea token
setup_gitea() {
  local gitea_url
  gitea_url=$(extract_gitea_url)

  local repo_key
  repo_key=$(nixsmith_repo_scope_key "$SECRETS_FILE" 2>/dev/null || true)
  [[ -n "$repo_key" ]] || repo_key=$(extract_repo_owner_scope 2>/dev/null || true)

  if [[ -z "$gitea_url" ]]; then
    echo "Error: Could not determine Gitea URL" >&2
    return 1
  fi

  # Check secrets.json repos entry
  if [[ -f "$SECRETS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e 'has("repos")' "$SECRETS_FILE" >/dev/null 2>&1; then
      secrets_token=$(jq -r --arg k "$repo_key" '.repos[$k].GITEA_TOKEN // empty' "$SECRETS_FILE" 2>/dev/null || true)
      if [[ -n "$secrets_token" ]]; then
        if ! verify_gitea "$gitea_url" "$secrets_token"; then
          echo "Error: Token verification failed" >&2
          return 1
        fi
        remove_legacy_tea_config
        debug "secrets.json repos entry exists — verified with tea"
        echo "✓ Agent API tokens verified - ${SECRETS_FILE} (repos.${repo_key})"
        return 0
      fi
    fi
  fi

  echo "Gitea API Token Setup"
  echo "====================="
  echo ""
  echo "Token will be named: nixsmith - ${HOSTNAME}"
  echo "Gitea URL: ${gitea_url}"
  echo ""
  echo "Opening Gitea token creation page..."
  echo ""

  local url="${gitea_url}/user/settings/applications"

  if command -v open >/dev/null 2>&1; then
    open "$url" 2>/dev/null || echo "Visit: $url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" 2>/dev/null || echo "Visit: $url"
  else
    echo "Visit: $url"
  fi

  echo ""
  echo "Configure the token:"
  echo "  1. Token Name: nixsmith - ${HOSTNAME}"
  echo "  2. Select scopes:"
  echo "     ☑ write:repository"
  echo "     ☑ write:issue"
  echo "  3. Generate Token"
  echo ""
  echo "Note: Token will have access to all your repositories (Gitea limitation)"
  echo ""

  read -p "Paste the generated token: " -rs token
  echo ""

  if [[ -z "$token" ]]; then
    echo "Error: No token provided" >&2
    return 1
  fi

  echo "Verifying token..."
  verify_gitea "$gitea_url" "$token" || {
    echo "Error: Token verification failed" >&2
    return 1
  }
  if ! store_repo_token "$repo_key" GITEA_TOKEN "$token"; then
    echo "Error: Failed to update ${SECRETS_FILE}" >&2
    return 1
  fi
  remove_legacy_tea_config

  echo "✓ Gitea token configured (${SECRETS_FILE})"
  echo ""
}

# Main flow
main() {
  local forge_type
  forge_type=$(detect_forge)

  case "$forge_type" in
    github)
      setup_github
      ;;
    gitea)
      setup_gitea
      ;;
    *)
      echo "Error: Could not detect forge type (GitHub or Gitea)" >&2
      exit 1
      ;;
  esac
}

main "$@"
