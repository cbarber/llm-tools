#!/usr/bin/env bash

# Setup OpenCode configuration and plugins on shell entry.
# Only creates opencode.json if it doesn't already exist.

set -euo pipefail

# Copy temper plugin from nix store if not already present
if [[ ! -d ".opencode/plugin/temper" ]] && [[ -n "${OPENCODE_PLUGIN_TEMPER_DIR:-}" ]] && [[ -d "$OPENCODE_PLUGIN_TEMPER_DIR" ]]; then
  mkdir -p .opencode/plugin
  cp -r "$OPENCODE_PLUGIN_TEMPER_DIR" .opencode/plugin/
  echo "Copied temper plugin from nix store to .opencode/plugin/temper"
fi

# Add temper plugin to opencode.json if not already present
if [[ -f "opencode.json" ]] && ! grep -q ".opencode/plugin/temper" opencode.json 2>/dev/null; then
  if [[ -d ".opencode/plugin/temper" ]]; then
    tmp=$(mktemp)
    jq '.plugin += ["./.opencode/plugin/temper"]' opencode.json > "$tmp" && mv "$tmp" opencode.json
    echo "Added temper plugin to opencode.json"
  fi
fi

# Create opencode.json with beads plugin if it doesn't exist
if [[ ! -f "opencode.json" ]]; then
  cat >opencode.json <<'EOF'
{
  "$schema": "https://opncd.ai/config.json",
  "share": "disabled",
  "plugin": ["opencode-beads@0.3.0"]
}
EOF
  echo "Created opencode.json with opencode-beads@0.3.0 plugin"
fi
