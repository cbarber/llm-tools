#!/usr/bin/env bash
# Shared shell aliases and functions for agent environments

git() {
  local first_arg="${1:-}"

  if [[ "$first_arg" == "commit" ]]; then
    local default_branch current_branch
    default_branch=$(command git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    current_branch=$(command git symbolic-ref --short HEAD 2>/dev/null || echo "")

    if [[ -n "$default_branch" && "$current_branch" == "$default_branch" ]]; then
      echo "⛔ Refusing to commit on the default branch ($default_branch). Create a feature branch first." >&2
      return 1
    fi

    if command -v temper >/dev/null 2>&1 && [[ -f AGENTS.md ]]; then
      echo "📋 Commit Format:"
      echo ""
      temper commit
      echo ""
    fi
    shift
    command git commit "$@"
    return
  fi

  if [[ "$first_arg" == "rebase" ]] && [[ " $* " =~ " -i " || " $* " =~ " --interactive " ]]; then
    echo "📋 Interactive rebase: GIT_SEQUENCE_EDITOR will inject 'break' and print the todo path."
    echo "   Edit the todo file, then run: git rebase --continue"
    echo "   If --continue opens an editor: GIT_EDITOR prints the file path and exits."
    echo "   Supply the message with: git commit --amend -m '...' then git rebase --continue"
    echo ""
  fi

  command git "$@"
}

export -f git

spr() {
  command spr "$@"
}
export -f spr

# Make agent-sandbox available as a command
agent-sandbox() {
  "$AGENT_SANDBOX_SCRIPT" "$@"
}
export -f agent-sandbox
