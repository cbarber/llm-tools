# shellcheck shell=bash
# The per-session context size, then the context window on a second line
# when known: context-status records them from the status line,
# stop-continue reads them. Sourced by absolute path from the sourcing
# script's own directory.

# Prints the record's path for session $1, or fails when $1 is not a safe
# file name.
context_size_file() {
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  echo "$HOME/.cache/claude/context-size/$1"
}
