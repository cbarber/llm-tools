#!/usr/bin/env bats

TOOLS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SETUP_SCRIPT="${TOOLS_DIR}/setup-agent-api-tokens.sh"
COMMON_HELPERS="${TOOLS_DIR}/common-helpers.sh"
PATHS_SCRIPT="${TOOLS_DIR}/setup-sandbox-paths.sh"
SHARED_SCRIPT="${TOOLS_DIR}/setup-shared-shell.sh"
FORGE_SCRIPT="${TOOLS_DIR}/forge"

setup() {
  TEST_HOME=$(mktemp -d)
  TEST_REPO=$(mktemp -d)
  TEST_BIN=$(mktemp -d)
  mkdir -p "$TEST_HOME/.config/nixsmith"
  git -C "$TEST_REPO" init -q
}

teardown() {
  rm -rf "$TEST_HOME" "$TEST_REPO" "$TEST_BIN"
}

@test "repository scopes normalize SSH and HTTPS origin URLs" {
  git -C "$TEST_REPO" remote add origin git@github.com:CBarber/project.git

  run bash -c 'cd "$1"; source "$2"; extract_repo_url' _ "$TEST_REPO" "$COMMON_HELPERS"

  [ "$status" -eq 0 ]
  [ "$output" = "github.com/cbarber/project" ]

  git -C "$TEST_REPO" remote set-url origin https://git.thingiedoo.com/CBarber/project.git

  run bash -c 'cd "$1"; source "$2"; extract_repo_url' _ "$TEST_REPO" "$COMMON_HELPERS"

  [ "$status" -eq 0 ]
  [ "$output" = "git.thingiedoo.com/cbarber/project" ]

  git -C "$TEST_REPO" remote set-url origin https://github.com/CBarber/project.git/

  run bash -c 'cd "$1"; source "$2"; extract_repo_url' _ "$TEST_REPO" "$COMMON_HELPERS"

  [ "$status" -eq 0 ]
  [ "$output" = "github.com/cbarber/project" ]
}

@test "longest repository URL prefix wins at a path boundary" {
  git -C "$TEST_REPO" remote add origin git@github.com:cbarber/project.git
  printf '%s\n' '{"repos":{"github.com/cbarber":{"VALUE":"owner"},"github.com/cbarber/project":{"VALUE":"repo"},"github.com/cbar":{"VALUE":"sibling"}}}' > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c 'cd "$1"; source "$2"; nixsmith_repo_scope_key "$HOME/.config/nixsmith/secrets.json"' _ "$TEST_REPO" "$COMMON_HELPERS"

  [ "$status" -eq 0 ]
  [ "$output" = "github.com/cbarber/project" ]

  git -C "$TEST_REPO" remote set-url origin git@github.com:cbarber-old/project.git

  run env HOME="$TEST_HOME" bash -c 'cd "$1"; source "$2"; nixsmith_repo_scope_key "$HOME/.config/nixsmith/secrets.json"' _ "$TEST_REPO" "$COMMON_HELPERS"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Gitea token in secrets.json authenticates tea without persistent config" {
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:cbarber/project.git
  printf '%s\n' '{"repos":{"git.thingiedoo.com/cbarber":{"GITEA_TOKEN":"test-token"}}}' > "$TEST_HOME/.config/nixsmith/secrets.json"
  mkdir -p "$TEST_HOME/.config/nixsmith/tea"
  printf '%s\n' 'legacy-token-config' > "$TEST_HOME/.config/nixsmith/tea/config.yml"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s|%s|%s\n" "$GITEA_INSTANCE_URL" "$GITEA_TOKEN" "$*" >> "$TEA_CALLS"' '[[ "$*" == "api /repos/{owner}/{repo} --output /dev/null" ]]' > "$TEST_BIN/tea"
  chmod +x "$TEST_BIN/tea"

  run env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" TEA_CALLS="$TEST_HOME/tea-calls" \
    bash -c 'cd "$1"; "$2"' _ "$TEST_REPO" "$SETUP_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent API tokens verified"* ]]
  grep -Fxq 'https://git.thingiedoo.com|test-token|api /repos/{owner}/{repo} --output /dev/null' "$TEST_HOME/tea-calls"
  [ ! -e "$TEST_HOME/.config/nixsmith/tea/config.yml" ]
}

@test "failed Gitea verification fails setup" {
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:cbarber/project.git
  printf '%s\n' '{"repos":{"git.thingiedoo.com/cbarber":{"GITEA_TOKEN":"test-token"}}}' > "$TEST_HOME/.config/nixsmith/secrets.json"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "tea verification detail" >&2' 'exit 42' > "$TEST_BIN/tea"
  chmod +x "$TEST_BIN/tea"

  run env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" bash -c 'cd "$1"; "$2"' _ "$TEST_REPO" "$SETUP_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'Token verification failed'* ]]
  [[ "$output" == *'tea verification detail'* ]]
  [[ "$output" != *'Agent API tokens verified'* ]]
}

@test "new Gitea token is stored safely in secrets.json" {
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:cbarber/project.git
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_BIN/xdg-open"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_BIN/tea"
  chmod +x "$TEST_BIN/xdg-open" "$TEST_BIN/tea"

  run env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" \
    bash -c 'cd "$1"; printf '\''%s\n'\'' '\''test-"token'\'' | "$2"' _ "$TEST_REPO" "$SETUP_SCRIPT"

  [ "$status" -eq 0 ]
  run jq -r '.repos["git.thingiedoo.com/cbarber"].GITEA_TOKEN' "$TEST_HOME/.config/nixsmith/secrets.json"
  [ "$status" -eq 0 ]
  [ "$output" = 'test-"token' ]
}

@test "failed secrets.json update fails setup" {
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:cbarber/project.git
  printf '%s\n' '{invalid' > "$TEST_HOME/.config/nixsmith/secrets.json"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_BIN/xdg-open"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_BIN/tea"
  chmod +x "$TEST_BIN/xdg-open" "$TEST_BIN/tea"

  run env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" \
    bash -c 'cd "$1"; printf '\''%s\n'\'' '\''test-token'\'' | "$2"' _ "$TEST_REPO" "$SETUP_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to update $TEST_HOME/.config/nixsmith/secrets.json"* ]]
  [[ "$output" != *'Gitea token configured'* ]]
}

@test "sandbox derives Tea instance URL from a Gitea repository scope" {
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:cbarber/project.git
  printf '%s\n' '{"repos":{"git.thingiedoo.com/cbarber":{"GITEA_TOKEN":"test-token","GITEA_INSTANCE_URL":"https://evil.example"}}}' > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
    printf "%s--derived--\n%s" "$NIXSMITH_SECRETS_ENV" "$NIXSMITH_DERIVED_ENV"
  ' _ "$TEST_REPO" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'GITEA_TOKEN=test-token\n'* ]]
  [[ "${output%%--derived--*}" != *'GITEA_INSTANCE_URL='* ]]
  [[ "$output" == *$'--derived--\nGITEA_INSTANCE_URL=https://git.thingiedoo.com'* ]]
  [[ "$output" != *'evil.example'* ]]
}

@test "Gitea token without a repository origin fails closed" {
  printf '%s\n' "{\"paths\":{\"$TEST_REPO\":{\"GITEA_TOKEN\":\"test-token\"}}}" > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c '
    set -e
    cd "$1"
    SANDBOX_MOUNTS_RO=()
    SANDBOX_MOUNTS_RW=()
    source "$2"
    source "$3"
  ' _ "$TEST_REPO" "$COMMON_HELPERS" "$PATHS_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'without a repository origin'* ]]
}

@test "legacy GitHub owner scope migrates to host path" {
  git -C "$TEST_REPO" remote add origin git@github.com:cbarber/project.git
  printf '%s\n' '{"repos":{"github:cbarber":{"GH_TOKEN":"test-token","VALUE":"preserved"}}}' > "$TEST_HOME/.config/nixsmith/secrets.json"

  run env HOME="$TEST_HOME" bash -c 'cd "$1"; "$2"' _ "$TEST_REPO" "$SETUP_SCRIPT"

  [ "$status" -eq 0 ]
  jq -e '.repos["github:cbarber"] == null and .repos["github.com/cbarber"] == {"GH_TOKEN":"test-token","VALUE":"preserved"}' \
    "$TEST_HOME/.config/nixsmith/secrets.json" >/dev/null
}

@test "shared shell removes inherited forge credentials" {
  run env HOME="$TEST_HOME" TOOLS_DIR="$TOOLS_DIR" AGENT_ENV_CONFIG_DIR="$TEST_HOME" \
    SKIP_AGENT_SETUP=true GH_TOKEN=github-token GITHUB_TOKEN=github-token \
    GITEA_TOKEN=gitea-token GITEA_INSTANCE_URL=https://git.thingiedoo.com \
    bash -c 'cd "$1"; source "$2"; printf "%s|%s|%s|%s" "${GH_TOKEN:-}" "${GITHUB_TOKEN:-}" "${GITEA_TOKEN:-}" "${GITEA_INSTANCE_URL:-}"' \
    _ "$TEST_REPO" "$SHARED_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = '|||' ]
}

@test "forge authenticates Gitea from its injected environment" {
  git -C "$TEST_REPO" remote add origin git@git.thingiedoo.com:cbarber/project.git
  printf '%s\n' '#!/usr/bin/env bash' 'set -e' '[[ "$GITEA_INSTANCE_URL" == "https://git.thingiedoo.com" ]]' '[[ "$GITEA_TOKEN" == "test-token" ]]' '[[ "$*" == "api /repos/{owner}/{repo} --output /dev/null" ]]' '[[ ! -e "$HOME/.config/nixsmith/tea/config.yml" ]]' > "$TEST_BIN/tea"
  chmod +x "$TEST_BIN/tea"

  run env HOME="$TEST_HOME" PATH="$TEST_BIN:$PATH" \
    GITEA_INSTANCE_URL=https://git.thingiedoo.com GITEA_TOKEN=test-token \
    bash -c 'cd "$1"; "$2" --type' _ "$TEST_REPO" "$FORGE_SCRIPT"

  [ "$status" -eq 0 ]
  [ "$output" = 'gitea' ]
}
