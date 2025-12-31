#!/usr/bin/env bash
# Setup Agent SSH Keys
#
# Generates platform-specific SSH keys for agent operations and provides
# instructions for adding them as deploy keys to repositories.
#
# Usage: setup-agent-keys.sh

set -euo pipefail

# Debug logging function (controlled by AGENT_DEBUG env var)
debug() {
  if [[ "${AGENT_DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG $(date +%H:%M:%S)] setup-agent-keys: $*" >&2
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

AGENT_KEY_DIR="$HOME/.ssh"
GITHUB_KEY="$AGENT_KEY_DIR/agent-github"
GITLAB_KEY="$AGENT_KEY_DIR/agent-gitlab"
GITEA_KEY="$AGENT_KEY_DIR/agent-gitea"

debug "Key paths configured:"
debug "  GITHUB_KEY: $GITHUB_KEY"
debug "  GITLAB_KEY: $GITLAB_KEY"
debug "  GITEA_KEY: $GITEA_KEY"

echo "======================================"
echo "Agent SSH Key Setup"
echo "======================================"
echo ""

# Early exit if not in a git repo
debug "Checking for git repository..."
if ! git remote -v &>/dev/null 2>&1; then
  debug "Not in git repository - exiting early"
  echo "✓ Agent SSH keys verified (not a git repo)"
  exit 0
fi
debug "Git repository detected"

# Early exit if no remote configured
debug "Getting remote URL..."
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
debug "Remote URL: '$remote_url'"

if [[ -z "$remote_url" ]]; then
  debug "No remote configured - exiting early"
  echo "✓ Agent SSH keys verified (no remote configured)"
  exit 0
fi
debug "Remote URL found: $remote_url"

debug "Checking for existing keys..."
if [[ "$remote_url" =~ github\.com ]] && [[ -f "$GITHUB_KEY" ]]; then
  debug "GitHub remote detected and key exists - exiting early"
  echo "✓ Agent SSH keys verified (GitHub key exists)"
  exit 0
elif [[ "$remote_url" =~ gitlab\.com ]] && [[ -f "$GITLAB_KEY" ]]; then
  debug "GitLab remote detected and key exists - exiting early"
  echo "✓ Agent SSH keys verified (GitLab key exists)"
  exit 0
elif [[ "$remote_url" =~ gitea ]] && [[ -f "$GITEA_KEY" ]]; then
  debug "Gitea remote detected and key exists - exiting early"
  echo "✓ Agent SSH keys verified (Gitea key exists)"
  exit 0
fi
debug "No early exit conditions met - continuing with setup"

# Detect current repository
CURRENT_REPO=""
CURRENT_PLATFORM=""
CURRENT_KEY=""

if git remote -v &>/dev/null; then
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ -n "$REMOTE_URL" ]]; then
    CURRENT_REPO="$REMOTE_URL"
    
    # Detect platform
    if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/\.]+) ]]; then
      CURRENT_PLATFORM="github"
      CURRENT_KEY="$GITHUB_KEY"
      REPO_OWNER="${BASH_REMATCH[1]}"
      REPO_NAME="${BASH_REMATCH[2]}"
    elif [[ "$REMOTE_URL" =~ gitlab\.com[:/]([^/]+)/([^/\.]+) ]]; then
      CURRENT_PLATFORM="gitlab"
      CURRENT_KEY="$GITLAB_KEY"
      REPO_OWNER="${BASH_REMATCH[1]}"
      REPO_NAME="${BASH_REMATCH[2]}"
    elif [[ "$REMOTE_URL" =~ gitea ]]; then
      CURRENT_PLATFORM="gitea"
      CURRENT_KEY="$GITEA_KEY"
      # Try to extract owner/repo from various gitea URL formats
      if [[ "$REMOTE_URL" =~ [:/]([^/]+)/([^/\.]+)\.git ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
      fi
    fi
  fi
fi

# Function to generate key if it doesn't exist
generate_key() {
  local key_path="$1"
  local platform="$2"
  
  debug "generate_key called: platform=$platform, path=$key_path"
  
  if [[ -f "$key_path" ]]; then
    debug "Key already exists at $key_path"
    echo "✓ Key already exists: $key_path"
    return 0
  fi
  
  debug "Key does not exist - generating..."
  debug "Checking if $AGENT_KEY_DIR exists..."
  if [[ ! -d "$AGENT_KEY_DIR" ]]; then
    debug "ERROR: $AGENT_KEY_DIR does not exist!"
    echo "Error: $AGENT_KEY_DIR directory does not exist" >&2
    return 1
  fi
  debug "$AGENT_KEY_DIR exists"
  
  echo "Generating $platform agent key..."
  debug "Running: ssh-keygen -t ed25519 -f '$key_path' -C 'llm-agent@$platform' -N ''"
  if ssh-keygen -t ed25519 -f "$key_path" -C "llm-agent@$platform" -N ""; then
    debug "ssh-keygen succeeded"
    echo "✓ Generated: $key_path"
  else
    local exit_code=$?
    debug "ERROR: ssh-keygen failed with exit code $exit_code"
    return $exit_code
  fi
}

# Generate keys for all platforms
echo "1. Generating Agent SSH Keys"
echo "------------------------------"
debug "Generating keys for all platforms..."
generate_key "$GITHUB_KEY" "github"
generate_key "$GITLAB_KEY" "gitlab"
generate_key "$GITEA_KEY" "gitea"
debug "Key generation complete"
echo ""

# Create agent-specific SSH config (sandbox mounts this as ~/.ssh/config)
SSH_CONFIG_AGENT="$HOME/.ssh/config.agent"

debug "SSH config path: $SSH_CONFIG_AGENT"

echo "2. Configuring SSH"
echo "------------------------------"

# Create agent-specific config
debug "Creating $SSH_CONFIG_AGENT..."
cat > "$SSH_CONFIG_AGENT" << 'EOF'
# Agent SSH Configuration
# Auto-generated by setup-agent-keys.sh

Host github.com
  IdentityFile ~/.ssh/agent-github
  IdentitiesOnly yes

Host gitlab.com
  IdentityFile ~/.ssh/agent-gitlab
  IdentitiesOnly yes

Host *.gitea.* gitea.*
  IdentityFile ~/.ssh/agent-gitea
  IdentitiesOnly yes
EOF

debug "Successfully created $SSH_CONFIG_AGENT"
echo "✓ Created: $SSH_CONFIG_AGENT"
echo ""

# Update sandbox to mount agent keys
echo "3. Updating Sandbox Configuration"
echo "------------------------------"

SANDBOX_SCRIPT="$(dirname "$0")/agent-sandbox.sh"
debug "Sandbox script path: $SANDBOX_SCRIPT"

if [[ -f "$SANDBOX_SCRIPT" ]]; then
  debug "Sandbox script exists"
  # Check if agent SSH keys are already mounted
  if ! grep -q "agent-github" "$SANDBOX_SCRIPT"; then
    debug "Sandbox script needs updating - adding agent key mounts"
    echo "Adding agent SSH key mounts to sandbox script..."
    
    # Find the line with "Optional: bind mount SSH keys"
    # Insert agent key mounts before it
    sed -i '/# Optional: bind mount SSH keys for git authentication/i \
# Agent SSH keys for git operations\
if [[ -f "$HOME/.ssh/agent-github" ]]; then\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-github" "$HOME/.ssh/agent-github")\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-github.pub" "$HOME/.ssh/agent-github.pub")\
fi\
if [[ -f "$HOME/.ssh/agent-gitlab" ]]; then\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitlab" "$HOME/.ssh/agent-gitlab")\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitlab.pub" "$HOME/.ssh/agent-gitlab.pub")\
fi\
if [[ -f "$HOME/.ssh/agent-gitea" ]]; then\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitea" "$HOME/.ssh/agent-gitea")\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/agent-gitea.pub" "$HOME/.ssh/agent-gitea.pub")\
fi\
\
# SSH config for agent keys\
if [[ -f "$HOME/.ssh/config.agent" ]]; then\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/config.agent" "$HOME/.ssh/config.agent")\
fi\
if [[ -f "$HOME/.ssh/config" ]]; then\
  BWRAP_ARGS+=(--ro-bind "$HOME/.ssh/config" "$HOME/.ssh/config")\
fi\
\
' "$SANDBOX_SCRIPT"
    
    debug "Successfully updated $SANDBOX_SCRIPT"
    echo "✓ Updated: $SANDBOX_SCRIPT"
    echo "  (Agent keys now accessible in sandbox)"
  else
    debug "Sandbox script already configured"
    echo "✓ Sandbox already configured for agent keys"
  fi
else
  debug "Sandbox script not found"
  echo "⚠️  Sandbox script not found: $SANDBOX_SCRIPT"
fi
debug "Sandbox configuration complete"
echo ""

# Provide instructions for current repository
if [[ -n "$CURRENT_REPO" ]] && [[ -n "$CURRENT_PLATFORM" ]]; then
  echo "4. Add Deploy Key to Current Repository"
  echo "======================================"
  echo ""
  echo "Repository: $CURRENT_REPO"
  echo "Platform:   $CURRENT_PLATFORM"
  echo ""
  echo "Public Key to Add:"
  echo "-------------------"
  cat "${CURRENT_KEY}.pub"
  echo ""
  echo "Instructions:"
  echo "-------------"
  
  case "$CURRENT_PLATFORM" in
    github)
      echo "1. Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/keys"
      echo "2. Click 'Add deploy key'"
      echo "3. Title: LLM Agent"
      echo "4. Key: (copy the public key above)"
      echo "5. ☑ Allow write access"
      echo "6. Click 'Add key'"
      echo ""
      echo "Or use GitHub CLI:"
      echo "  gh repo deploy-key add ${CURRENT_KEY}.pub --title 'LLM Agent' --allow-write"
      ;;
    gitlab)
      echo "1. Go to: https://gitlab.com/$REPO_OWNER/$REPO_NAME/-/settings/repository"
      echo "2. Expand 'Deploy Keys'"
      echo "3. Title: LLM Agent"
      echo "4. Key: (copy the public key above)"
      echo "5. ☑ Write access allowed"
      echo "6. Click 'Add key'"
      ;;
    gitea)
      echo "1. Go to your Gitea repository settings"
      echo "2. Navigate to 'Deploy Keys'"
      echo "3. Title: LLM Agent"
      echo "4. Key: (copy the public key above)"
      echo "5. ☑ Allow write access (if available)"
      echo "6. Click 'Add key'"
      ;;
  esac
  
  echo ""
  echo "After adding the deploy key, test with:"
  echo "  git push"
  echo ""
else
  echo "4. Add Deploy Keys to Repositories"
  echo "======================================"
  echo ""
  echo "Not in a git repository or remote not configured."
  echo ""
  echo "For each repository you want agents to access:"
  echo ""
  echo "GitHub:"
  echo "  Repository → Settings → Deploy Keys → Add deploy key"
  echo "  Use key: $GITHUB_KEY.pub"
  echo ""
  echo "GitLab:"
  echo "  Project → Settings → Repository → Deploy Keys → Add deploy key"
  echo "  Use key: $GITLAB_KEY.pub"
  echo ""
  echo "Gitea:"
  echo "  Repository → Settings → Deploy Keys → Add deploy key"
  echo "  Use key: $GITEA_KEY.pub"
  echo ""
fi

echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""

# Verify SSH connectivity if deploy key was shown for current repo
if [[ -n "$CURRENT_PLATFORM" ]]; then
  echo "Verifying SSH connection..."
  case "$CURRENT_PLATFORM" in
    github)
      if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo "✓ GitHub SSH authentication successful"
      else
        echo "⚠️  GitHub SSH authentication failed"
        echo "   Please add the deploy key shown above to:"
        echo "   https://github.com/$REPO_OWNER/$REPO_NAME/settings/keys"
      fi
      ;;
    gitlab)
      if ssh -T git@gitlab.com 2>&1 | grep -q "Welcome to GitLab"; then
        echo "✓ GitLab SSH authentication successful"
      else
        echo "⚠️  GitLab SSH authentication failed"
        echo "   Please add the deploy key to your GitLab repository"
      fi
      ;;
    gitea)
      echo "⚠️  Gitea SSH verification not automated"
      echo "   Please verify manually with: ssh -T git@<your-gitea-host>"
      ;;
  esac
  echo ""
fi

debug "Script completed successfully"
