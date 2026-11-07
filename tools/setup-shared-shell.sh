#!/usr/bin/env bash
set -euo pipefail
# Shared shell setup sourced by all agent environments.
# Callers must set TOOLS_DIR and AGENT_ENV_CONFIG_DIR before sourcing this file.

export DEFAULT_BRANCH
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")

# shellcheck source=common-helpers.sh
source "${TOOLS_DIR}/common-helpers.sh"

if [[ -n "${AGENTS_SKILLS_DIR:-}" && -d "${AGENTS_SKILLS_DIR}" ]]; then
  # Other sources install into the same directory, so only skills named in
  # this repo's manifest are ever removed.
  skills_manifest="$HOME/.agents/skills/.llm-tools-installed"
  installed_skills=()
  for skill_dir in "${AGENTS_SKILLS_DIR}"/*/; do
    skill_name=$(basename "$skill_dir")
    dest="$HOME/.agents/skills/${skill_name}"
    mkdir -p "$dest" 2>/dev/null || true
    rsync --checksum --recursive "${skill_dir}" "$dest/" 2>/dev/null || true
    installed_skills+=("$skill_name")
  done
  # Installed by the fsm branch before the manifest existed.
  previous_skills=(mojo-create-pull-request mojo-update-pull-request mojo-review-response)
  [[ -f "$skills_manifest" ]] && mapfile -t previous_skills <"$skills_manifest"
  for skill_name in "${previous_skills[@]}"; do
    [[ "$skill_name" =~ ^[A-Za-z0-9_-][A-Za-z0-9._-]*$ ]] || continue
    [[ " ${installed_skills[*]} " == *" ${skill_name} "* ]] && continue
    dest="$HOME/.agents/skills/${skill_name}"
    # The install only creates real directories; a symlink is someone else's.
    [[ -L "$dest" ]] && continue
    # Some installed skill directories are read-only.
    chmod -R u+w "$dest" 2>/dev/null || true
    rm -rf "$dest" 2>/dev/null || true
  done
  printf '%s\n' "${installed_skills[@]}" >"$skills_manifest" 2>/dev/null || true
  unset skills_manifest installed_skills previous_skills
fi

[[ -f .env ]] && source .env
[[ -f "${AGENT_ENV_CONFIG_DIR}/.env" ]] && source "${AGENT_ENV_CONFIG_DIR}/.env"

# Strip known credentials from the outer shell after .env sourcing.
# These vars are injected exclusively into the sandbox via secrets.json --setenv,
# preventing them from leaking across projects through shell inheritance.
for _blocklist_var in \
  ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN \
  CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES \
  CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY \
  OPENAI_API_KEY \
  GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT \
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_BEARER_TOKEN_BEDROCK \
  AZURE_OPENAI_API_KEY AZURE_RESOURCE_NAME \
  GH_TOKEN GITHUB_TOKEN GITEA_TOKEN GITEA_INSTANCE_URL GITLAB_TOKEN \
  CLOUDFLARE_API_TOKEN \
  NVIDIA_API_KEY \
  DIGITALOCEAN_ACCESS_TOKEN \
  GROQ_API_KEY MISTRAL_API_KEY XAI_API_KEY OPENROUTER_API_KEY; do
  unset "${_blocklist_var}"
done
unset _blocklist_var

if [[ "${SKIP_AGENT_SETUP:-}" != "true" ]] && git remote -v &>/dev/null 2>&1; then
  "${TOOLS_DIR}/setup-agent-api-tokens.sh" || {
    echo "Error: API token setup failed" >&2
    exit 1
  }

fi
