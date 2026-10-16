#!/usr/bin/env bats

SETUP_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/setup-settings.sh"
REAL_TEMPLATE="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/settings.template.json"

setup() {
  TEST_REPO=$(mktemp -d)
  # Merge cases describe changes relative to a template whose only Stop hook
  # is notify, whatever else the real template gains.
  REPO_TEMPLATE="$TEST_REPO/repo-template.json"
  jq '.hooks.Stop |= map(.hooks |= map(select(.command == "notify")))' \
    "$REAL_TEMPLATE" >"$REPO_TEMPLATE"
  TEMPLATE="$TEST_REPO/template.json"
  SETTINGS="$TEST_REPO/.claude/settings.local.json"
  cp "$REPO_TEMPLATE" "$TEMPLATE"
}

teardown() {
  chmod -R u+w "$TEST_REPO"
  rm -rf "$TEST_REPO"
}

run_setup() {
  run bash -c 'cd "$1" && SETTINGS_TEMPLATE="$2" "$3"' _ "$TEST_REPO" "$TEMPLATE" "$SETUP_SCRIPT"
}

# Simulates a later template revision adding a Stop hook beside notify.
add_template_stop_hook() {
  jq '.hooks.Stop[0].hooks += [{"type": "command", "command": "continue"}]' \
    "$REPO_TEMPLATE" >"$TEMPLATE"
}

@test "absent settings are created from the template" {
  run_setup
  [ "$status" -eq 0 ]
  cmp "$TEMPLATE" "$SETTINGS"
}

@test "a new template hook reaches existing settings" {
  run_setup
  chmod 444 "$SETTINGS"
  add_template_stop_hook

  run_setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated"* ]]
  run jq -c '[.hooks.Stop[].hooks[].command]' "$SETTINGS"
  [ "$output" = '["notify","continue"]' ]
  run jq -c '.hooks.Stop | length' "$SETTINGS"
  [ "$output" = "1" ]
}

@test "a new template hook event reaches existing settings" {
  run_setup
  jq '.hooks.SessionStart = [{"matcher": "", "hooks": [{"type": "command", "command": "start"}]}]' \
    "$REPO_TEMPLATE" >"$TEMPLATE"

  run_setup
  run jq -r '.hooks.SessionStart[0].hooks[0].command' "$SETTINGS"
  [ "$output" = "start" ]
}

@test "local edits survive the merge" {
  mkdir -p "$TEST_REPO/.claude"
  jq '.env.BASH_DEFAULT_TIMEOUT_MS = "1000"
      | .env.MINE = "1"
      | .model = "opus"
      | .hooks.Stop[0].hooks += [{"type": "command", "command": "mine"}]
      | .hooks.PreToolUse = [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard"}]}]' \
    "$REPO_TEMPLATE" >"$SETTINGS"
  add_template_stop_hook

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.env.BASH_DEFAULT_TIMEOUT_MS, .env.MINE, .env.BASH_MAX_TIMEOUT_MS, .model]' "$SETTINGS"
  [ "$output" = '["1000","1","600000","opus"]' ]
  run jq -c '[.hooks.Stop[].hooks[].command]' "$SETTINGS"
  [ "$output" = '["notify","mine","continue"]' ]
  run jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS"
  [ "$output" = "guard" ]
}

@test "repeated runs are idempotent and keep the file mode" {
  run_setup
  chmod 444 "$SETTINGS"
  add_template_stop_hook
  run_setup
  cp "$SETTINGS" "$TEST_REPO/after-first"

  run_setup
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run_setup
  [ -z "$output" ]
  cmp "$TEST_REPO/after-first" "$SETTINGS"
  [ ! -w "$SETTINGS" ]
  [ -z "$(find "$TEST_REPO/.claude" -name 'settings.local.json.*')" ]
}

@test "invalid local JSON is left untouched with a warning" {
  mkdir -p "$TEST_REPO/.claude"
  printf '{ not json' >"$SETTINGS"

  run_setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"not valid JSON"* ]]
  [ "$(cat "$SETTINGS")" = "{ not json" ]
}

@test "an unwritable settings directory is left untouched with a warning" {
  run_setup
  add_template_stop_hook
  cp "$SETTINGS" "$TEST_REPO/before"
  chmod 555 "$TEST_REPO/.claude"

  run_setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"not writable"* ]]
  cmp "$TEST_REPO/before" "$SETTINGS"
}

@test "an edited template hook replaces rather than duplicates" {
  run_setup
  jq '.hooks.Stop[0].hooks[0].timeout = 5' "$REPO_TEMPLATE" >"$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '.hooks.Stop[0].hooks' "$SETTINGS"
  [ "$output" = '[{"type":"command","command":"notify","timeout":5}]' ]
}

@test "a template scalar change reaches an unedited value" {
  run_setup
  jq '.env.BASH_DEFAULT_TIMEOUT_MS = "1000"' "$REPO_TEMPLATE" >"$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -r '.env.BASH_DEFAULT_TIMEOUT_MS' "$SETTINGS"
  [ "$output" = "1000" ]
}

@test "a local deletion of a template hook survives" {
  run_setup
  jq '.hooks.Stop = []' "$TEMPLATE" >"$TEST_REPO/local"
  cp -f "$TEST_REPO/local" "$SETTINGS"
  jq '.env.BASH_DEFAULT_TIMEOUT_MS = "1000"' "$REPO_TEMPLATE" >"$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.env.BASH_DEFAULT_TIMEOUT_MS, .hooks.Stop]' "$SETTINGS"
  [ "$output" = '["1000",[]]' ]
}

@test "a template hook joins a group whose local hook was deleted" {
  run_setup
  jq '.hooks.Stop[0].hooks = []' "$TEMPLATE" >"$TEST_REPO/local"
  cp -f "$TEST_REPO/local" "$SETTINGS"
  add_template_stop_hook

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.Stop[].hooks[].command]' "$SETTINGS"
  [ "$output" = '["continue"]' ]
}

@test "a local modification beats a conflicting template change" {
  run_setup
  jq '.env.BASH_DEFAULT_TIMEOUT_MS = "1000" | .hooks.Stop[0].hooks[0].timeout = 10' \
    "$TEMPLATE" >"$TEST_REPO/local"
  cp -f "$TEST_REPO/local" "$SETTINGS"
  jq '.env.BASH_DEFAULT_TIMEOUT_MS = "2000" | .hooks.Stop[0].hooks[0].timeout = 5' \
    "$REPO_TEMPLATE" >"$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.env.BASH_DEFAULT_TIMEOUT_MS, .hooks.Stop[0].hooks]' "$SETTINGS"
  [ "$output" = '["1000",[{"type":"command","command":"notify","timeout":10}]]' ]
}

@test "a first run without a base only adds and records the base" {
  mkdir -p "$TEST_REPO/.claude"
  jq '.env.BASH_DEFAULT_TIMEOUT_MS = "1000" | .hooks.Stop = []' \
    "$REPO_TEMPLATE" >"$SETTINGS"
  add_template_stop_hook

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.env.BASH_DEFAULT_TIMEOUT_MS, [.hooks.Stop[].hooks[].command]]' "$SETTINGS"
  [ "$output" = '["1000",["notify","continue"]]' ]
  cmp "$TEMPLATE" "$TEST_REPO/.claude/.settings.local.base.json"

  run_setup
  [ -z "$output" ]
}

@test "a new template group with an existing matcher reaches edited settings" {
  run_setup
  jq '.hooks.Stop[0].hooks += [{"type": "command", "command": "mine"}]' \
    "$TEMPLATE" >"$TEST_REPO/local"
  cp -f "$TEST_REPO/local" "$SETTINGS"
  jq '.hooks.Stop += [{"matcher": "", "hooks": [{"type": "command", "command": "stop-continue"}]}]' \
    "$REPO_TEMPLATE" >"$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.Stop[] | [.hooks[].command]]' "$SETTINGS"
  [ "$output" = '[["notify","mine","stop-continue"]]' ]
}

# Writes FILE to OUT with one "" Stop group per argument, each argument a
# space-separated list of hook commands.
stop_groups() {
  local file=$1 out=$2
  shift 2
  jq '.hooks.Stop = [$ARGS.positional[] | {matcher: "",
      hooks: [splits(" ") | {type: "command", command: .}]}]' "$file" --args "$@" >"$out"
}

@test "a template hook reaches a same-matcher group after a local deletion" {
  stop_groups "$REPO_TEMPLATE" "$TEMPLATE" notify sc
  run_setup
  stop_groups "$REPO_TEMPLATE" "$TEST_REPO/local" sc
  cp -f "$TEST_REPO/local" "$SETTINGS"
  stop_groups "$REPO_TEMPLATE" "$TEMPLATE" notify "sc extra"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.Stop[] | [.hooks[].command]]' "$SETTINGS"
  [ "$output" = '[["sc","extra"]]' ]
}

@test "a locally deleted hook stays deleted when the template drops another" {
  stop_groups "$REPO_TEMPLATE" "$TEMPLATE" notify sc
  run_setup
  stop_groups "$REPO_TEMPLATE" "$TEST_REPO/local" notify
  cp -f "$TEST_REPO/local" "$SETTINGS"
  stop_groups "$REPO_TEMPLATE" "$TEMPLATE" sc

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.Stop[].hooks[].command]' "$SETTINGS"
  [ "$output" = '[]' ]
}

@test "a missing template is named in the warning" {
  run_setup
  TEMPLATE="$TEST_REPO/absent.json"

  run_setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"absent.json is missing or not valid JSON"* ]]
}

@test "a group without a matcher matches the template's empty matcher" {
  mkdir -p "$TEST_REPO/.claude"
  jq '.hooks.Stop[0] |= del(.matcher)' "$REPO_TEMPLATE" >"$SETTINGS"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.Stop[].hooks[].command]' "$SETTINGS"
  [ "$output" = '["notify"]' ]
}

@test "the real template adds stop-continue beside notify in existing settings" {
  run_setup
  cp "$REAL_TEMPLATE" "$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.Stop[] | [.hooks[].command]]' "$SETTINGS"
  [ "$output" = '[["notify","stop-continue"]]' ]
}

@test "the real template adds the compact resume hook to existing settings" {
  jq 'del(.hooks.SessionStart)' "$REAL_TEMPLATE" >"$TEMPLATE"
  run_setup
  run jq -e '.hooks | has("SessionStart") | not' "$SETTINGS"
  [ "$status" -eq 0 ]
  cp "$REAL_TEMPLATE" "$TEMPLATE"

  run_setup
  [ "$status" -eq 0 ]
  run jq -c '[.hooks.SessionStart[] | {matcher, commands: [.hooks[].command]}]' "$SETTINGS"
  [ "$output" = '[{"matcher":"compact","commands":["compact-resume"]}]' ]
}
