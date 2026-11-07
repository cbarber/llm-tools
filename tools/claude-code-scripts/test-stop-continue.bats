#!/usr/bin/env bats
# jq filters are single-quoted on purpose.
# shellcheck disable=SC2016

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
HOOK="$HERE/stop-continue"
TEMPLATE="$HERE/../../agents/claude-code/settings.template.json"

setup() {
  SCRATCH=$(mktemp -d)
  export WORK_RECORD_HOME="$SCRATCH/store"
  # The status line's context-size records live under HOME.
  export HOME="$SCRATCH/home"
  mkdir -p "$SCRATCH/bin"
  ln -s "$HERE/../work-record" "$SCRATCH/bin/work-record"
  # Herdr is absent unless a test opts in; even then the hook only writes a
  # request and never calls Herdr itself.
  unset HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_WORKSPACE_ID HERDR_TAB_ID CLAUDE_RENEWAL_TOKENS
  export PATH="$SCRATCH/bin:$PATH"
  # A stop follows an assistant turn, so the transcript holds its usage.
  context 1000
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
  input=$(jq -n --arg cwd "$1" --argjson active "${2:-false}" --argjson tasks "${3:-[]}" --arg transcript "$SCRATCH/transcript.jsonl" \
    '{hook_event_name: "Stop", session_id: "s1", cwd: $cwd, stop_hook_active: $active, background_tasks: $tasks, transcript_path: $transcript}')
  run bash -c 'cd / && "$1" <<<"$2"' _ "$HOOK" "$input"
}

blocked() {
  [ "$status" -eq 0 ] && [ "$(jq -r '.decision' <<<"$output")" = block ]
}

# context TOKENS: the main conversation last reported TOKENS of context.
context() {
  jq -nc --argjson t "$1" '{type: "assistant", message: {role: "assistant", usage: {input_tokens: 2, cache_read_input_tokens: ($t - 102), cache_creation_input_tokens: 50, output_tokens: 50}}}' \
    >>"$SCRATCH/transcript.jsonl"
}

link_handoff() {
  echo "Next: implement TASK-1" >"$SCRATCH/handoff.md"
  work-record --cwd "$1" handoff "$SCRATCH/handoff.md" >/dev/null
}

renewal_request() {
  jq -c . "$(dirname "$(work-record --cwd "$1" path)")/renewal" 2>/dev/null || true
}

expected_request() {
  work-record --cwd "$1" read |
    jq -c '{handoff: .artifacts.handoff.record, session_id: "s1", pane: "w9:p9", state: "requested"}'
}

# fail_work_record COMMAND: work-record fails COMMAND as an unexpected error
# would, and runs every other command as usual.
fail_work_record() {
  mkdir -p "$SCRATCH/failing"
  cat >"$SCRATCH/failing/work-record" <<STUB
#!$BASH
[[ "\$3" != "$1" ]] || { echo "work-record: simulated $1 failure" >&2; exit 5; }
exec "$SCRATCH/bin/work-record" "\$@"
STUB
  chmod +x "$SCRATCH/failing/work-record"
  export PATH="$SCRATCH/failing:$PATH"
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

@test "a missing work-record is reported and the stop allowed" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  PATH=$(tr : '\n' <<<"$PATH" | while read -r dir; do [ -e "$dir/work-record" ] || echo "$dir"; done | paste -sd:)
  [ -z "$(command -v work-record)" ]
  stop "$A"
  allowed
  message=$(jq -r '.systemMessage' <<<"$output")
  [[ "$message" == "Could not consult the work record for $A, so this stop was allowed: \`work-record check\` exited 127: "*"work-record: command not found" ]]
}

@test "a record unreadable after the check is reported and the stop allowed" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  fail_work_record read
  stop "$A"
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"\`work-record read\` exited 5: work-record: simulated read failure" ]]
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

@test "a current handoff allows the stop until context is renewed" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  echo "Next: implement TASK-1" >"$SCRATCH/handoff.md"
  work-record --cwd "$A" handoff "$SCRATCH/handoff.md" >/dev/null
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" false
  allowed
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true
  allowed
  [ -z "$output" ]
}

@test "a stale handoff nudges as before" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  echo "Next: implement TASK-1" >"$SCRATCH/handoff.md"
  work-record --cwd "$A" handoff "$SCRATCH/handoff.md" >/dev/null
  work-record --cwd "$A" record '.next_action = "review TASK-1 round 0"' >/dev/null
  [ "$(work-record --cwd "$A" handoff)" = stale ]
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"review TASK-1 round 0"* ]]
}

@test "the template runs stop-continue beside notify in one Stop group" {
  run jq -c '[.hooks.Stop[] | select(.matcher == "") | .hooks[].command]' "$TEMPLATE"
  [ "$output" = '["notify","stop-continue"]' ]
  run jq -c '.hooks.Stop | length' "$TEMPLATE"
  [ "$output" = 1 ]
}

@test "below the renewal threshold the stop continues as usual" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 174999
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  [ "$(jq -r '.systemMessage // empty' <<<"$output")" = "" ]
}

@test "the renewal threshold asks to finish the step and hand off" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 175000
  stop "$A"
  blocked
  reason=$(jq -r '.reason' <<<"$output")
  [[ "$reason" == *"175000 tokens (renewal threshold 175000); hand off for renewal"* ]]
  [[ "$reason" == *"Finish the step you are on"* && "$reason" == *"invoke the mojo-handoff skill"* ]]
  [[ "$reason" != *"next action"* ]]
}

@test "the renewal threshold is a setting" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 5000
  CLAUDE_RENEWAL_TOKENS=6000 stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  CLAUDE_RENEWAL_TOKENS=5000 stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"(renewal threshold 5000); hand off"* ]]
}

@test "context is counted from the main conversation since the last compaction" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 250000
  {
    echo '{"type": "system", "subtype": "compact_boundary", "compactMetadata": {"trigger": "manual"}}'
    jq -nc '{type: "assistant", isSidechain: true, message: {usage: {input_tokens: 190000}}}'
    echo 'not json'
  } >>"$SCRATCH/transcript.jsonl"
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  context 210000
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"hand off for renewal"* ]]
}

@test "an unreadable transcript is reported rather than silently disabling renewal" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  mv "$SCRATCH/transcript.jsonl" "$SCRATCH/moved.jsonl"
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context size is unknown"* ]]

  run bash -c 'cd / && "$1" <<<"$2"' _ "$HOOK" "$(jq -n --arg cwd "$A" '{cwd: $cwd, background_tasks: [{status: "running", agent_type: "general-purpose"}]}')"
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context size is unknown"* ]]
}

@test "a transcript tail without main-conversation usage is reported rather than counted as no context" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  jq -nc '{type: "assistant", isSidechain: true, message: {usage: {input_tokens: 190000}}}' >"$SCRATCH/transcript.jsonl"
  for _ in $(seq 500); do echo '{"type": "progress"}'; done >>"$SCRATCH/transcript.jsonl"
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context size is unknown: the last 500 lines of the session transcript hold no main-conversation usage"* ]]

  echo '{"type": "system", "subtype": "compact_boundary", "compactMetadata": {"trigger": "manual"}}' >>"$SCRATCH/transcript.jsonl"
  stop "$A"
  blocked
  [ "$(jq -r '.systemMessage // empty' <<<"$output")" = "" ]
}

@test "the status line's recorded context size is read before the transcript" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  mkdir -p "$HOME/.cache/claude/context-size"
  echo 210000 >"$HOME/.cache/claude/context-size/s1"
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"Context holds 210000 tokens"* ]]

  mv "$SCRATCH/transcript.jsonl" "$SCRATCH/moved.jsonl"
  echo 1000 >"$HOME/.cache/claude/context-size/s1"
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  [ "$(jq -r '.systemMessage // empty' <<<"$output")" = "" ]
}

# record TOKENS [WINDOW]: the status line recorded TOKENS of context, and
# the context window when given.
record() {
  mkdir -p "$HOME/.cache/claude/context-size"
  printf '%s\n' "$@" >"$HOME/.cache/claude/context-size/s1"
}

@test "a recorded 200k window caps the threshold below native compaction" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  record 139000 200000
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  record 141000 200000
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"141000 tokens (renewal threshold 140000); hand off for renewal"* ]]
}

@test "a recorded 1M window leaves the setting in charge" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  record 174999 1000000
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  record 175000 1000000
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"(renewal threshold 175000); hand off"* ]]
}

@test "an unknown window leaves the setting in charge" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  # An old one-line record, and one with the window left empty.
  record 174999
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  record 174999 ""
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"next action: implement TASK-1"* ]]
  record 175000
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"(renewal threshold 175000); hand off"* ]]
}

@test "a lower setting wins over the window-derived cap" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  record 100000 200000
  CLAUDE_RENEWAL_TOKENS=100000 stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"(renewal threshold 100000); hand off"* ]]
}

@test "a missing or malformed context-size record falls back to the transcript" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 210000
  mkdir -p "$HOME/.cache/claude/context-size"
  echo 'not a number' >"$HOME/.cache/claude/context-size/s1"
  stop "$A"
  [[ "$(jq -r '.reason' <<<"$output")" == *"Context holds 210000 tokens"* ]]

  rm "$HOME/.cache/claude/context-size/s1"
  stop "$A" true
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"paused"* ]]
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"at 210000 tokens"* ]]
}

@test "a handoff request that yields no current handoff pauses for the user" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 210000
  stop "$A"
  blocked
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context renewal paused"* ]]
  [ -z "$(renewal_request "$A")" ]
  # The user's next turn stays paused rather than asking again.
  stop "$A"
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context renewal paused"* ]]
}

@test "a renewal pause holds until a handoff is current or context drops below the threshold" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 210000
  stop "$A"
  stop "$A" true
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context renewal paused"* ]]
  for active in false true false; do
    stop "$A" "$active"
    allowed
    [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context renewal paused"* ]]
  done

  link_handoff "$A"
  stop "$A"
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Renew by hand"* ]]
  work-record --cwd "$A" record '.next_action = "implement TASK-2"' >/dev/null
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"mojo-handoff"* ]]

  stop "$A" true
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Context renewal paused"* ]]
  context 1000
  stop "$A" false '[{"id": "a1", "type": "subagent", "status": "running", "agent_type": "general-purpose"}]'
  allowed
  [ -z "$output" ]
  context 210000
  stop "$A"
  blocked
  [[ "$(jq -r '.reason' <<<"$output")" == *"mojo-handoff"* ]]
}

@test "a current handoff in a Herdr pane requests renewal instead of a continuation" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 180000
  link_handoff "$A"
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true
  allowed
  # Said once, in case no helper runs to act on the request.
  [[ "$(jq -r '.systemMessage' <<<"$output")" == "Context renewal requested"*"If nothing happens, renew by hand: /compact, then /mojo-resume." ]]
  [ "$(renewal_request "$A")" = "$(expected_request "$A")" ]
}

@test "a record unreadable for a renewal request is reported and the stop allowed" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  link_handoff "$A"
  fail_work_record read
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"\`work-record read\` exited 5: work-record: simulated read failure" ]]
  [ -z "$(renewal_request "$A")" ]
}

@test "a renewal in flight is not requested again" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  link_handoff "$A"
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A"
  state="$(dirname "$(work-record --cwd "$A" path)")/renewal"
  jq '.state = "compacted"' "$state" >"$SCRATCH/compacted" && mv "$SCRATCH/compacted" "$state"
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true
  allowed
  [ "$(jq -r .state "$state")" = compacted ]
}

@test "outside Herdr a current handoff tells the user to renew by hand" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 180000
  link_handoff "$A"
  stop "$A"
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"Renew by hand: /compact, then /mojo-resume"* ]]
  [ -z "$(renewal_request "$A")" ]
}

@test "a human gate is never renewed through or asked for a handoff" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1" | .human_gate = "design approval"' >/dev/null
  context 190000
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A"
  allowed
  [ -z "$output" ]
  [ -z "$(renewal_request "$A")" ]
}

@test "a human gate set after a handoff is never renewed through" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  work-record --cwd "$A" record '.human_gate = "design approval"' >/dev/null
  link_handoff "$A"
  [ "$(work-record --cwd "$A" handoff)" = current ]
  context 190000
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true
  allowed
  [ -z "$output" ]
  [ -z "$(renewal_request "$A")" ]
}

@test "renewal proceeds while a background worker runs, without re-dispatching it" {
  worker='[{"id": "a7f3", "type": "subagent", "status": "running", "description": "review TASK-1", "agent_type": "general-purpose"}]'
  work-record --cwd "$A" init '.next_action = "reconcile TASK-1 review round 0"' >/dev/null
  context 210000
  stop "$A" false "$worker"
  blocked
  reason=$(jq -r '.reason' <<<"$output")
  [[ "$reason" == *"naming every background worker still running"* ]]
  [[ "$reason" == *"Do not wait for running background workers first"* ]]
  [[ "$reason" != *"next action"* ]]

  link_handoff "$A"
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" true "$worker"
  allowed
  [ "$(renewal_request "$A")" = "$(expected_request "$A")" ]
}

@test "a stop during an in-flight renewal issues no continuation" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  context 180000
  link_handoff "$A"
  HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" false
  allowed
  [[ "$(jq -r '.systemMessage' <<<"$output")" == "Context renewal requested"* ]]
  for active in true true true; do
    HERDR_ENV=1 HERDR_PANE_ID=w9:p9 stop "$A" "$active"
    allowed
    [ -z "$output" ]
  done
}
