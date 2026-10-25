#!/usr/bin/env bats
# jq filters are single-quoted on purpose.
# shellcheck disable=SC2016

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK="$HERE/compact-resume"
TEMPLATE="$HERE/../../agents/claude-code/settings.template.json"

setup() {
  SCRATCH=$(mktemp -d)
  export WORK_RECORD_HOME="$SCRATCH/store"
  mkdir -p "$SCRATCH/bin"
  ln -s "$HERE/../work-record" "$SCRATCH/bin/work-record"
  export PATH="$SCRATCH/bin:$PATH"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  A=$(make_repo a)
  B=$(make_repo b)
}

teardown() {
  rm -rf "$SCRATCH"
}

make_repo() {
  local path="$SCRATCH/$1"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" commit -q --allow-empty -m root
  (cd "$path" && pwd -P)
}

# session_start CWD [SOURCE]
session_start() {
  local input
  input=$(jq -n --arg cwd "$1" --arg source "${2:-compact}" \
    '{hook_event_name: "SessionStart", session_id: "s1", cwd: $cwd, source: $source}')
  run bash -c 'cd / && "$1" <<<"$2"' _ "$HOOK" "$input"
}

context() {
  jq -r '.hookSpecificOutput | select(.hookEventName == "SessionStart") | .additionalContext' <<<"$output"
}

points_to_resume() {
  [ "$status" -eq 0 ] && [[ "$(context)" == *"invoke the mojo-resume skill"* ]]
}

@test "compaction during approved work points to the resume entry" {
  work-record --cwd "$A" init '.current_ticket = "TASK-1" | .next_action = "review TASK-1 round 0"' >/dev/null
  session_start "$A"
  points_to_resume
  [[ "$(context)" == *"continuation: continue"* ]]
  [[ "$(context)" == *"$(work-record --cwd "$A" path)"* ]]
}

@test "compaction at a human gate points to the resume entry and leaves the gate" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1" | .human_gate = "design approval"' >/dev/null
  before=$(work-record --cwd "$A" read)
  session_start "$A"
  points_to_resume
  [[ "$(context)" == *"continuation: wait-for-human"* ]]
  [[ "$(context)" == *"human gate stays pending"* ]]
  [ "$(work-record --cwd "$A" read)" = "$before" ]
}

@test "an inconsistent record still routes through the resume entry" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  echo '{}' >"$(work-record --cwd "$A" path)"
  session_start "$A"
  points_to_resume
  [[ "$(context)" == *"continuation: inconsistent"* ]]
}

@test "completed work or no record adds nothing" {
  session_start "$A"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  work-record --cwd "$A" init '.complete = true' >/dev/null
  session_start "$A"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "other session starts add nothing" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  for source in startup resume clear fork; do
    session_start "$A" "$source"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "compaction in one checkout never consults another checkout's record" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  session_start "$B"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a compaction confirms a pending Herdr renewal, which submits the single resume entry" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  renewal="$(dirname "$(work-record --cwd "$A" path)")/renewal"
  echo '{"handoff": "h1", "session_id": "s1", "pane": "w9:p9", "state": "requested", "attempt": "a1"}' >"$renewal"
  session_start "$A"
  points_to_resume
  [ "$(jq -c . "$renewal")" = '{"handoff":"h1","session_id":"s1","pane":"w9:p9","state":"compacted","attempt":"a1"}' ]
  [[ "$(context)" == *"Herdr submits /mojo-resume as the next prompt"* ]]
  [[ "$(context)" == *"do not invoke mojo-resume a second time"* ]]
}

@test "a compaction without a pending renewal leaves renewal state alone" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  renewal="$(dirname "$(work-record --cwd "$A" path)")/renewal"
  echo '{"handoff": "h1", "session_id": "s1", "state": "compacted"}' >"$renewal"
  session_start "$A"
  points_to_resume
  [ "$(jq -r .state "$renewal")" = compacted ]
  [[ "$(context)" != *"Herdr submits"* ]]
  echo '{"handoff": "h1", "session_id": "s1", "state": "requested"}' >"$renewal"
  session_start "$A" startup
  [ "$(jq -r .state "$renewal")" = requested ]
}

@test "another session's compaction does not confirm a renewal" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  renewal="$(dirname "$(work-record --cwd "$A" path)")/renewal"
  for request in '{"handoff": "h1", "session_id": "s0", "state": "requested", "attempt": "a1"}' '{"handoff": "h1", "state": "requested", "attempt": "a1"}'; do
    echo "$request" >"$renewal"
    session_start "$A"
    points_to_resume
    [ "$(jq -r .state "$renewal")" = requested ]
    [[ "$(context)" != *"Herdr submits"* ]]
  done
}

@test "a request the helper has not armed is not confirmed" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  renewal="$(dirname "$(work-record --cwd "$A" path)")/renewal"
  echo '{"handoff": "h1", "session_id": "s1", "state": "requested"}' >"$renewal"
  session_start "$A"
  points_to_resume
  [ "$(jq -r .state "$renewal")" = requested ]
  [[ "$(context)" != *"Herdr submits"* ]]
}

@test "the template runs compact-resume only after compaction" {
  run jq -c '[.hooks.SessionStart[] | {matcher, commands: [.hooks[].command]}]' "$TEMPLATE"
  [ "$output" = '[{"matcher":"compact","commands":["compact-resume"]}]' ]
}
