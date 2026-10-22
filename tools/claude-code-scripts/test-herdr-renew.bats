#!/usr/bin/env bats
# jq filters are single-quoted on purpose.
# shellcheck disable=SC2016

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
RENEW="$HERE/herdr-renew"

setup() {
  SCRATCH="$BATS_TEST_TMPDIR"
  export WORK_RECORD_HOME="$SCRATCH/store"
  mkdir -p "$SCRATCH/bin"
  ln -s "$HERE/../work-record" "$SCRATCH/bin/work-record"
  ln -s "$HERE/compact-resume" "$SCRATCH/bin/compact-resume"
  stub_herdr
  # Never reach a real Herdr session: the stub is first on PATH and the
  # pane is fictional.
  unset HERDR_ENV HERDR_SOCKET_PATH HERDR_WORKSPACE_ID HERDR_TAB_ID
  export HERDR_PANE_ID="w9:p9"
  export PATH="$SCRATCH/bin:$PATH"
  export HERDR_LOG="$SCRATCH/herdr.log" STUB_STATUS=idle STUB_COMPACTS=1 STUB_PROMPT_EXIT=0 STUB_ON_COMPACT="" STUB_SESSION=s1
  export RENEW_SETTLE_SECONDS=0 RENEW_COMPACT_TIMEOUT_SECONDS=1 RENEW_POLL_SECONDS=0.1 RENEW_LOG="$SCRATCH/renewal.log"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  A=$(make_repo a)
  touch "$HERDR_LOG"
}

teardown() {
  stop_helper
}

make_repo() {
  local path="$SCRATCH/$1"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" commit -q --allow-empty -m root
  (cd "$path" && pwd -P)
}

# Logs each call. /compact optionally behaves like Claude: compacting runs
# the SessionStart compact hook; otherwise the keys are merely acknowledged.
stub_herdr() {
  cat >"$SCRATCH/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$HERDR_LOG"
status() { jq -n --arg s "$1" '{result: {agent: {agent_status: $s}}}'; }
case "$1 $2" in
"agent wait" | "agent get") status "$STUB_STATUS" ;;
"agent prompt")
  [[ "$STUB_PROMPT_EXIT" == 0 ]] || exit "$STUB_PROMPT_EXIT"
  if [[ "$4" == /compact ]]; then
    [[ -z "$STUB_ON_COMPACT" ]] || eval "$STUB_ON_COMPACT"
    if [[ "$STUB_COMPACTS" == 1 ]]; then
      jq -n --arg cwd "$STUB_CWD" --arg s "$STUB_SESSION" '{hook_event_name: "SessionStart", source: "compact", session_id: $s, cwd: $cwd}' |
        compact-resume >"$HERDR_LOG.context"
    fi
    status idle
  else
    status working
  fi
  ;;
esac
EOF
  chmod +x "$SCRATCH/bin/herdr"
}

link_handoff() {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  echo "Next: implement TASK-1" >"$SCRATCH/handoff.md"
  work-record --cwd "$A" handoff "$SCRATCH/handoff.md" >/dev/null
  export STUB_CWD="$A"
}

state_file() {
  echo "$(dirname "$(work-record --cwd "$A" path)")/renewal"
}

fingerprint() {
  work-record --cwd "$A" read | jq -r '.artifacts.handoff.record'
}

# request [STATE [PANE [HANDOFF]]]: what stop-continue writes in the sandbox.
request() {
  mkdir -p "$(dirname "$(state_file)")"
  jq -n --arg h "${3:-$(fingerprint)}" --arg p "${2:-w9:p9}" --arg s "${1:-requested}" \
    '{handoff: $h, session_id: "s1", pane: $p, state: $s}' >"$(state_file)"
}

start_helper() {
  sleep 60 &
  WATCHED=$!
  "$RENEW" --watch "$WATCHED" --herdr "$SCRATCH/bin/herdr" --cwd "$A" &
  HELPER=$!
}

stop_helper() {
  [[ -z "${WATCHED:-}" ]] || kill "$WATCHED" 2>/dev/null || true
  [[ -z "${HELPER:-}" ]] || wait "$HELPER" 2>/dev/null || true
  WATCHED="" HELPER=""
}

# Waits for the helper to log a line matching PATTERN.
logged() {
  for _ in $(seq 50); do
    grep -q -- "$1" "$RENEW_LOG" 2>/dev/null && return 0
    sleep 0.1
  done
  echo "not logged: $1" >&2
  cat "$RENEW_LOG" >&2 || true
  return 1
}

prompts() {
  grep '^agent prompt' "$HERDR_LOG" || true
}

notification() {
  grep '^notification show' "$HERDR_LOG" || true
}

# Waits until COUNT pause notifications reached Herdr.
notified() {
  for _ in $(seq 50); do
    [ "$(grep -c '^notification show' "$HERDR_LOG")" -ge "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "a confirmed compaction is followed by the resume entry in the same pane" {
  link_handoff
  start_helper
  request
  logged "resumed handoff"
  [ "$(prompts)" = "$(printf '%s\n' 'agent prompt w9:p9 /compact' 'agent prompt w9:p9 /mojo-resume --wait --until working --timeout 30000')" ]
  # The turn settled before /compact was typed.
  [ "$(head -n 2 "$HERDR_LOG" | cut -d' ' -f1-2 | tr '\n' ' ')" = "agent wait agent get " ]
  [[ "$(cat "$HERDR_LOG.context")" == *"do not invoke mojo-resume a second time"* ]]
  [ "$(jq -r .state "$(state_file)")" = compacted ]
}

@test "acknowledged /compact input without a compaction pauses before the resume entry" {
  link_handoff
  before=$(work-record --cwd "$A" read)
  export STUB_COMPACTS=0
  start_helper
  request
  logged "paused: no compaction observed"
  [ "$(prompts)" = 'agent prompt w9:p9 /compact' ]
  [[ "$(notification)" == *"Context renewal paused"*"renew by hand (/compact, then /mojo-resume)"* ]]
  # Compaction may outlast the wait.
  [[ "$(notification)" == *"submit /mojo-resume once it finishes"* ]]
  [ "$(work-record --cwd "$A" read)" = "$before" ]
  [ "$(work-record --cwd "$A" handoff)" = current ]
}

@test "another session's compaction is not counted" {
  link_handoff
  export STUB_SESSION=s2
  start_helper
  request
  logged "paused: no compaction observed"
  [ "$(prompts)" = 'agent prompt w9:p9 /compact' ]
}

@test "undelivered /compact pauses" {
  link_handoff
  export STUB_PROMPT_EXIT=1
  start_helper
  request
  logged "paused: /compact was not delivered"
}

@test "a busy or blocked agent is never typed into" {
  link_handoff
  for busy in working blocked unknown; do
    stop_helper
    : >"$HERDR_LOG"
    work-record --cwd "$A" record . >/dev/null
    work-record --cwd "$A" handoff "$SCRATCH/handoff.md" >/dev/null
    export STUB_STATUS=$busy
    start_helper
    request
    logged "agent is $busy, not idle"
    [ -z "$(prompts)" ]
  done
}

@test "without a current handoff nothing is sent" {
  link_handoff
  work-record --cwd "$A" record . >/dev/null
  start_helper
  request
  sleep 0.5
  [ ! -s "$HERDR_LOG" ]
}

@test "a handoff is renewed at most once, even after a paused attempt" {
  link_handoff
  export STUB_COMPACTS=0
  start_helper
  request
  logged "paused"
  notified 1
  : >"$HERDR_LOG"
  request
  sleep 0.5
  [ ! -s "$HERDR_LOG" ]
}

@test "every handoff attempted is remembered, not only the last" {
  link_handoff
  export STUB_COMPACTS=0
  record="$(work-record --cwd "$A" path)"
  cp "$record" "$SCRATCH/record-a"
  start_helper
  request
  logged "paused"
  notified 1
  work-record --cwd "$A" record . >/dev/null
  work-record --cwd "$A" handoff "$SCRATCH/handoff.md" >/dev/null
  request
  for _ in $(seq 50); do
    [ "$(grep -c paused "$RENEW_LOG")" -ge 2 ] && break
    sleep 0.1
  done
  notified 2
  # The first handoff becomes current again.
  cp "$SCRATCH/record-a" "$record"
  : >"$HERDR_LOG"
  request
  sleep 0.5
  [ ! -s "$HERDR_LOG" ]
}

@test "a request left before the helper started is not acted on" {
  link_handoff
  request
  start_helper
  logged "watching"
  sleep 0.5
  [ ! -s "$HERDR_LOG" ]
}

@test "requests for another pane or with a malformed handoff are ignored" {
  link_handoff
  start_helper
  request requested w1:p1
  sleep 0.3
  request requested w9:p9 "\$(touch $SCRATCH/pwned)"
  sleep 0.3
  echo 'not json' >"$(state_file)"
  sleep 0.3
  [ ! -s "$HERDR_LOG" ]
  [ ! -e "$SCRATCH/pwned" ]
  # Still watching: this pane's own request is served.
  request
  logged "resumed handoff"
}

@test "a compaction the helper did not submit /compact for does not skip it" {
  link_handoff
  start_helper
  request compacted
  logged "resumed handoff"
  [ "$(prompts)" = "$(printf '%s\n' 'agent prompt w9:p9 /compact' 'agent prompt w9:p9 /mojo-resume --wait --until working --timeout 30000')" ]
}

@test "a confirmation forged before /compact is not counted" {
  link_handoff
  export STUB_COMPACTS=0
  start_helper
  # The agent writes compacted, with a guessed attempt, without compacting.
  request compacted
  jq '.attempt = "0123"' "$(state_file)" >"$SCRATCH/forged"
  cp "$SCRATCH/forged" "$(state_file)"
  logged "paused: no compaction observed"
  [ "$(prompts)" = 'agent prompt w9:p9 /compact' ]
}

@test "a record directory swapped for a symlink is never written through" {
  link_handoff
  start_helper
  logged "watching"
  dir=$(dirname "$(state_file)")
  mv "$dir" "$SCRATCH/elsewhere"
  ln -s "$SCRATCH/elsewhere" "$dir"
  request
  before=$(cat "$SCRATCH/elsewhere/renewal")
  logged "paused: the renewal request could not be armed"
  [ -z "$(prompts)" ]
  [ "$(cat "$SCRATCH/elsewhere/renewal")" = "$before" ]
  [ "$(find "$SCRATCH/elsewhere" -name 'renewal.*')" = "" ]
}

@test "a request that is a symlink is replaced, neither written through nor copied" {
  link_handoff
  export STUB_COMPACTS=0
  start_helper
  logged "watching"
  jq -n --arg h "$(fingerprint)" \
    '{handoff: $h, session_id: "s1", pane: "w9:p9", state: "requested", secret: "outside"}' >"$SCRATCH/outside.json"
  before=$(cat "$SCRATCH/outside.json")
  ln -s "$SCRATCH/outside.json" "$(state_file)"
  logged "paused"
  [ "$(cat "$SCRATCH/outside.json")" = "$before" ]
  [ ! -L "$(state_file)" ]
  [ "$(jq -r '[.state, (.attempt | length), (keys | join(","))] | join(" ")' "$(state_file)")" = "requested 32 attempt,handoff,pane,session_id,state" ]
}

@test "a record write after compaction pauses without advising another /compact" {
  link_handoff
  export STUB_ON_COMPACT='work-record --cwd "$STUB_CWD" record . >/dev/null'
  start_helper
  request
  logged "paused: the handoff changed after compaction"
  [ "$(prompts)" = 'agent prompt w9:p9 /compact' ]
  [[ "$(notification)" != *"/compact"* ]]
}

@test "a resume entry that starts no turn pauses without advising another /compact" {
  link_handoff
  sed -i 's/status working/status idle/' "$SCRATCH/bin/herdr"
  start_helper
  request
  logged "paused: /mojo-resume did not start a turn"
  [[ "$(notification)" == *"Context was compacted; submit /mojo-resume by hand"* ]]
  [[ "$(notification)" != *"/compact,"* ]]
}

@test "the helper exits with the process it watches" {
  start_helper
  logged "watching"
  kill "$WATCHED"
  wait "$HELPER"
  WATCHED="" HELPER=""
  logged "exited"
}

@test "outside a Herdr pane the helper exits without calling Herdr" {
  HERDR_PANE_ID="" run "$RENEW" --watch "$$" --cwd "$A"
  [ "$status" -eq 0 ]
  [ ! -s "$HERDR_LOG" ]
}

@test "a stalled read of the request does not outlive the watched process" {
  link_handoff
  # A FIFO swapped in after the regular-file check blocks the reader.
  mkdir -p "$SCRATCH/stall"
  printf '#!/usr/bin/env bash\n[[ "${*: -1}" != */renewal ]] || exec sleep 1000\nexec %s "$@"\n' "$(type -P jq)" >"$SCRATCH/stall/jq"
  chmod +x "$SCRATCH/stall/jq"
  export RENEW_READ_TIMEOUT_SECONDS=1
  request
  PATH="$SCRATCH/stall:$PATH" start_helper
  logged "watching"
  kill "$WATCHED"
  for _ in $(seq 50); do
    kill -0 "$HELPER" 2>/dev/null || break
    sleep 0.1
  done
  run kill -0 "$HELPER"
  [ "$status" -ne 0 ]
  wait "$HELPER"
  WATCHED="" HELPER=""
  logged "exited"
}

@test "herdr is run only by the path given, never from PATH" {
  link_handoff
  mkdir -p "$SCRATCH/planted"
  printf '#!/bin/sh\ntouch %s/pwned\n' "$SCRATCH" >"$SCRATCH/planted/herdr"
  chmod +x "$SCRATCH/planted/herdr"
  PATH="$SCRATCH/planted:$PATH" start_helper
  request
  logged "resumed handoff"
  [ ! -e "$SCRATCH/pwned" ]
}

# Stands in for root in an unprivileged test: the owners of every directory
# from / down to each PATH given.
trust_owners_of() {
  local p
  for p in "$@"; do
    while :; do
      echo "--trust-uid $(stat -c %u -- "$p")"
      [[ "$p" != / ]] || break
      p=$(dirname -- "$p")
    done
  done
}

store_bash() {
  STORE_BASH=$(readlink -f "$BASH")
  [[ "$STORE_BASH" == /nix/store/* ]] || skip "bash is not in the Nix store"
}

@test "a store bash posing as herdr where the sandbox writes is refused" {
  store_bash
  ln -s "$STORE_BASH" "$SCRATCH/herdr-link"
  run "$RENEW" --resolve-herdr "$SCRATCH/herdr-link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is owned by uid"*"not root"* ]]
  [[ "$output" == *"context renewal is off"* ]]
}

@test "a herdr reached through a root-owned chain resolves to its file" {
  store_bash
  mkdir -p "$SCRATCH/sys/bin"
  chmod 755 "$SCRATCH" "$SCRATCH/sys" "$SCRATCH/sys/bin"
  ln -s "$STORE_BASH" "$SCRATCH/sys/bin/herdr"
  ln -s sys "$SCRATCH/current"
  # shellcheck disable=SC2046 # one word per flag
  run "$RENEW" --resolve-herdr "$SCRATCH/current/./bin/../bin/herdr" $(trust_owners_of "$SCRATCH" "$STORE_BASH")
  [ "$status" -eq 0 ]
  [ "$output" = "$STORE_BASH" ]
}

@test "a symlink in a directory others may write is refused" {
  store_bash
  mkdir -p "$SCRATCH/open"
  chmod 755 "$SCRATCH"
  ln -s "$STORE_BASH" "$SCRATCH/open/herdr"
  for mode in 775 757; do
    chmod "$mode" "$SCRATCH/open"
    # shellcheck disable=SC2046
    run "$RENEW" --resolve-herdr "$SCRATCH/open/herdr" $(trust_owners_of "$SCRATCH" "$STORE_BASH")
    [ "$status" -eq 1 ]
    [[ "$output" == *"$SCRATCH/open is writable by others"* ]]
  done
}

@test "a symlink to a file others may write is refused" {
  mkdir -p "$SCRATCH/sys"
  chmod 755 "$SCRATCH" "$SCRATCH/sys"
  cp "$SCRATCH/bin/herdr" "$SCRATCH/sys/herdr"
  chmod 777 "$SCRATCH/sys/herdr"
  # shellcheck disable=SC2046
  run "$RENEW" --resolve-herdr "$SCRATCH/sys/herdr" $(trust_owners_of "$SCRATCH")
  [ "$status" -eq 1 ]
  [[ "$output" == *"$SCRATCH/sys/herdr is writable by others"* ]]
}

@test "the system profile's herdr resolves through its chain" {
  herdr=/run/current-system/sw/bin/herdr
  [[ -e "$herdr" ]] || skip "no system herdr"
  # shellcheck disable=SC2046
  run "$RENEW" --resolve-herdr "$herdr" $(trust_owners_of /run/current-system "$(readlink -f "$herdr")")
  [ "$status" -eq 0 ]
  [ "$output" = "$(readlink -f "$herdr")" ]
}

@test "a relative or missing herdr is refused" {
  run "$RENEW" --resolve-herdr herdr
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an absolute path"* ]]
  # shellcheck disable=SC2046
  run "$RENEW" --resolve-herdr "$SCRATCH/absent" $(trust_owners_of "$SCRATCH")
  [ "$status" -eq 1 ]
  [[ "$output" == *"$SCRATCH/absent does not exist"* ]]
}

@test "the log is trimmed" {
  seq 1500 >"$RENEW_LOG"
  start_helper
  logged "watching"
  [ "$(wc -l <"$RENEW_LOG")" -le 501 ]
  [ "$(head -n 1 "$RENEW_LOG")" = 1001 ]
}
