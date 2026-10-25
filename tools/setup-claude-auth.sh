#!/usr/bin/env bash
# Expose the host claude.ai OAuth credential to a sandboxed Claude Code launch.
#
# Sourced by agent-sandbox.sh — never executed. Returns non-zero to abort the
# launch when the grant is configured but the credential cannot be used.
#
# Mirrors setup-opencode-auth.sh: the canonical credential file stays unreadable
# inside Fence and only the fields Claude Code needs cross the boundary. Unlike
# OpenCode, Claude Code can complete the OAuth exchange itself from the
# environment, so the sandbox refreshes its own access token without ever
# reading or writing ~/.claude/.credentials.json.

CLAUDE_AUTH_DENY_CANONICAL=false
export CLAUDE_AUTH_DENY_CANONICAL

# Never inherit these from the outer shell.
unset CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES

# Opt-in. Without the grant the canonical file stays readable so that Claude
# Code's own browser login keeps working inside the sandbox as before.
[[ "${NIXSMITH_CLAUDE_OAUTH:-false}" == "true" ]] || return 0

_claude_auth_print_login_command() {
  echo 'Run: nix develop github:cbarber/llm-tools#claude-code-auth --command claude auth login' >&2
}

_claude_auth_file="${HOME}/.claude/.credentials.json"

if [[ ! -f "$_claude_auth_file" ]]; then
  echo "Claude Code OAuth credential is missing." >&2
  _claude_auth_print_login_command
  return 1
fi

if ! jq -e '
  .claudeAiOauth | type == "object" and
    (.accessToken | type == "string" and length > 0) and
    (.refreshToken | type == "string" and length > 0) and
    (.expiresAt | type == "number" and floor == .) and
    (.scopes | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) and
    (if has("refreshTokenExpiresAt") then
      (.refreshTokenExpiresAt | type == "number" and floor == .)
    else true end)
' "$_claude_auth_file" >/dev/null 2>&1; then
  echo "Claude Code OAuth credential is invalid." >&2
  _claude_auth_print_login_command
  return 1
fi

# Gate on the refresh token, not the access token. The access token lives ~12h
# and Claude Code renews it from the refresh token inside the sandbox; only an
# expired refresh token actually requires a new browser login.
_claude_auth_expires=$(jq -r '.claudeAiOauth | .refreshTokenExpiresAt // .expiresAt' "$_claude_auth_file")
_claude_auth_now=$(($(date +%s) * 1000))
if ((_claude_auth_expires <= _claude_auth_now)); then
  echo "Claude Code OAuth credential is expired." >&2
  _claude_auth_print_login_command
  return 1
fi

CLAUDE_CODE_OAUTH_TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$_claude_auth_file")
CLAUDE_CODE_OAUTH_REFRESH_TOKEN=$(jq -r '.claudeAiOauth.refreshToken' "$_claude_auth_file")
CLAUDE_CODE_OAUTH_SCOPES=$(jq -r '.claudeAiOauth.scopes | join(" ")' "$_claude_auth_file")
export CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_OAUTH_REFRESH_TOKEN CLAUDE_CODE_OAUTH_SCOPES

CLAUDE_AUTH_DENY_CANONICAL=true

unset _claude_auth_file _claude_auth_expires _claude_auth_now
unset -f _claude_auth_print_login_command
