#!/usr/bin/env bats
# The packaged status line must record the context size whatever PATH Claude
# Code launches it with. Runs against the build output, as the package's
# install check does.

setup() {
  [[ -n "${CONTEXT_STATUS_BIN:-}" ]] || skip "needs CONTEXT_STATUS_BIN, the packaged context-status"
  export HOME="$BATS_TEST_TMPDIR/home"
}

@test "jq and coreutils are found without the caller's PATH" {
  run env PATH="$(dirname "$BASH")" "$CONTEXT_STATUS_BIN" \
    <<<'{"session_id": "s1", "context_window": {"context_window_size": 200000, "current_usage": {"input_tokens": 100000}}}'
  [ "$status" -eq 0 ]
  [ "$output" = "ctx 100k/200k (50%)" ]
  [ "$(cat "$HOME/.cache/claude/context-size/s1")" = "$(printf '100000\n200000')" ]
}
