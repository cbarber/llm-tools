#!/usr/bin/env bats

setup() {
  TEST_ROOT="$(mktemp -d)"
  TEST_HOME="${TEST_ROOT}/home"
  TEST_WORK="${TEST_ROOT}/work"
  TEST_BIN="${TEST_ROOT}/bin"
  mkdir -p "$TEST_HOME" "$TEST_WORK" "$TEST_BIN"
  SETUP_CONFIG_SCRIPT="${BATS_TEST_DIRNAME}/setup-config.sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_setup() {
  run bash -c 'cd "$1" && HOME="$2" PATH="$3:$PATH" OPEN_CURSOR_PLUGIN_ENTRY="$4" OPENCODE_PLUGIN_DIR="$5" bash "$6"' \
    _ "$TEST_WORK" "$TEST_HOME" "$TEST_BIN" \
    "/nix/store/new-open-cursor-2.5.8/lib/open-cursor/dist/plugin-entry.js" \
    "${TEST_ROOT}/missing-plugins" "$SETUP_CONFIG_SCRIPT"
}

@test "configures patched plugin and discovered Cursor models" {
  cat >"${TEST_BIN}/cursor-agent" <<'EOF'
#!/usr/bin/env bash
cat <<'MODELS'
auto - Auto (default)
composer-2.5 - Composer 2.5
sonnet-4.6-thinking - Claude 4.6 Sonnet (Thinking) (current)
MODELS
EOF
  chmod +x "${TEST_BIN}/cursor-agent"

  cat >"${TEST_WORK}/opencode.json" <<'EOF'
{
  "share": "disabled",
  "plugin": [
    "@rama_nigg/open-cursor@2.5.8",
    "file:///nix/store/old-open-cursor-2.5.8/lib/open-cursor/dist/plugin-entry.js",
    "other-plugin"
  ],
  "provider": {
    "cursor-acp": {
      "models": {
        "stale-model": { "name": "Stale" }
      }
    }
  }
}
EOF

  run_setup
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]

  run jq -e '
    .plugin == [
      "other-plugin",
      "file:///nix/store/new-open-cursor-2.5.8/lib/open-cursor/dist/plugin-entry.js"
    ] and
    (.provider["cursor-acp"].models | keys) == ["auto", "composer-2.5", "sonnet-4.6-thinking"] and
    .provider["cursor-acp"].models["sonnet-4.6-thinking"].name == "Claude 4.6 Sonnet (Thinking)"
  ' "${TEST_WORK}/opencode.json"
  if [ "$status" -ne 0 ]; then
    jq . "${TEST_WORK}/opencode.json" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "keeps the last model catalog when discovery fails" {
  cat >"${TEST_BIN}/cursor-agent" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${TEST_BIN}/cursor-agent"

  cat >"${TEST_WORK}/opencode.json" <<'EOF'
{
  "share": "disabled",
  "plugin": [],
  "provider": {
    "cursor-acp": {
      "models": {
        "composer-2.5": { "name": "Composer 2.5" }
      }
    }
  }
}
EOF

  run_setup
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]

  run jq -e '
    .provider["cursor-acp"].models["auto"].name == "Auto" and
    .provider["cursor-acp"].models["composer-2.5"].name == "Composer 2.5"
  ' "${TEST_WORK}/opencode.json"
  [ "$status" -eq 0 ]
}
