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
  run bash -c 'cd "$1" && HOME="$2" PATH="$3:$PATH" OPENCODE_CURSOR_PLUGIN_ENTRY="$4" OPENCODE_CURSOR_PROVIDER_NPM="$5" OPENCODE_PLUGIN_DIR="$6" bash "$7"' \
    _ "$TEST_WORK" "$TEST_HOME" "$TEST_BIN" \
    "/nix/store/new-opencode-cursor-0.9.0/lib/opencode-cursor/dist/plugin/index.js" \
    "file:///nix/store/new-opencode-cursor-0.9.0/lib/opencode-cursor/dist/provider/index.js" \
    "${TEST_ROOT}/missing-plugins" "$SETUP_CONFIG_SCRIPT"
}

@test "configures the pinned native Cursor plugin idempotently" {
  cat >"${TEST_WORK}/opencode.json" <<'EOF'
{
  "share": "disabled",
  "plugin": [
    "@rama_nigg/open-cursor@2.5.8",
    "file:///nix/store/old-open-cursor-2.5.8/lib/open-cursor/dist/plugin-entry.js",
    "@stablekernel/opencode-cursor@0.6.0",
    "file:///nix/store/old-opencode-cursor-0.9.0/lib/opencode-cursor/dist/plugin/index.js",
    "other-plugin"
  ],
  "provider": {
    "cursor": {
      "npm": "@stablekernel/opencode-cursor"
    },
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

  run_setup
  [ "$status" -eq 0 ]

  run jq -e '
    .plugin == [
      "other-plugin",
      "file:///nix/store/new-opencode-cursor-0.9.0/lib/opencode-cursor/dist/plugin/index.js"
    ] and
    (.provider["cursor-acp"] == null) and
    .provider.cursor.npm == "file:///nix/store/new-opencode-cursor-0.9.0/lib/opencode-cursor/dist/provider/index.js"
  ' "${TEST_WORK}/opencode.json"
  if [ "$status" -ne 0 ]; then
    jq . "${TEST_WORK}/opencode.json" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "preserves unrelated providers" {
  cat >"${TEST_WORK}/opencode.json" <<'EOF'
{
  "share": "disabled",
  "plugin": [],
  "provider": {
    "anthropic": {
      "models": {
        "claude": { "name": "Claude" }
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
    .provider.anthropic.models.claude.name == "Claude"
  ' "${TEST_WORK}/opencode.json"
  [ "$status" -eq 0 ]
}
