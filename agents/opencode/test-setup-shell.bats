#!/usr/bin/env bats
# What the OpenCode shell hands the sandbox in a Herdr pane. agent-sandbox is a
# stub that records the environment it was called with.

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

setup() {
  SCRATCH="$BATS_TEST_TMPDIR"
  mkdir -p "$SCRATCH/tools" "$SCRATCH/home"
  touch "$SCRATCH/tools/setup-shared-aliases.sh" "$SCRATCH/tools/setup-shared-shell.sh"
  printf '#!/bin/sh\n' >"$SCRATCH/sandbox" && chmod +x "$SCRATCH/sandbox"
  unset IN_AGENT_SANDBOX
  export HOME="$SCRATCH/home" TOOLS_DIR="$SCRATCH/tools" ANTHROPIC_API_KEY=test
  export AGENT_SANDBOX_SCRIPT="$SCRATCH/sandbox" SETUP_CONFIG_SCRIPT=true AUTO_LAUNCH=false
  export PR_POLL_DAEMON=false OPENCODE_PORT=45678
  export HERDR_SOCKET_PATH="$SCRATCH/herdr.sock" HERDR_PANE_ID="w9:p9" HERDR_ENV=1
  # shellcheck source=/dev/null
  source "$HERE/setup-shell.sh" >/dev/null
  agent-sandbox() {
    printf 'EXTRA_RO=%s\nAGENT=%s\nARGS=%s\n' "${SANDBOX_EXTRA_RO:-}" "${HERDR_AGENT:-}" "$*" >"$SCRATCH/launch"
  }
}

@test "the sandbox never gets the Herdr socket" {
  SANDBOX_EXTRA_RO=/opt/ro sandboxed-opencode
  grep -qx "EXTRA_RO=/opt/ro" "$SCRATCH/launch"
  ! grep -q "herdr.sock" "$SCRATCH/launch"
}

@test "Herdr still recognizes the sandboxed process as OpenCode" {
  sandboxed-opencode
  grep -qx "AGENT=opencode" "$SCRATCH/launch"
  grep -qx "ARGS=opencode --port 45678 --dangerously-skip-permissions" "$SCRATCH/launch"
}
