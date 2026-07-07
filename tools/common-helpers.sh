#!/usr/bin/env bash
# Common helper functions for agent environments

# Extract the GitHub owner (org or username) from the current git remote.
# Outputs the owner lowercased, which is the canonical key for per-org secrets
# Prints nothing and returns 1 if no GitHub remote is found.
extract_github_owner() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" =~ github\.com[:/]([^/]+)/ ]]; then
    echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  return 1
}
