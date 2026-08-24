#!/usr/bin/env bash
# Common helper functions for agent environments

# Normalize the current origin as a host/path value suitable for repo matching.
extract_repo_url() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")

  if [[ "$remote_url" =~ ^[^/@]+@([a-zA-Z0-9.-]+):(.+)$ ]]; then
    remote_url="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$remote_url" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@]+@)?([a-zA-Z0-9.:-]+)/(.+)$ ]]; then
    remote_url="${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
  else
    return 1
  fi

  remote_url=${remote_url%/}
  remote_url=${remote_url%.git}
  echo "$remote_url" | tr '[:upper:]' '[:lower:]'
}

extract_repo_owner_scope() {
  local repo_url
  repo_url=$(extract_repo_url) || return 1
  [[ "$repo_url" == */*/* ]] || return 1
  echo "${repo_url%/*}"
}

nixsmith_repo_scope_key() {
  local secrets_file="$1"
  local repo_url
  repo_url=$(extract_repo_url) || return 1

  jq -r --arg url "$repo_url" '
    (.repos // {}) | keys
    | map(. as $key | select($url == $key or ($url | startswith($key + "/"))))
    | sort_by(length) | last // empty
  ' "$secrets_file"
}

# Extract the GitHub owner for diagnostics and GitHub-specific setup.
extract_github_owner() {
  local repo_url
  repo_url=$(extract_repo_url) || return 1
  if [[ "$repo_url" =~ ^github\.com/([^/]+)/ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

detect_forge() {
  local repo_url host
  repo_url=$(extract_repo_url) || { echo "unknown"; return; }
  host=${repo_url%%/*}

  if [[ "$host" == "github.com" ]]; then
    echo "github"
  elif [[ "$host" == "gitlab.com" ]]; then
    echo "gitlab"
  elif [[ "$host" == "gitea.com" || "$host" == *gitea* || "$host" == git.* ]]; then
    echo "gitea"
  else
    echo "unknown"
  fi
}
