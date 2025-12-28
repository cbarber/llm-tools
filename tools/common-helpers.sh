#!/usr/bin/env bash
# Common helper functions for agent environments

# Setup language tooling cache paths for sandbox
# These paths are bind-mounted only if they exist, allowing language tools to cache builds/packages
setup_language_cache_paths() {
  local cache_paths=(
    "$HOME/.cache/go-build"
    "$HOME/.cargo"
    "$HOME/.cache/pip"
    "$HOME/.gem"
    "$HOME/.cache/yarn"
    "$HOME/.npm"
    "$HOME/.local/share/pnpm"
    "$HOME/.bun"
  )
  
  # Build list of existing paths
  local existing_paths=()
  for path in "${cache_paths[@]}"; do
    if [[ -d "$path" ]]; then
      existing_paths+=("$path")
    fi
  done
  
  # Append to BWRAP_EXTRA_PATHS if any paths exist
  if [[ ${#existing_paths[@]} -gt 0 ]]; then
    local new_paths
    new_paths=$(IFS=:; echo "${existing_paths[*]}")
    export BWRAP_EXTRA_PATHS="${BWRAP_EXTRA_PATHS:-}${BWRAP_EXTRA_PATHS:+:}${new_paths}"
  fi
}
