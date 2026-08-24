#!/usr/bin/env bats

AUTH_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/setup-opencode-auth.sh"
AGENT_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/agent-sandbox.sh"
COMMON_HELPERS="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/common-helpers.sh"
PATHS_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/setup-sandbox-paths.sh"

setup() {
  TEST_HOME=$(mktemp -d)
  AUTH_FILE="$TEST_HOME/.local/share/opencode/auth.json"
  TEST_REPO=$(mktemp -d)
  mkdir -p "$(dirname "$AUTH_FILE")"
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_REPO"
}

@test "no OAuth grant exposes an empty auth map" {
  run env NIXSMITH_OPENCODE_OAUTH_PROVIDERS='[]' \
    bash -c 'source "$1"; printf "%s\n" "$OPENCODE_AUTH_CONTENT"' _ "$AUTH_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "only granted OAuth providers are exposed" {
  printf '%s\n' '{"openai":{"type":"oauth","access":"openai-access","refresh":"openai-refresh","expires":4102444800000,"accountId":"acct-1","unrecognized":"not-exported"},"anthropic":{"type":"oauth","access":"anthropic-access","refresh":"anthropic-refresh","expires":4102444800000}}' > "$AUTH_FILE"

  run env HOME="$TEST_HOME" NIXSMITH_OPENCODE_OAUTH_PROVIDERS='["openai"]' \
    bash -c 'source "$1"; printf "%s\n" "$OPENCODE_AUTH_CONTENT"' _ "$AUTH_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = '{"openai":{"type":"oauth","access":"openai-access","refresh":"openai-refresh","expires":4102444800000,"accountId":"acct-1"}}' ]
}

@test "missing granted provider fails with the authentication command" {
  printf '%s\n' '{}' > "$AUTH_FILE"

  run env HOME="$TEST_HOME" NIXSMITH_OPENCODE_OAUTH_PROVIDERS='["openai"]' \
    bash -c 'set -e; source "$1"' _ "$AUTH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'OpenCode OAuth credential for provider "openai" is missing.'* ]]
  [[ "$output" == *'nix develop github:cbarber/llm-tools#opencode-auth --command opencode auth login --provider openai --method "ChatGPT Pro/Plus (browser)"'* ]]
}

@test "missing canonical auth file fails with the authentication command" {
  run env HOME="$TEST_HOME/missing" NIXSMITH_OPENCODE_OAUTH_PROVIDERS='["openai"]' \
    bash -c 'set -e; source "$1"' _ "$AUTH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'OpenCode OAuth credential for provider "openai" is missing.'* ]]
  [[ "$output" == *'opencode auth login --provider openai'* ]]
}

@test "expired OAuth credential fails closed" {
  printf '%s\n' '{"openai":{"type":"oauth","access":"expired-access","refresh":"expired-refresh","expires":1}}' > "$AUTH_FILE"

  run env HOME="$TEST_HOME" NIXSMITH_OPENCODE_OAUTH_PROVIDERS='["openai"]' \
    bash -c 'set -e; source "$1"' _ "$AUTH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'OpenCode OAuth credential for provider "openai" is expired.'* ]]
  [[ "$output" != *'expired-access'* ]]
  [[ "$output" != *'expired-refresh'* ]]
}

@test "API credentials cannot satisfy an OAuth grant" {
  printf '%s\n' '{"openai":{"type":"api","key":"raw-api-key"}}' > "$AUTH_FILE"

  run env HOME="$TEST_HOME" NIXSMITH_OPENCODE_OAUTH_PROVIDERS='["openai"]' \
    bash -c 'set -e; source "$1"' _ "$AUTH_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'OpenCode OAuth credential for provider "openai" is invalid.'* ]]
  [[ "$output" == *'opencode auth login --provider openai'* ]]
  [[ "$output" != *'raw-api-key'* ]]
}

@test "repository OAuth metadata wins over path secrets without becoming an environment variable" {
  mkdir -p "$TEST_HOME/.config/nixsmith"
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:scope-owner/project.git
  printf '%s\n' "{\"repos\":{\"git.thingiedoo.com/scope-owner\":{\"_opencodeAuth\":{\"oauthProviders\":[\"openai\"]}}},\"paths\":{\"$TEST_REPO\":{\"ANTHROPIC_API_KEY\":\"path-key\",\"_opencodeAuth\":{\"oauthProviders\":[\"anthropic\"]}}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
    printf "%s\n--env--\n%s" "$NIXSMITH_OPENCODE_OAUTH_PROVIDERS" "$NIXSMITH_SECRETS_ENV"
  ' _ "$TEST_REPO" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = $'["openai"]\n--env--' ]
}

@test "OpenCode launch receives only scoped canonical OAuth credentials" {
  local test_bin="$TEST_HOME/bin"
  mkdir -p "$TEST_HOME/.config/nixsmith" "$TEST_HOME/.local/share/opencode" "$test_bin"
  git -C "$TEST_REPO" init -q
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{\"_opencodeAuth\":{\"oauthProviders\":[\"openai\"]}}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"
  printf '%s\n' '{"openai":{"type":"oauth","access":"scoped-access","refresh":"scoped-refresh","expires":4102444800000},"anthropic":{"type":"oauth","access":"hidden-access","refresh":"hidden-refresh","expires":4102444800000}}' > "$TEST_HOME/.local/share/opencode/auth.json"
  printf '%s\n' '#!/usr/bin/env bash' 'while [[ "$1" != "--" ]]; do' '  if [[ "$1" == "--settings" ]]; then cp "$2" "$FENCE_SETTINGS_CAPTURE"; shift 2' '  elif [[ "$1" == "--expose-host-path-rw" ]]; then exit 99' '  else shift; fi' 'done' 'shift' 'exec "$@"' > "$test_bin/fence"
  printf '%s\n' '#!/usr/bin/env bash' '[[ "$GIT_CONFIG_GLOBAL" == "/dev/null" ]] || exit 98' 'printf "%s\n" "$OPENCODE_AUTH_CONTENT"' > "$test_bin/opencode"
  chmod +x "$test_bin/fence" "$test_bin/opencode"

  run env HOME="$TEST_HOME" PATH="$test_bin:$PATH" FENCE_PATH="$test_bin/fence" \
    FENCE_SETTINGS_CAPTURE="$TEST_HOME/fence.json" \
    TOOLS_DIR="$(dirname "$AUTH_SCRIPT")" \
    bash -c 'cd "$1"; shift; exec "$@"' _ "$TEST_REPO" "$AGENT_SCRIPT" opencode

  [ "$status" -eq 0 ]
  [ "$output" = '{"openai":{"type":"oauth","access":"scoped-access","refresh":"scoped-refresh","expires":4102444800000}}' ]
  jq -e --arg auth "$AUTH_FILE" '.filesystem.denyRead | index($auth)' "$TEST_HOME/fence.json" >/dev/null
  jq -e --arg auth "$AUTH_FILE" '.filesystem.denyWrite | index($auth)' "$TEST_HOME/fence.json" >/dev/null
  jq -e '.filesystem.allowGitConfig == true' "$TEST_HOME/fence.json" >/dev/null
  jq -e --arg config '.git/config' '.filesystem.denyRead | index($config) == null' "$TEST_HOME/fence.json" >/dev/null
  jq -e --arg config '.git/config' '.filesystem.denyWrite | index($config)' "$TEST_HOME/fence.json" >/dev/null
}

@test "longest matching path selects OAuth grants and string environment values" {
  local parent="$TEST_REPO/projects"
  local project="$parent/project"
  mkdir -p "$TEST_HOME/.config/nixsmith" "$project"
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{\"_opencodeAuth\":{\"oauthProviders\":[\"anthropic\"]}},\"$parent\":{\"OPENAI_API_KEY\":\"path-key\",\"_opencodeAuth\":{\"oauthProviders\":[\"openai\"]}}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
    printf "%s\n--env--\n%s" "$NIXSMITH_OPENCODE_OAUTH_PROVIDERS" "$NIXSMITH_SECRETS_ENV"
  ' _ "$project" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = $'["openai"]\n--env--\nOPENAI_API_KEY=path-key' ]
}

@test "non-string environment values in a matched scope fail closed" {
  mkdir -p "$TEST_HOME/.config/nixsmith"
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{\"OPENAI_API_KEY\":{\"nested\":\"value\"}}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    set -e
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
  ' _ "$TEST_REPO" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'values must be strings'* ]]
  [[ "$output" != *'nested'* ]]
}
