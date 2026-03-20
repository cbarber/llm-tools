#!/usr/bin/env bash
# Shared shell aliases and functions for agent environments

git() {
  local first_arg="${1:-}"

  if [[ "$first_arg" == "commit" ]]; then
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
