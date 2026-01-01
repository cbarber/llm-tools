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

# Make agent-sandbox available as a command
agent-sandbox() {
  "$AGENT_SANDBOX_SCRIPT" "$@"
}
export -f agent-sandbox
