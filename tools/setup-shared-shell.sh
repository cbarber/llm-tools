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
  # without the sandbox credential helper. Resolved from the per-owner token
  # file; silently skipped when not a GitHub repo or token doesn't exist yet.
  _gh_token_file=$(nixsmith_github_token_file 2>/dev/null || true)
  if [[ -n "$_gh_token_file" ]] && [[ -f "$_gh_token_file" ]]; then
    export GH_TOKEN
    GH_TOKEN=$(cat "$_gh_token_file")
  fi
  unset _gh_token_file
fi
