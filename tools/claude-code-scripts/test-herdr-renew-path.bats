#!/usr/bin/env bats
# The packaged helper runs outside the sandbox with a launching PATH that
# holds sandbox-writable directories. Runs against the build output, as the
# package's install check does.

setup() {
  [[ -n "${HERDR_RENEW_BIN:-}" ]] || skip "needs HERDR_RENEW_BIN, the packaged herdr-renew"
  SCRATCH="$BATS_TEST_TMPDIR"
  export WORK_RECORD_HOME="$SCRATCH/store" HERDR_PANE_ID="w9:p9" RENEW_LOG="$SCRATCH/renewal.log"
  export RENEW_SETTLE_SECONDS=0 RENEW_COMPACT_TIMEOUT_SECONDS=1 RENEW_POLL_SECONDS=0.1
  unset HERDR_ENV HERDR_SOCKET_PATH HERDR_WORKSPACE_ID HERDR_TAB_ID
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  A="$SCRATCH/a"
  mkdir -p "$A" "$SCRATCH/planted" "$SCRATCH/bin"
  git -C "$A" init -q -b main
  git -C "$A" commit -q --allow-empty -m root
  # Answers as an idle pane without using anything from PATH.
  cat >"$SCRATCH/bin/herdr" <<STUB
#!$BASH
echo "\$*" >>"$SCRATCH/herdr.log"
echo '{"result":{"agent":{"agent_status":"idle"}}}'
STUB
  chmod +x "$SCRATCH/bin/herdr"
  for tool in herdr git jq work-record bash sh sleep date dirname mkdir timeout mktemp mv od readlink stat; do
    printf '#!/bin/sh\ntouch %s/ran-%s\nexit 1\n' "$SCRATCH" "$tool" >"$SCRATCH/planted/$tool"
    chmod +x "$SCRATCH/planted/$tool"
  done
}

wait_for() {
  for _ in $(seq 50); do
    grep -q -- "$1" "$RENEW_LOG" 2>/dev/null && return 0
    sleep 0.1
  done
}

@test "nothing planted earlier on the caller's PATH is executed" {
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
  echo "Next: implement TASK-1" >"$SCRATCH/handoff.md"
  work-record --cwd "$A" handoff "$SCRATCH/handoff.md" >/dev/null
  sleep 60 &
  watched=$!
  PATH="$SCRATCH/planted:$PATH" "$HERDR_RENEW_BIN" --watch "$watched" --herdr "$SCRATCH/bin/herdr" --cwd "$A" &
  helper=$!
  wait_for watching
  state="$(dirname "$(work-record --cwd "$A" path)")/renewal"
  jq -n --arg h "$(work-record --cwd "$A" read | jq -r .artifacts.handoff.record)" \
    '{handoff: $h, session_id: "s1", pane: "w9:p9", state: "requested"}' >"$state"
  wait_for paused
  kill "$watched"
  wait "$helper" || true
  cat "$RENEW_LOG"
  grep -q "paused: no compaction observed" "$RENEW_LOG"
  grep -q "^agent prompt w9:p9 /compact" "$SCRATCH/herdr.log"
  run ls "$SCRATCH"
  [[ "$output" != *ran-* ]]
}

@test "checking a herdr executes nothing from the caller's PATH" {
  ln -s "$SCRATCH/bin/herdr" "$SCRATCH/herdr-link"
  PATH="$SCRATCH/planted:$PATH" run "$HERDR_RENEW_BIN" --resolve-herdr "$SCRATCH/herdr-link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not root"* ]]
  run ls "$SCRATCH"
  [[ "$output" != *ran-* ]]
}
