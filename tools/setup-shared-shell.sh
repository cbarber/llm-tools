#!/usr/bin/env bash
set -euo pipefail
# Shared shell setup sourced by all agent environments.
# Callers must set TOOLS_DIR, AGENTS_TEMPLATE_DEFAULT, AGENTS_TEMPLATES_DIR,
# and AGENT_ENV_CONFIG_DIR before sourcing this file.
# Optional: set BEADS_POST_INIT to a command run after bd init in standard repos.

select_workflow() {
  [[ -z "${AGENTS_TEMPLATE:-}" ]] || {
    [[ "${AGENTS_TEMPLATE}" != /* ]] \
      && echo "${AGENTS_TEMPLATES_DIR}/${AGENTS_TEMPLATE}" \
      || echo "${AGENTS_TEMPLATE}"
    return
  }
  [[ -f ~/.config/nixsmith/workflow.md ]] && echo ~/.config/nixsmith/workflow.md && return
  echo "${AGENTS_TEMPLATE_DEFAULT}"
}

export AGENTS_TEMPLATE="$(select_workflow)"
export DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")

[[ -f .env ]] && source .env
[[ -f "${AGENT_ENV_CONFIG_DIR}/.env" ]] && source "${AGENT_ENV_CONFIG_DIR}/.env"

# fix-beads-hooks is idempotent; run unconditionally when in a git repo.
git rev-parse --git-dir >/dev/null 2>&1 && "${TOOLS_DIR}/fix-beads-hooks" . 2>/dev/null || true

# Worktree repos share beads under the common git dir so all worktrees see the
# same issue tracker. Standard repos init in the working tree root as usual.
if git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null); then
  git_dir=$(git rev-parse --git-dir 2>/dev/null)

  if [[ "$git_dir" != "$git_common_dir" ]]; then
    beads_shared="$git_common_dir/beads"

    if [[ -d "$beads_shared/.beads" ]]; then
      export BEADS_DIR="$beads_shared/.beads"
      echo "Using shared beads at: $BEADS_DIR"
    elif [[ "${BD_SKIP_SETUP:-}" != "true" ]]; then
      echo "Initializing shared beads for all worktrees..."
      mkdir -p "$beads_shared"

      branch_arg=""
      if [[ -n "${BD_BRANCH:-}" ]]; then
        branch_arg="--branch ${BD_BRANCH}"
        echo "  Using branch: ${BD_BRANCH}"
        export BD_BRANCH
      fi

      if (cd "$beads_shared" && bd init --quiet "$branch_arg" 2>/dev/null); then
        export BEADS_DIR="$beads_shared/.beads"

        if [[ -n "${BD_BRANCH:-}" ]]; then
          (cd "$beads_shared" && bd daemon --start --auto-commit 2>/dev/null) || true
          echo "Beads initialized at $BEADS_DIR with auto-commit to branch: ${BD_BRANCH}"
        else
          echo "Beads initialized at $BEADS_DIR. Use 'bd ready' to see tasks, 'bd create' to add tasks."
        fi
        echo "Set BD_SKIP_SETUP=true to disable auto-initialization."
      fi
    fi
  fi
elif [[ ! -d ".beads" && "${BD_SKIP_SETUP:-}" != "true" ]]; then
  echo "Initializing beads for task tracking..."

  branch_arg=""
  [[ -n "${BD_BRANCH:-}" ]] && branch_arg="--branch ${BD_BRANCH}"

  if bd init --quiet $branch_arg 2>/dev/null; then
    ${BEADS_POST_INIT:-}

    if [[ -n "${BD_BRANCH:-}" ]]; then
      sed -i "s/^# sync-branch:.*/sync-branch: \"${BD_BRANCH}\"/" .beads/config.yaml
      echo "Beads initialized with auto-commit to branch: ${BD_BRANCH}"
    else
      echo "Beads initialized. Use 'bd ready' to see tasks, 'bd create' to add tasks."
    fi
    echo "Set BD_SKIP_SETUP=true to disable auto-initialization."
  fi
fi

if [[ -d ".beads" && -f ".beads/config.yaml" && "${BD_SKIP_SETUP:-}" != "true" ]]; then
  if grep -q "^sync-branch:" .beads/config.yaml 2>/dev/null; then
    if ! bd daemon --status --json 2>/dev/null | jq -e '.running' >/dev/null 2>&1; then
      bd daemon --start --auto-commit 2>/dev/null || true
      echo "Started beads daemon with auto-commit"
    fi
  fi
fi

if [[ "${SKIP_AGENT_SETUP:-}" != "true" ]] && git remote -v &>/dev/null 2>&1; then
  "${TOOLS_DIR}/setup-agent-keys.sh" || {
    echo "Error: SSH key setup failed" >&2
    exit 1
  }
  "${TOOLS_DIR}/setup-agent-api-tokens.sh" || {
    echo "Error: API token setup failed" >&2
    exit 1
  }
fi
