#!/usr/bin/env bash
# Shared shell aliases and functions for agent environments

# Git wrapper to prevent catastrophic recovery attempts on write operations
git() {
  # Only intercept write operations that could cause damage
  local first_arg="${1:-}"
  local write_commands="add|commit|push|pull|merge|rebase|reset|checkout|branch|tag|stash|cherry-pick|revert|am|apply"
  
  if [[ "$first_arg" =~ ^($write_commands)$ ]]; then
    command git "$@" || {
      echo "❌ STOP: Git write operation failed. You MUST ask user for guidance. DO NOT attempt recovery." >&2
      return 1
    }
  else
    command git "$@"
  fi
}

export -f git

# Make agent-sandbox available as a command
agent-sandbox() {
  "$AGENT_SANDBOX_SCRIPT" "$@"
}
export -f agent-sandbox
