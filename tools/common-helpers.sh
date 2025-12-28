#!/usr/bin/env bash
# Common helper functions for agent environments

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
