#!/usr/bin/env bash
# Shared shell aliases and functions for agent environments

# Git wrapper to prevent catastrophic recovery attempts on write operations
git() {
  local first_arg="${1:-}"
  local write_commands="add|commit|push|pull|merge|rebase|reset|checkout|branch|tag|stash|cherry-pick|revert|am|apply"
  
  case "$first_arg" in
    commit)
      # Show commit format before commit
      if command -v temper >/dev/null 2>&1 && [[ -f AGENTS.md ]]; then
        echo "📋 Commit Format:"
        echo ""
        temper commit
        echo ""
      fi
      
      # Execute commit (shift off 'commit' to avoid passing it twice)
      shift
      command git commit "$@" || {
        echo "❌ STOP: Git commit failed. You MUST ask user for guidance. DO NOT attempt recovery." >&2
        return 1
      }
      ;;
    
    *)
      # Handle other write operations
      if [[ "$first_arg" =~ ^($write_commands)$ ]]; then
        command git "$@" || {
          echo "❌ STOP: Git write operation failed. You MUST ask user for guidance. DO NOT attempt recovery." >&2
          return 1
        }
      else
        command git "$@"
      fi
      ;;
  esac
}

export -f git

# spr wrapper to auto-load GitHub token and handle prompts
spr() {
  # Auto-load GITHUB_TOKEN if available
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    local token_file="${HOME}/.config/nixsmith/github-token"
    if [[ -f "$token_file" ]]; then
      export GITHUB_TOKEN=$(cat "$token_file")
    fi
  fi
  
  # For merge command, auto-answer prompts with 'y'
  if [[ "${1:-}" == "merge" ]]; then
    yes | command spr "$@"
  else
    command spr "$@"
  fi
}
export -f spr

# Make agent-sandbox available as a command
agent-sandbox() {
  "$AGENT_SANDBOX_SCRIPT" "$@"
}
export -f agent-sandbox
