#!/usr/bin/env bash

# Setup OpenCode configuration and plugins on shell entry.

set -euo pipefail

GLOBAL_CONFIG_DIR="${HOME}/.config/opencode"
GLOBAL_CONFIG="${GLOBAL_CONFIG_DIR}/opencode.json"
[[ -f "${GLOBAL_CONFIG_DIR}/opencode.jsonc" && ! -f "$GLOBAL_CONFIG" ]] && GLOBAL_CONFIG="${GLOBAL_CONFIG_DIR}/opencode.jsonc"
PROJECT_CONFIG="opencode.json"

# ---------------------------------------------------------------------------
# Config discovery and creation
# ---------------------------------------------------------------------------
# Determine which config is active (global takes precedence over project).
# If neither exists, prompt the user to choose a location. Requires a tty —
# automated environments must pre-create the config.

if [[ -f "$GLOBAL_CONFIG" ]]; then
  CONFIG_LOCATION="global"
elif [[ -f "$PROJECT_CONFIG" ]]; then
  CONFIG_LOCATION="project"
else
  # No config found — require interactive terminal
  if [[ ! -t 0 ]]; then
    echo "ERROR: No OpenCode config found at '${PROJECT_CONFIG}' or '${GLOBAL_CONFIG}'." >&2
    echo "       Create one before running in a non-interactive environment." >&2
    exit 1
  fi

  echo ""
  echo "No OpenCode configuration found. Where would you like to install it?"
  echo "  [1] Project  — ${PROJECT_CONFIG}  (this repo only)"
  echo "  [2] Global   — ${GLOBAL_CONFIG}  (all projects)"
  echo ""
  read -r -p "Choice [1/2]: " choice </dev/tty

  case "$choice" in
    2)
      CONFIG_LOCATION="global"
      mkdir -p "$GLOBAL_CONFIG_DIR"
      cat >"$GLOBAL_CONFIG" <<'EOF'
{
  "$schema": "https://opncd.ai/config.json",
  "share": "disabled",
  "plugin": []
}
EOF
      echo "Created ${GLOBAL_CONFIG}"
      ;;
    *)
      CONFIG_LOCATION="project"
      cat >"$PROJECT_CONFIG" <<'EOF'
{
  "$schema": "https://opncd.ai/config.json",
  "share": "disabled",
  "plugin": []
}
EOF
      echo "Created ${PROJECT_CONFIG}"
      ;;
  esac
fi

if [[ "$CONFIG_LOCATION" == "global" ]]; then
  ACTIVE_CONFIG="$GLOBAL_CONFIG"
else
  ACTIVE_CONFIG="$PROJECT_CONFIG"
fi

# ---------------------------------------------------------------------------
# Temper plugin install
# ---------------------------------------------------------------------------
# Install temper into the plugins directory that matches the active config.
# Temper lives in .opencode/plugins/ (project) or ~/.config/opencode/plugins/
# (global) so OpenCode auto-loads it without an explicit opencode.json entry.

if [[ "$CONFIG_LOCATION" == "global" ]]; then
  PLUGINS_DIR="${GLOBAL_CONFIG_DIR}/plugins"
else
  PLUGINS_DIR=".opencode/plugins"
fi

# ---------------------------------------------------------------------------
# share:disabled compliance assertion
# ---------------------------------------------------------------------------
# Corporate policy requires sharing to be disabled in all OpenCode configs.
# Check every config that exists and auto-fix any violation with a warning.

assert_share_disabled() {
  local config="$1"
  local current
  current=$(jq -r '.share // empty' "$config" 2>/dev/null)
  if [[ "$current" != "disabled" ]]; then
    echo "WARNING: share is not set to 'disabled' in ${config} — fixing (corporate compliance requirement)" >&2
    local tmp
    tmp=$(mktemp)
    jq '.share = "disabled"' "$config" > "$tmp" && mv "$tmp" "$config"
  fi
}

[[ -f "$PROJECT_CONFIG" ]] && assert_share_disabled "$PROJECT_CONFIG"
[[ -f "$GLOBAL_CONFIG" ]] && assert_share_disabled "$GLOBAL_CONFIG"

configure_cursor_provider() {
  local config="$1"
  local plugin="file://${OPEN_CURSOR_PLUGIN_ENTRY}"
  local discovered_models="null"
  local models_output
  local tmp

  if models_output=$(timeout 5s cursor-agent models 2>/dev/null); then
    discovered_models=$(printf '%s\n' "$models_output" | jq -Rs '
      split("\n") |
      map(
        gsub("\\u001b\\[[0-9;]*m"; "") |
        try capture("^\\s*(?<id>[a-zA-Z0-9._-]+)\\s+-\\s+(?<name>.+?)(?:\\s+\\((?:current|default)\\))*\\s*$") catch null
      ) |
      map(select(. != null) | {key: .id, value: {name: .name}}) |
      from_entries |
      .auto //= {name: "Auto"}
    ')
    if [[ $(jq 'length' <<<"$discovered_models") -le 1 ]]; then
      discovered_models="null"
    fi
  fi

  tmp=$(mktemp)
  jq --arg plugin "$plugin" --argjson discovered_models "$discovered_models" '
    .plugin = (((.plugin // []) | map(select(
      (type != "string") or (
        (startswith("@rama_nigg/open-cursor@") or test("/[^/]+-open-cursor-[^/]+/lib/open-cursor/dist/plugin-entry\\.js$")) | not
      )
    ))) + [$plugin]) |
    .provider //= {} |
    .provider["cursor-acp"] //= {} |
    .provider["cursor-acp"].name //= "Cursor ACP" |
    .provider["cursor-acp"].npm //= "@ai-sdk/openai-compatible" |
    .provider["cursor-acp"].options //= {} |
    .provider["cursor-acp"].options.baseURL //= "http://127.0.0.1:32124/v1" |
    .provider["cursor-acp"].models //= {} |
    if $discovered_models == null then
      .provider["cursor-acp"].models.auto //= {"name": "Auto"}
    else
      .provider["cursor-acp"].models = $discovered_models
    end
  ' "$config" > "$tmp"

  if cmp -s "$config" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$config"
    echo "Configured Cursor provider in ${config}"
  fi
}

configure_cursor_provider "$ACTIVE_CONFIG"

if [[ -n "${OPENCODE_PLUGIN_DIR:-}" ]] && [[ -d "$OPENCODE_PLUGIN_DIR" ]]; then
  TEMPER_SRC="${OPENCODE_PLUGIN_DIR}/temper.ts"
  TEMPER_DEST="${PLUGINS_DIR}/temper.ts"

  if [[ ! -f "$TEMPER_DEST" ]]; then
    mkdir -p "$PLUGINS_DIR"
    install -m 0644 "$TEMPER_SRC" "$TEMPER_DEST"
    echo "Installed temper plugin to ${TEMPER_DEST}"
  else
    src_hash=$(sha256sum "$TEMPER_SRC" | cut -d' ' -f1)
    dest_hash=$(sha256sum "$TEMPER_DEST" | cut -d' ' -f1)
    if [[ "$src_hash" != "$dest_hash" ]]; then
      install -m 0644 "$TEMPER_SRC" "$TEMPER_DEST"
      echo "Updated temper plugin at ${TEMPER_DEST} (nix store version changed)"
    fi
  fi
fi
