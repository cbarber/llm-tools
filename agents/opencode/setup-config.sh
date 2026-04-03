#!/usr/bin/env bash

# Setup OpenCode configuration and plugins on shell entry.

set -euo pipefail

GLOBAL_CONFIG_DIR="${HOME}/.config/opencode"
GLOBAL_CONFIG="${GLOBAL_CONFIG_DIR}/opencode.json"
PROJECT_CONFIG="opencode.json"

# ---------------------------------------------------------------------------
# Config discovery and creation
# ---------------------------------------------------------------------------
# Determine which config is active (project takes precedence over global).
# If neither exists, prompt the user to choose a location. Requires a tty —
# automated environments must pre-create the config.

if [[ -f "$PROJECT_CONFIG" ]]; then
  CONFIG_LOCATION="project"
elif [[ -f "$GLOBAL_CONFIG" ]]; then
  CONFIG_LOCATION="global"
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
  "plugin": ["opencode-beads@0.3.0"]
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
  "plugin": ["opencode-beads@0.3.0"]
}
EOF
      echo "Created ${PROJECT_CONFIG}"
      ;;
  esac
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

if [[ -n "${OPENCODE_PLUGIN_DIR:-}" ]] && [[ -d "$OPENCODE_PLUGIN_DIR" ]]; then
  TEMPER_SRC="${OPENCODE_PLUGIN_DIR}/temper.ts"
  TEMPER_DEST="${PLUGINS_DIR}/temper.ts"

  if [[ ! -f "$TEMPER_DEST" ]]; then
    mkdir -p "$PLUGINS_DIR"
    cp "$TEMPER_SRC" "$TEMPER_DEST"
    echo "Installed temper plugin to ${TEMPER_DEST}"
  else
    src_hash=$(sha256sum "$TEMPER_SRC" | cut -d' ' -f1)
    dest_hash=$(sha256sum "$TEMPER_DEST" | cut -d' ' -f1)
    if [[ "$src_hash" != "$dest_hash" ]]; then
      cp "$TEMPER_SRC" "$TEMPER_DEST"
      echo "Updated temper plugin at ${TEMPER_DEST} (nix store version changed)"
    fi
  fi
fi
