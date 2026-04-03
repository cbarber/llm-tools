#!/usr/bin/env bash

# Setup OpenCode configuration and plugins on shell entry.
# Only creates opencode.json if it doesn't already exist.

set -euo pipefail

# Copy temper plugin from nix store if not already present.
# Temper lives in .opencode/plugins/ so OpenCode auto-loads it without
# requiring an explicit entry in opencode.json.
if [[ ! -f ".opencode/plugins/temper.ts" ]] && [[ -n "${OPENCODE_PLUGIN_TEMPER_DIR:-}" ]] && [[ -d "$OPENCODE_PLUGIN_TEMPER_DIR" ]]; then
  mkdir -p .opencode/plugins
  cp "$OPENCODE_PLUGIN_DIR/temper.ts" .opencode/plugins/temper.ts
  echo "Copied temper plugin from nix store to .opencode/plugins/temper.ts"
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
