#!/usr/bin/env bash

git() {
  command git "$@" || {
    echo "❌ Git command failed. Ask user for guidance instead of attempting recovery." >&2
    exit 1
  }
}

export -f git

# Make agent-sandbox available as a command
agent-sandbox() {
  "$AGENT_SANDBOX_SCRIPT" "$@"
}
export -f agent-sandbox
