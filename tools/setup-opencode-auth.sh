#!/usr/bin/env bash

OPENCODE_AUTH_CONTENT="{}"
export OPENCODE_AUTH_CONTENT

[[ "${NIXSMITH_OPENCODE_OAUTH_PROVIDERS:-[]}" != "[]" ]] || return 0

_opencode_auth_print_login_command() {
  if [[ "$1" == "openai" ]]; then
    echo 'Run: nix develop github:cbarber/llm-tools#opencode-auth --command opencode auth login --provider openai --method "ChatGPT Pro/Plus (browser)"' >&2
  else
    printf 'Run: nix develop github:cbarber/llm-tools#opencode-auth --command opencode auth login --provider %q\n' "$1" >&2
  fi
}

_opencode_auth_file="${HOME}/.local/share/opencode/auth.json"

while IFS= read -r _opencode_auth_provider; do
  if ! jq -e --arg provider "$_opencode_auth_provider" 'has($provider)' "$_opencode_auth_file" >/dev/null 2>&1; then
    echo "OpenCode OAuth credential for provider \"${_opencode_auth_provider}\" is missing." >&2
    _opencode_auth_print_login_command "$_opencode_auth_provider"
    return 1
  fi

  if ! jq -e --arg provider "$_opencode_auth_provider" \
    '.[$provider] | type == "object" and .type == "oauth" and
      (.access | type == "string" and length > 0) and
      (.refresh | type == "string" and length > 0) and
      (.expires | type == "number" and floor == .) and
      (if has("accountId") then (.accountId | type == "string") else true end) and
      (if has("enterpriseUrl") then (.enterpriseUrl | type == "string") else true end)' \
    "$_opencode_auth_file" >/dev/null 2>&1; then
    echo "OpenCode OAuth credential for provider \"${_opencode_auth_provider}\" is invalid." >&2
    _opencode_auth_print_login_command "$_opencode_auth_provider"
    return 1
  fi

  _opencode_auth_expires=$(jq -r --arg provider "$_opencode_auth_provider" '.[$provider].expires' "$_opencode_auth_file")
  _opencode_auth_now=$(($(date +%s) * 1000))
  if (( _opencode_auth_expires <= _opencode_auth_now )); then
    echo "OpenCode OAuth credential for provider \"${_opencode_auth_provider}\" is expired." >&2
    _opencode_auth_print_login_command "$_opencode_auth_provider"
    return 1
  fi
done < <(jq -r '.[]' <<< "$NIXSMITH_OPENCODE_OAUTH_PROVIDERS")

OPENCODE_AUTH_CONTENT=$(jq -c \
  --argjson providers "$NIXSMITH_OPENCODE_OAUTH_PROVIDERS" \
  'with_entries(.key as $key | select($providers | index($key))) |
    with_entries(.value |= ({type, access, refresh, expires} +
      (if has("accountId") then {accountId} else {} end) +
      (if has("enterpriseUrl") then {enterpriseUrl} else {} end)))' \
  "$_opencode_auth_file")
export OPENCODE_AUTH_CONTENT
unset _opencode_auth_file _opencode_auth_provider _opencode_auth_expires _opencode_auth_now
unset -f _opencode_auth_print_login_command
