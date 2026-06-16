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
TEA_CONFIG_DIR="${NIXSMITH_CONFIG}/tea"

# shellcheck source=common-helpers.sh
source "$(dirname "$0")/common-helpers.sh"

debug "Config paths:"
debug "  NIXSMITH_CONFIG: $NIXSMITH_CONFIG"
debug "  TEA_CONFIG_DIR: $TEA_CONFIG_DIR"

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

# Detect forge type from git remote
detect_forge() {
  local url
  url=$(git remote get-url origin 2>/dev/null || echo "")

  if [[ "$url" =~ github\.com ]]; then
    echo "github"
  elif [[ "$url" =~ gitea ]]; then
    echo "gitea"
  else
    echo "unknown"
  fi
}

extract_gitea_url() {
  local url
  url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$url" =~ ^git@([^:]+): ]]; then
    echo "https://${BASH_REMATCH[1]}"
  elif [[ "$url" =~ ^https://([^/]+) ]]; then
    echo "https://${BASH_REMATCH[1]}"
  fi
}

# Early-exit logic for GitHub: secrets.json repos entry takes priority,
# then per-owner token file, then legacy single-token file (migration required).
SECRETS_FILE="${NIXSMITH_CONFIG}/secrets.json"

if [[ "$remote_url" =~ github\.com ]]; then
  owner=$(extract_github_owner 2>/dev/null || true)
  repo_key="github:${owner}"
  debug "GitHub owner: '$owner'"
  debug "GitHub repo key: '$repo_key'"

  # Check secrets.json repos entry
  if [[ -f "$SECRETS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e 'has("repos")' "$SECRETS_FILE" >/dev/null 2>&1; then
      secrets_token=$(jq -r --arg k "$repo_key" '.repos[$k].GH_TOKEN // empty' "$SECRETS_FILE" 2>/dev/null || true)
      if [[ -n "$secrets_token" ]]; then
        debug "secrets.json repos entry exists — exiting early"
        echo "✓ Agent API tokens verified - ${SECRETS_FILE} (repos.${repo_key})"
        export GH_TOKEN="$secrets_token"
        exit 0
      fi
    fi
  fi

  # Check per-owner file; offer migration to secrets.json
  if [[ -f "$per_owner_file" ]]; then
    debug "Per-owner token file exists"
    if [[ -t 0 ]]; then
      echo ""
      echo "════════════════════════════════════════════════════════════"
      echo "  Migrate GitHub token to secrets.json?"
      echo "════════════════════════════════════════════════════════════"
      echo ""
      echo "  Token file: ${per_owner_file}"
      echo "  Destination: ${SECRETS_FILE} (repos.${repo_key}.GH_TOKEN)"
      echo ""
      echo "  Migrating stores the token alongside other project secrets"
      echo "  and removes the standalone file."
      echo ""
      read -r -p "  Migrate now? [y/N]: " migrate_choice </dev/tty
      if [[ "${migrate_choice,,}" == "y" ]]; then
        file_token=$(cat "$per_owner_file")
        mkdir -p "${NIXSMITH_CONFIG}"
        chmod 700 "${NIXSMITH_CONFIG}"
        if [[ ! -f "$SECRETS_FILE" ]]; then
          printf '{"repos":{"%s":{"GH_TOKEN":"%s"}},"paths":{}}\n' "$repo_key" "$file_token" | jq . > "$SECRETS_FILE"
        else
          tmp=$(mktemp)
          jq --arg k "$repo_key" --arg t "$file_token" \
            '.repos //= {} | .repos[$k] //= {} | .repos[$k].GH_TOKEN = $t' \
            "$SECRETS_FILE" | jq . > "$tmp" && mv "$tmp" "$SECRETS_FILE"
        fi
        chmod 600 "$SECRETS_FILE"
        rm -f "$per_owner_file"
        echo "  ✓ Migrated to ${SECRETS_FILE}"
        export GH_TOKEN="$file_token"
        exit 0
      fi
    fi
    echo "✓ Agent API tokens verified - ${per_owner_file}"
    export GH_TOKEN
    GH_TOKEN=$(cat "$per_owner_file")
    exit 0
  fi

  if [[ -f "$legacy_file" ]]; then
    echo "" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    echo "  GitHub token migration required" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    echo "" >&2
    echo "  The single-org token (~/.config/nixsmith/github-token) is" >&2
    echo "  deprecated. Tokens are now stored per GitHub org/user so" >&2
    echo "  the agent can work across multiple organizations." >&2
    echo "" >&2
    echo "  Run this command to migrate:" >&2
    echo "" >&2
    echo "    mv ${legacy_file} ${per_owner_file}" >&2
    echo "" >&2
    echo "  Then re-enter the shell." >&2
    echo "" >&2
    echo "════════════════════════════════════════════════════════════" >&2
    exit 1
  fi
fi

# Gitea: unchanged — single config file covers all repos
if [[ "$remote_url" =~ gitea ]] && [[ -f "$TEA_CONFIG_DIR/config.yml" ]]; then
  debug "Gitea remote detected and config exists - exiting early"
  echo "✓ Agent API tokens verified (Gitea token exists)"
  exit 0
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

  local repo_key="github:${owner}"
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

  # Store token in secrets.json
  mkdir -p "${NIXSMITH_CONFIG}"
  chmod 700 "${NIXSMITH_CONFIG}"
  if [[ ! -f "$SECRETS_FILE" ]]; then
    printf '{"repos":{"%s":{"GH_TOKEN":"%s"}},"paths":{}}\n' "$repo_key" "$token" | jq . > "$SECRETS_FILE"
  else
    local tmp
    tmp=$(mktemp)
    jq --arg k "$repo_key" --arg t "$token" \
      '.repos //= {} | .repos[$k] //= {} | .repos[$k].GH_TOKEN = $t' \
      "$SECRETS_FILE" | jq . > "$tmp" && mv "$tmp" "$SECRETS_FILE"
  fi
  chmod 600 "$SECRETS_FILE"

  # Export for immediate use
  export GH_TOKEN="$token"

  echo "✓ GitHub token configured (${SECRETS_FILE})"
  echo ""
}

# Setup Gitea token
setup_gitea() {
  local gitea_url
  gitea_url=$(extract_gitea_url)

  if [[ -z "$gitea_url" ]]; then
    echo "Error: Could not determine Gitea URL" >&2
    return 1
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
  echo "     ☑ read:repository"
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

  # Configure tea
  echo "Configuring tea CLI..."
  mkdir -p "${TEA_CONFIG_DIR}"
  chmod 700 "${TEA_CONFIG_DIR}"

  # Use XDG_CONFIG_HOME to target our namespace
  XDG_CONFIG_HOME="${NIXSMITH_CONFIG}" tea login add \
    --name nixsmith \
    --url "${gitea_url}" \
    --token "$token" 2>/dev/null || {
    echo "Error: Failed to configure tea CLI" >&2
    return 1
  }

  # Verify
  echo "Verifying token..."
  if ! XDG_CONFIG_HOME="${NIXSMITH_CONFIG}" tea repos list >/dev/null 2>&1; then
    echo "Error: Token verification failed" >&2
    return 1
  fi

  echo "✓ Gitea token configured"
  echo ""
}

# Main flow
main() {
  local forge_type
  forge_type=$(detect_forge)

  case "$forge_type" in
    github)
      setup_github || exit 1
      ;;
    gitea)
      setup_gitea || exit 1
      ;;
    *)
      echo "Error: Could not detect forge type (GitHub or Gitea)" >&2
      exit 1
      ;;
  esac
}

main "$@"
