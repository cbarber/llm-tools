#!/usr/bin/env bash

# Setup Claude Code settings.json for hooks
# Only creates settings.json if it doesn't already exist

set -euo pipefail

# Exit if settings.json already exists
if [[ -f ".claude/settings.local.json" ]]; then
  exit 0
fi

mkdir -p .claude
cp "${SETTINGS_TEMPLATE}" .claude/settings.local.json

echo "Created settings.json with Claude Code hooks (smart-lint, smart-test, notify)"
