#!/usr/bin/env bats

AUTH_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/setup-claude-auth.sh"
AGENT_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/agent-sandbox.sh"
COMMON_HELPERS="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/common-helpers.sh"
PATHS_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/setup-sandbox-paths.sh"

setup() {
  TEST_HOME=$(mktemp -d)
  TEST_REPO=$(mktemp -d)
  AUTH_FILE="$TEST_HOME/.claude/.credentials.json"
  mkdir -p "$(dirname "$AUTH_FILE")"
  # Far-future epoch-ms values so the suite does not rot.
  FUTURE=4102444800000
  PAST=1000000000000
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_REPO"
}

# Sourced in a child shell. The explicit `|| exit` is required: a `return` from
# a sourced script does not set the shell's exit status, the last command does.
EMIT='source "$1" || exit $?
  printf "token=%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-}"
  printf "refresh=%s\n" "${CLAUDE_CODE_OAUTH_REFRESH_TOKEN:-}"
  printf "scopes=%s\n" "${CLAUDE_CODE_OAUTH_SCOPES:-}"
  printf "deny=%s\n" "${CLAUDE_AUTH_DENY_CANONICAL:-}"'

write_credential() {
  printf '%s\n' "$1" > "$AUTH_FILE"
}

@test "without the grant nothing is exported and the file stays readable" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$FUTURE,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[\"user:inference\"]}}"

  run env HOME="$TEST_HOME" bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"token="* ]]
  [[ "$output" != *"token=a"* ]]
  [[ "$output" == *"deny=false"* ]]
}

@test "granted credential exports the OAuth triple and denies the canonical file" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$FUTURE,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[\"user:inference\",\"user:profile\"]}}"

  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"token=a"* ]]
  [[ "$output" == *"refresh=r"* ]]
  [[ "$output" == *"scopes=user:inference user:profile"* ]]
  [[ "$output" == *"deny=true"* ]]
}

@test "inherited OAuth values never leak through" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"fresh\",\"refreshToken\":\"r\",\"expiresAt\":$FUTURE,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[\"user:inference\"]}}"

  run env HOME="$TEST_HOME" CLAUDE_CODE_OAUTH_TOKEN=stale bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"token=stale"* ]]
}

@test "an expired access token is still usable while the refresh token lives" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$PAST,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[\"user:inference\"]}}"

  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"token=a"* ]]
}

@test "an expired refresh token aborts with the authentication command" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$PAST,\"refreshTokenExpiresAt\":$PAST,\"scopes\":[\"user:inference\"]}}"

  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expired"* ]]
  [[ "$output" == *"claude-code-auth"* ]]
}

@test "a missing credential file aborts with the authentication command" {
  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"claude-code-auth"* ]]
}

@test "a malformed credential aborts with the authentication command" {
  write_credential '{"claudeAiOauth":{"accessToken":"","refreshToken":"r","expiresAt":1,"scopes":["user:inference"]}}'

  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
  [[ "$output" == *"claude-code-auth"* ]]
}

@test "a credential without scopes is rejected" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$FUTURE,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[]}}"

  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "a credential with no refreshTokenExpiresAt falls back to expiresAt" {
  write_credential "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$PAST,\"scopes\":[\"user:inference\"]}}"

  run env HOME="$TEST_HOME" NIXSMITH_CLAUDE_OAUTH=true bash -c "$EMIT" _ "$AUTH_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expired"* ]]
}

@test "the _claudeAuth grant reaches the launch without becoming an environment variable" {
  mkdir -p "$TEST_HOME/.config/nixsmith"
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{\"ANTHROPIC_API_KEY\":\"path-key\",\"_claudeAuth\":{\"oauth\":true}}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
    printf "%s\n--env--\n%s" "$NIXSMITH_CLAUDE_OAUTH" "$NIXSMITH_SECRETS_ENV"
  ' _ "$TEST_REPO" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == "true"* ]]
  [[ "$output" == *"ANTHROPIC_API_KEY=path-key"* ]]
  [[ "$output" != *"_claudeAuth"* ]]
}

@test "a launch without the grant leaves the credential file readable" {
  mkdir -p "$TEST_HOME/.config/nixsmith"
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
    printf "%s" "$NIXSMITH_CLAUDE_OAUTH"
  ' _ "$TEST_REPO" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "Claude Code launch receives the OAuth triple and the canonical file is denied" {
  local test_bin="$TEST_HOME/bin"
  mkdir -p "$TEST_HOME/.config/nixsmith" "$test_bin"
  git -C "$TEST_REPO" init -q
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{\"_claudeAuth\":{\"oauth\":true}}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"
  printf '%s\n' "{\"claudeAiOauth\":{\"accessToken\":\"scoped-access\",\"refreshToken\":\"scoped-refresh\",\"expiresAt\":$PAST,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[\"user:inference\",\"user:profile\"]}}" > "$AUTH_FILE"
  printf '%s\n' '#!/usr/bin/env bash' 'while [[ "$1" != "--" ]]; do' '  if [[ "$1" == "--settings" ]]; then cp "$2" "$FENCE_SETTINGS_CAPTURE"; shift 2' '  elif [[ "$1" == "--expose-host-path-rw" ]]; then exit 99' '  else shift; fi' 'done' 'shift' 'exec "$@"' > "$test_bin/fence"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s|%s|%s\n" "$CLAUDE_CODE_OAUTH_TOKEN" "$CLAUDE_CODE_OAUTH_REFRESH_TOKEN" "$CLAUDE_CODE_OAUTH_SCOPES"' > "$test_bin/claude"
  chmod +x "$test_bin/fence" "$test_bin/claude"

  run env HOME="$TEST_HOME" PATH="$test_bin:$PATH" FENCE_PATH="$test_bin/fence" \
    FENCE_SETTINGS_CAPTURE="$TEST_HOME/fence.json" \
    TOOLS_DIR="$(dirname "$AUTH_SCRIPT")" \
    bash -c 'cd "$1"; shift; exec "$@"' _ "$TEST_REPO" "$AGENT_SCRIPT" claude

  [ "$status" -eq 0 ]
  [ "$output" = 'scoped-access|scoped-refresh|user:inference user:profile' ]
  jq -e --arg cred "$AUTH_FILE" '.filesystem.denyRead | index($cred)' "$TEST_HOME/fence.json" >/dev/null
  jq -e --arg cred "$AUTH_FILE" '.filesystem.denyWrite | index($cred)' "$TEST_HOME/fence.json" >/dev/null
}

@test "an ungranted Claude Code launch does not deny the credential file" {
  local test_bin="$TEST_HOME/bin"
  mkdir -p "$TEST_HOME/.config/nixsmith" "$test_bin"
  git -C "$TEST_REPO" init -q
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"
  printf '%s\n' "{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r\",\"expiresAt\":$FUTURE,\"refreshTokenExpiresAt\":$FUTURE,\"scopes\":[\"user:inference\"]}}" > "$AUTH_FILE"
  printf '%s\n' '#!/usr/bin/env bash' 'while [[ "$1" != "--" ]]; do' '  if [[ "$1" == "--settings" ]]; then cp "$2" "$FENCE_SETTINGS_CAPTURE"; shift 2' '  elif [[ "$1" == "--expose-host-path-rw" ]]; then exit 99' '  else shift; fi' 'done' 'shift' 'exec "$@"' > "$test_bin/fence"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "${CLAUDE_CODE_OAUTH_TOKEN:-unset}"' > "$test_bin/claude"
  chmod +x "$test_bin/fence" "$test_bin/claude"

  run env HOME="$TEST_HOME" PATH="$test_bin:$PATH" FENCE_PATH="$test_bin/fence" \
    FENCE_SETTINGS_CAPTURE="$TEST_HOME/fence.json" \
    TOOLS_DIR="$(dirname "$AUTH_SCRIPT")" \
    bash -c 'cd "$1"; shift; exec "$@"' _ "$TEST_REPO" "$AGENT_SCRIPT" claude

  [ "$status" -eq 0 ]
  [ "$output" = 'unset' ]
  jq -e --arg cred "$AUTH_FILE" '.filesystem.denyRead | index($cred) == null' "$TEST_HOME/fence.json" >/dev/null
}
