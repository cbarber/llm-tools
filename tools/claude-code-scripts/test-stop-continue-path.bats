#!/usr/bin/env bats
# The packaged hook must consult the work record whatever PATH Claude Code
# launches it with. Runs against the build output, as the package's install
# check does.

setup() {
  [[ -n "${STOP_CONTINUE_BIN:-}" ]] || skip "needs STOP_CONTINUE_BIN, the packaged stop-continue"
  export WORK_RECORD_HOME="$BATS_TEST_TMPDIR/store"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  A="$BATS_TEST_TMPDIR/a"
  mkdir -p "$A"
  git -C "$A" init -q -b main
  git -C "$A" commit -q --allow-empty -m root
  work-record --cwd "$A" init '.next_action = "implement TASK-1"' >/dev/null
}

@test "work-record and git are found without the caller's PATH" {
  run env PATH="$(dirname "$BASH")" "$STOP_CONTINUE_BIN" <<<"{\"cwd\": \"$A\"}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision": "block"'* ]]
  [[ "$output" == *"implement TASK-1"* ]]
}
