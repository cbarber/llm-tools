#!/usr/bin/env bash
set -euo pipefail
# Shared shell setup sourced by all agent environments.
# Callers must set TOOLS_DIR and AGENT_ENV_CONFIG_DIR before sourcing this file.

export DEFAULT_BRANCH
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")

# shellcheck source=common-helpers.sh
source "${TOOLS_DIR}/common-helpers.sh"

if [[ -n "${AGENTS_SKILLS_DIR:-}" && -d "${AGENTS_SKILLS_DIR}" ]]; then
  for skill_dir in "${AGENTS_SKILLS_DIR}"/*/; do
    skill_name=$(basename "$skill_dir")
    dest="$HOME/.agents/skills/${skill_name}"
    mkdir -p "$dest" 2>/dev/null || true
    rsync --checksum --recursive "${skill_dir}" "$dest/" 2>/dev/null || true
  done
fi

[[ -f .env ]] && source .env
[[ -f "${AGENT_ENV_CONFIG_DIR}/.env" ]] && source "${AGENT_ENV_CONFIG_DIR}/.env"

# Strip known AI provider credentials from the outer shell after .env sourcing.
# These vars are injected exclusively into the sandbox via secrets.json --setenv,
# preventing them from leaking across projects through shell inheritance.
for _blocklist_var in \
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN \
  CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY \
  OPENAI_API_KEY \
  GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_BEARER_TOKEN_BEDROCK \
  AZURE_OPENAI_API_KEY AZURE_RESOURCE_NAME \
  GITLAB_TOKEN \
  CLOUDFLARE_API_TOKEN \
  NVIDIA_API_KEY \
  DIGITALOCEAN_ACCESS_TOKEN \
  GROQ_API_KEY MISTRAL_API_KEY XAI_API_KEY OPENROUTER_API_KEY; do
  unset "${_blocklist_var}"
done
unset _blocklist_var

if [[ "${SKIP_AGENT_SETUP:-}" != "true" ]] && git remote -v &>/dev/null 2>&1; then
  "${TOOLS_DIR}/setup-agent-keys.sh" || {
    echo "Error: SSH key setup failed" >&2
    exit 1
  }
  "${TOOLS_DIR}/setup-agent-api-tokens.sh" || {
    echo "Error: API token setup failed" >&2
    exit 1
  }

  # Export GH_TOKEN for the current shell session so forge and gh CLI work
  # without the sandbox credential helper. Resolved from secrets.json
  _gh_owner=$(extract_github_owner 2>/dev/null || true)
  _secrets_file="${HOME}/.config/nixsmith/secrets.json"
  if [[ -n "$_gh_owner" ]] && [[ -f "$_secrets_file" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e 'has("repos")' "$_secrets_file" >/dev/null 2>&1; then
      _gh_token=$(jq -r --arg k "github:${_gh_owner}" '.repos[$k].GH_TOKEN // empty' "$_secrets_file" 2>/dev/null || true)
      [[ -n "$_gh_token" ]] && export GH_TOKEN="$_gh_token"
      unset _gh_token
    fi
  fi
  unset _gh_owner _secrets_file
fi
