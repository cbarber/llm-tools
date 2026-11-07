#!/usr/bin/env bats
# jq filters are single-quoted on purpose.
# shellcheck disable=SC2016

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
STATUS="$HERE/context-status"
TEMPLATE="$HERE/../../agents/claude-code/settings.template.json"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  RECORDS="$HOME/.cache/claude/context-size"
}

# show SESSION_ID [CURRENT_USAGE_JSON]
show() {
  local input
  input=$(jq -n --arg s "$1" --argjson u "${2:-null}" \
    '{session_id: $s, context_window: {context_window_size: 200000, current_usage: $u}}')
  run "$STATUS" <<<"$input"
}

@test "the line shows the context size and records it for the session" {
  show s1 '{"input_tokens": 2, "cache_read_input_tokens": 141000, "cache_creation_input_tokens": 1000, "output_tokens": 300}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 142k/200k (71%)" ]
  [ "$(cat "$RECORDS/s1")" = "$(printf '142302\n200000')" ]
  [ "$(find "$RECORDS" -type f | wc -l)" -eq 1 ]
}

@test "an unknown window size is recorded as an empty second line" {
  run "$STATUS" <<<'{"session_id": "s1", "context_window": {"current_usage": {"input_tokens": 5000}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 5k" ]
  [ "$(cat "$RECORDS/s1")" = "$(printf '5000\n')" ]
  [ "$(wc -l <"$RECORDS/s1")" -eq 2 ]
}

@test "an unsafe session id is shown but never recorded" {
  show ../../escape '{"input_tokens": 5000}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 5k/200k (2%)" ]
  [ ! -e "$HOME/.cache/escape" ]
  [ ! -e "$RECORDS" ]
}

@test "unknown usage drops the session's record so the hook reads the transcript" {
  show s1 '{"input_tokens": 150000}'
  [ -f "$RECORDS/s1" ]
  show s1
  [ "$status" -eq 0 ]
  [ "$output" = "ctx –" ]
  [ ! -e "$RECORDS/s1" ]
}

@test "the template wires the status line" {
  run jq -c '.statusLine' "$TEMPLATE"
  [ "$output" = '{"type":"command","command":"context-status"}' ]
}
