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
GITHUB_TOKEN_FILE="${NIXSMITH_CONFIG}/github-token"
TEA_CONFIG_DIR="${NIXSMITH_CONFIG}/tea"

debug "Config paths:"
debug "  NIXSMITH_CONFIG: $NIXSMITH_CONFIG"
debug "  GITHUB_TOKEN_FILE: $GITHUB_TOKEN_FILE"
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

# Exit if tokens already configured for this forge
debug "Checking for existing tokens..."
if [[ "$remote_url" =~ github\.com ]] && [[ -f "$GITHUB_TOKEN_FILE" ]]; then
  debug "GitHub remote detected and token exists - exiting early"
  echo "✓ Agent API tokens verified (GitHub token exists)"
  exit 0
elif [[ "$remote_url" =~ gitea ]] && [[ -f "$TEA_CONFIG_DIR/config.yml" ]]; then
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

# Detect forge type from git remote
detect_forge() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  
  if [[ "$remote_url" =~ github\.com ]]; then
    echo "github"
  elif [[ "$remote_url" =~ gitea ]]; then
    echo "gitea"
  else
    echo "unknown"
  fi
}

extract_github_repo() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/\.]+) ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
}

extract_gitea_url() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" =~ ^git@([^:]+): ]]; then
    echo "https://${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^https://([^/]+) ]]; then
    echo "https://${BASH_REMATCH[1]}"
  fi
}

# Setup GitHub token
setup_github() {
  echo "GitHub API Token Setup"
  echo "======================"
  echo ""
  echo "Token will be named: nixsmith - ${HOSTNAME}"
  echo "Scope: All repositories (or select specific repos)"
  echo ""
  echo "Opening GitHub token creation page..."
  echo ""
  
  # Build URL with pre-filled parameters
  local url="https://github.com/settings/personal-access-tokens/new"
  url+="?name=nixsmith+-+${HOSTNAME}"
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
  echo "  1. Token name: nixsmith - ${HOSTNAME} (pre-filled)"
  echo "  2. Expiration: No expiration"
  echo "  3. Repository access: All repositories"
  echo "     (or select specific repos you want agent to access)"
  echo "  4. Permissions:"
  echo "     - Contents: Read"
  echo "     - Pull requests: Read and write"
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
  
  # Store token
  mkdir -p "${NIXSMITH_CONFIG}"
  chmod 700 "${NIXSMITH_CONFIG}"
  echo "$token" > "${GITHUB_TOKEN_FILE}"
  chmod 600 "${GITHUB_TOKEN_FILE}"
  
  # Export for immediate use
  export GH_TOKEN="$token"
  
  echo "✓ GitHub token configured"
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
