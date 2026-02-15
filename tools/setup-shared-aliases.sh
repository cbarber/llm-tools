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

spr() {
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    local token_file="${HOME}/.config/nixsmith/github-token"
    if [[ -f "$token_file" ]]; then
      GITHUB_TOKEN=$(cat "$token_file")
      export GITHUB_TOKEN
    fi
  fi
  
  local cmd="${1:-}"
  local result
  local exit_code
  
  if [[ "$cmd" == "update" ]]; then
    result=$(command spr "$@" 2>&1)
    exit_code=$?
    echo "$result"
    
    if [[ $exit_code -eq 0 ]] && [[ -n "${OPENCODE_SESSION_ID:-}" ]]; then
      local repo_dir=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      local repo_hash=$(echo "$repo_dir" | sed 's#/#-#g' | sed 's#^-##')
      local state_dir="${HOME}/.local/share/nixsmith/pr-poll/${repo_hash}"
      mkdir -p "$state_dir"
      
      local pid_file="${state_dir}/daemon.pid"
      local log_file="${state_dir}/daemon.log"
      
      if [[ ! -f "$pid_file" ]] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
        echo "Starting PR polling daemon" >&2
        nohup bash "${repo_dir}/tools/pr-poll" --daemon >> "$log_file" 2>&1 &
      fi
    fi
    
    return $exit_code
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
