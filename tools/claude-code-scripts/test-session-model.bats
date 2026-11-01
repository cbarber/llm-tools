#!/usr/bin/env bats
# jq filters are single-quoted on purpose.
# shellcheck disable=SC2016

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK="$HERE/session-model"
TEMPLATE="$HERE/../../agents/claude-code/settings.template.json"

setup() {
  SCRATCH=$(mktemp -d)
  export CLAUDE_ENV_FILE="$SCRATCH/env"
}

teardown() {
  rm -rf "$SCRATCH"
}

# session_start [MODEL]
session_start() {
  local input
  input=$(jq -n --arg source startup '{hook_event_name: "SessionStart", session_id: "s1", cwd: "/", source: $source}')
  [[ $# -eq 0 ]] || input=$(jq --arg model "$1" '.model = $model' <<<"$input")
  run "$HOOK" <<<"$input"
}

# The value a later Bash command sees after running the env file.
exported_model() {
  bash -c 'source "$1" && printf %s "${AUTHORED_BY_MODEL-unset}"' _ "$CLAUDE_ENV_FILE"
}

@test "the session's model is exported for later commands" {
  session_start claude-opus-5
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_ENV_FILE")" = "export AUTHORED_BY_MODEL=claude-opus-5" ]
  [ "$(exported_model)" = claude-opus-5 ]
}

@test "an export from another hook is kept" {
  echo 'export OTHER=1' >"$CLAUDE_ENV_FILE"
  session_start claude-opus-5
  [ "$(head -n1 "$CLAUDE_ENV_FILE")" = "export OTHER=1" ]
  [ "$(exported_model)" = claude-opus-5 ]
}

@test "a session without a model writes nothing" {
  session_start
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_ENV_FILE" ]
}

@test "an empty model writes nothing" {
  session_start ""
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_ENV_FILE" ]
}

@test "without an env file the hook writes nothing" {
  unset CLAUDE_ENV_FILE
  session_start claude-opus-5
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$SCRATCH")" ]
}

@test "a model with shell metacharacters is exported verbatim, never run" {
  local model
  model=$'x"; touch '"$SCRATCH"$'/pwned; echo \'$(touch '"$SCRATCH"$'/pwned)`id`\nexport AUTHORED_BY_MODEL=forged'
  session_start "$model"
  [ "$status" -eq 0 ]
  [ "$(exported_model)" = "$model" ]
  [ ! -e "$SCRATCH/pwned" ]
}

@test "the template exports the model on every session start" {
  run jq -c '[.hooks.SessionStart[] | select(.matcher == "") | .hooks[].command]' "$TEMPLATE"
  [ "$output" = '["session-model"]' ]
}
