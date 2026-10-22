#!/usr/bin/env bats
# How the Claude Code shell starts the context-renewal helper outside the
# sandbox. The helper is a stub that records how it was called.

HERE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

setup() {
  SCRATCH="$BATS_TEST_TMPDIR"
  mkdir -p "$SCRATCH/tools" "$SCRATCH/planted" "$SCRATCH/home"
  touch "$SCRATCH/tools/setup-shared-aliases.sh" "$SCRATCH/tools/setup-shared-shell.sh"
  printf '#!/bin/sh\ntouch %s/pwned\n' "$SCRATCH" >"$SCRATCH/planted/herdr"
  cat >"$SCRATCH/helper" <<STUB
#!$BASH
echo "\$PWD \$*" >>"$SCRATCH/helper.log"
[[ "\$1" != --resolve-herdr ]] && exit 0
[[ -z "\${REFUSE:-}" ]] || exit 1
echo "\$2.checked"
STUB
  chmod +x "$SCRATCH/planted/herdr" "$SCRATCH/helper"
  unset IN_AGENT_SANDBOX HERDR_RENEW_HERDR HERDR_ENV HERDR_WORKSPACE_ID HERDR_TAB_ID
  export HOME="$SCRATCH/home" TOOLS_DIR="$SCRATCH/tools" ANTHROPIC_API_KEY=test
  export AGENT_SANDBOX_SCRIPT="$SCRATCH/helper" SETUP_SETTINGS_SCRIPT=true AUTO_LAUNCH=false
  export HERDR_RENEW_PATH="$SCRATCH/helper" HERDR_SOCKET_PATH="$SCRATCH/herdr.sock" HERDR_PANE_ID="w9:p9"
  export PATH="$SCRATCH/planted:$PATH"
  # shellcheck source=/dev/null
  source "$HERE/setup-shell.sh" >/dev/null
  mkdir -p "$SCRATCH/checkout"
  cd "$SCRATCH/checkout" || return
}

# Waits for the detached helper to record its --watch call.
started() {
  for _ in $(seq 50); do
    grep -q -- "--watch" "$SCRATCH/helper.log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

@test "herdr comes from the system profile, never from PATH" {
  start-renewal-helper 4242
  started
  grep -qx -- ".* --resolve-herdr /run/current-system/sw/bin/herdr" "$SCRATCH/helper.log"
  grep -q -- "--watch 4242 --herdr /run/current-system/sw/bin/herdr.checked " "$SCRATCH/helper.log"
  [ ! -e "$SCRATCH/pwned" ]
}

@test "the launching shell may name another herdr, under the same check" {
  HERDR_RENEW_HERDR=/opt/herdr start-renewal-helper 4242
  started
  grep -qx -- ".* --resolve-herdr /opt/herdr" "$SCRATCH/helper.log"
  grep -q -- "--herdr /opt/herdr.checked " "$SCRATCH/helper.log"
}

@test "the helper runs from / and is told the checkout" {
  start-renewal-helper 4242
  started
  grep -qx -- "/ --resolve-herdr .*" "$SCRATCH/helper.log"
  grep -qx -- "/ --watch 4242 --herdr .* --cwd $SCRATCH/checkout" "$SCRATCH/helper.log"
}

@test "a refused herdr starts no helper" {
  REFUSE=1 start-renewal-helper 4242
  sleep 0.5
  run grep -c -- "--watch" "$SCRATCH/helper.log"
  [ "$output" = 0 ]
}

@test "sandboxed-claude runs the sandbox script, never a PATH lookup" {
  printf '#!/bin/sh\ntouch %s/pwned\n' "$SCRATCH" >"$SCRATCH/planted/agent-sandbox"
  chmod +x "$SCRATCH/planted/agent-sandbox"
  run sandboxed-claude --x
  [ "$status" = 0 ]
  grep -qx -- "$SCRATCH/checkout claude --x" "$SCRATCH/helper.log"
  [ ! -e "$SCRATCH/pwned" ]
}
