#!/usr/bin/env bats
# jq filters are single-quoted on purpose.
# shellcheck disable=SC2016

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK="$HERE/stop-continue"
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

# stop CWD [STOP_HOOK_ACTIVE] [BACKGROUND_TASKS_JSON]
stop() {
  local input
  input=$(jq -n --arg cwd "$1" --argjson active "${2:-false}" --argjson tasks "${3:-[]}" \
    '{hook_event_name: "Stop", cwd: $cwd, stop_hook_active: $active, background_tasks: $tasks}')
  run bash -c 'cd / && "$1" <<<"$2"' _ "$HOOK" "$input"
}

blocked() {
  [ "$status" -eq 0 ] && [ "$(jq -r '.decision' <<<"$output")" = block ]
}

allowed() {
  [ "$status" -eq 0 ] && ! jq -e '.decision == "block"' <<<"$output" >/dev/null
}

@test "approved remaining work resumes from the recorded next action" {
  work-record --cwd "$A" init '.current_ticket = "TASK-1" | .next_action = "review TASK-1 round 0"' >/dev/null
  stop "$A"
  blocked
  reason=$(jq -r '.reason' <<<"$output")
  [[ "$reason" == *"next action: review TASK-1 round 0"* ]]
  [[ "$reason" == *"current ticket TASK-1"* ]]
  [[ "$reason" == *"do not dispatch another"* ]]
}

@test "a running background agent is waited for, not nudged" {
  work-record --cwd "$A" init '.next_action = "reconcile TASK-1 implementer report"' >/dev/null
  stop "$A" false '[{"id": "a1", "type": "local_agent", "status": "running", "description": "implement TASK-1", "agent_type": "general-purpose"}]'
  allowed
  [ -z "$output" ]
}

@test "a finished background agent or a running shell does not suppress the nudge" {
  work-record --cwd "$A" init '.next_action = "reconcile TASK-1 implementer report"' >/dev/null
  stop "$A" false '[{"id": "a1", "type": "local_agent", "status": "completed", "agent_type": "general-purpose"}, {"id": "s1", "type": "shell", "status": "running", "command": "tail -f log"}]'
  blocked
}

@test "pending human gates remain stopped" {
  for gate in "grilling: answer open questions" "design approval" "final review: unresolved findings"; do
    rm -rf "$WORK_RECORD_HOME"
    work-record --cwd "$A" init '.next_action = "implement TASK-1" | .human_gate = $g' --arg g "$gate" >/dev/null
    stop "$A"
    allowed
    stop "$A" true
    allowed
  done
}

@test "completed agent work stops for final human review" {
  work-record --cwd "$A" init '.complete = true' >/dev/null
  stop "$A"
  allowed
  [ -z "$output" ]
}

@test "no record allows the stop silently" {
  stop "$A"
  allowed
  [ -z "$output" ]
}

@test "an inconsistent record stops with a reconcile message" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  echo '{}' >"$(work-record --cwd "$A" path)"
  stop "$A"
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *inconsistent* ]]
}

@test "repeated nudges without progress stop rather than loop" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  stop "$A" false
  blocked
  stop "$A" true
  blocked
  stop "$A" true
  blocked
  stop "$A" true
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"without work-record progress"* ]]
  stop "$A" true
  allowed
}

@test "record progress renews the nudge budget" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  stop "$A" false
  stop "$A" true
  stop "$A" true
  work-record --cwd "$A" record '.next_action = "review TASK-1 round 0"' >/dev/null
  stop "$A" true
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"review TASK-1 round 0"* ]]
}

@test "a stop not caused by a hook continuation starts a new count" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  for _ in 1 2 3 4; do stop "$A" true; done
  allowed
  stop "$A" false
  blocked
}

@test "a stop in one checkout never consults another checkout's record" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  stop "$B"
  allowed
  [ -z "$output" ]

  work-record --cwd "$B" init '.next_action = "implement TASK-2" | .human_gate = "design approval"' >/dev/null
  stop "$B"
  allowed
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"implement TASK-1"* ]]
}

@test "a stop in a subdirectory uses its checkout's record" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  mkdir -p "$A/sub/dir"
  stop "$A/sub/dir"
  blocked
}

@test "the template runs stop-continue beside notify in one Stop group" {
  run jq -c '[.hooks.Stop[] | select(.matcher == "") | .hooks[].command]' "$TEMPLATE"
  [ "$output" = '["notify","stop-continue"]' ]
  run jq -c '.hooks.Stop | length' "$TEMPLATE"
  [ "$output" = 1 ]
}
