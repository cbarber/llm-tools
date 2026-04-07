#!/usr/bin/env bash
# Common helper functions for agent environments

# Extract the GitHub owner (org or username) from the current git remote.
# Outputs the owner lowercased, which is the canonical key for per-org token
# file names (github-token-<owner>). GitHub names are case-insensitive;
# lowercasing avoids case-collision on case-sensitive Linux filesystems.
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

# Resolve the nixsmith GitHub token file path for the current repo's owner.
# Outputs the absolute path to ~/.config/nixsmith/github-token-<owner>.
# Prints nothing and returns 1 if no GitHub remote is found.
nixsmith_github_token_file() {
  local owner
  owner=$(extract_github_owner) || return 1
  echo "${HOME}/.config/nixsmith/github-token-${owner}"
}

nixsmith_legacy_github_token_file() {
  echo "${HOME}/.config/nixsmith/github-token"
}

# Add agent-specific paths to BWRAP_EXTRA_PATHS
# Usage: add_sandbox_paths "/path/one" "/path/two" "~/path/three"
# Only adds paths that exist; does not create them
add_sandbox_paths() {
  local existing_paths=()
  
  for path in "$@"; do
    # Expand tilde to home directory
    local expanded_path="${path/#\~/$HOME}"
    
    # Skip empty paths
    [[ -z "$expanded_path" ]] && continue
    
    # Add to list if path exists
    if [[ -d "$expanded_path" ]]; then
      existing_paths+=("$expanded_path")
    fi
  done
  
  # Append to BWRAP_EXTRA_PATHS if any paths exist
  if [[ ${#existing_paths[@]} -gt 0 ]]; then
    local new_paths
    new_paths=$(IFS=:; echo "${existing_paths[*]}")
    export BWRAP_EXTRA_PATHS="${BWRAP_EXTRA_PATHS:-}${BWRAP_EXTRA_PATHS:+:}${new_paths}"
  fi
}
