#!/usr/bin/env bats
# The sandbox's commit hook, reached through agent-sandbox with a stub fence
# that records its settings and runs the command unsandboxed.

TOOLS="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  TEST_REPO="$BATS_TEST_TMPDIR/repo"
  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_HOME/.config/nixsmith" "$TEST_BIN"
  printf '%s\n' '#!/usr/bin/env bash' 'while [[ "$1" != "--" ]]; do' '  if [[ "$1" == "--settings" ]]; then cp "$2" "$FENCE_SETTINGS_CAPTURE"; shift 2' '  else shift; fi' 'done' 'shift' 'exec "$@"' >"$TEST_BIN/fence"
  chmod +x "$TEST_BIN/fence"
  git init -q "$TEST_REPO"
  unset NIXSMITH_SECRETS_ENV NIXSMITH_CREDENTIAL_PROXY NIXSMITH_DERIVED_ENV AUTHORED_BY_MODEL
  export AUTHORED_BY_AGENT=claude-code
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
}

# Runs git in the test repository under agent-sandbox.
sandboxed_git() {
  env HOME="$TEST_HOME" FENCE_PATH="$TEST_BIN/fence" FENCE_SETTINGS_CAPTURE="$TEST_HOME/fence.json" \
    TOOLS_DIR="$TOOLS" bash -c 'cd "$1"; shift; exec "$@"' _ "$TEST_REPO" "$TOOLS/agent-sandbox.sh" git "$@"
}

trailers() {
  git -C "$TEST_REPO" log -1 --format=%B | git interpret-trailers --parse | grep '^Authored-By: '
}

reviews() {
  git -C "$TEST_REPO" log -1 --format=%B "${1:-HEAD}" | git interpret-trailers --parse | grep '^Reviewed-By: '
}

@test "a -m commit carries one trailer naming the agent" {
  sandboxed_git commit -q --allow-empty -m "feat: x"
  [ "$(trailers)" = "Authored-By: claude-code" ]
}

@test "a --no-verify commit still carries the trailer" {
  sandboxed_git commit -q --no-verify --allow-empty -m "feat: x"
  [ "$(trailers)" = "Authored-By: claude-code" ]
}

@test "the model is named when the environment provides it" {
  AUTHORED_BY_MODEL=m1 sandboxed_git commit -q --allow-empty -m "feat: x"
  [ "$(trailers)" = "Authored-By: claude-code (m1)" ]
}

@test "amending a stamped commit does not duplicate the trailer" {
  sandboxed_git commit -q --allow-empty -m "feat: x"
  sandboxed_git commit -q --allow-empty --amend --no-edit
  sandboxed_git commit -q --allow-empty --amend -m "$(git -C "$TEST_REPO" log -1 --format=%B)"
  [ "$(trailers)" = "Authored-By: claude-code" ]
}

# Commits f with each content in turn: a base, a reviewed human change on
# side, and an upstream change on up; leaves side checked out.
diverge() {
  printf '%s' "$1" >"$TEST_REPO/f" && git -C "$TEST_REPO" add f && git -C "$TEST_REPO" commit -q -m "feat: base"
  git -C "$TEST_REPO" checkout -q -b side
  printf '%s' "$2" >"$TEST_REPO/f" && git -C "$TEST_REPO" commit -q -am "feat: human" -m "Reviewed-By: r"
  git -C "$TEST_REPO" checkout -q -b up HEAD~1
  printf '%s' "$3" >"$TEST_REPO/f" && git -C "$TEST_REPO" commit -q -am "feat: other"
  git -C "$TEST_REPO" checkout -q side
}

@test "replaying or amending a commit made outside the sandbox keeps its message" {
  diverge $'a\nb\nc\nd\ne\n' $'a\nb\nc\nD\ne\n' $'a\nB\nc\nd\ne\n'
  sandboxed_git commit -q --amend --no-edit
  sandboxed_git rebase -q up
  sandboxed_git checkout -q up
  sandboxed_git cherry-pick side >/dev/null
  run bash -c 'git -C "$1" log --all --format=%B | grep "^Authored-By: "' _ "$TEST_REPO"
  [ -z "$output" ]
  [ "$(reviews side)" = "Reviewed-By: r" ]
  [ "$(reviews up)" = "Reviewed-By: r" ]
}

@test "a rebase continued with a resolution that alters the change stamps it" {
  diverge $'a\n' $'s\n' $'m\n'
  run sandboxed_git rebase -q up
  [ "$status" -ne 0 ]
  echo s >"$TEST_REPO/f" && git -C "$TEST_REPO" add f
  GIT_EDITOR=true sandboxed_git rebase --continue >/dev/null
  [ "$(trailers)" = "Authored-By: claude-code" ]
  run reviews
  [ -z "$output" ]
}

@test "a cherry-pick resolution committed by hand that alters the change stamps it" {
  diverge $'a\n' $'s\n' $'m\n'
  git -C "$TEST_REPO" checkout -q up
  run sandboxed_git cherry-pick side
  [ "$status" -ne 0 ]
  echo s >"$TEST_REPO/f" && git -C "$TEST_REPO" add f
  GIT_EDITOR=true sandboxed_git commit -q
  [ "$(trailers)" = "Authored-By: claude-code" ]
  run reviews
  [ -z "$output" ]
}

@test "a conflict resolution equal to the original change keeps its message" {
  # Upstream changes only an adjacent line, which the patch-id leaves out.
  diverge $'a\nb\nc\n' $'a\nB\nc\n' $'a \nb\nc\n'
  run sandboxed_git rebase -q up
  [ "$status" -ne 0 ]
  printf '%s\n' 'a ' B c >"$TEST_REPO/f" && git -C "$TEST_REPO" add f
  GIT_EDITOR=true sandboxed_git rebase --continue >/dev/null
  run trailers
  [ -z "$output" ]
  [ "$(reviews)" = "Reviewed-By: r" ]
}

@test "a conflict resolution that changes only whitespace stamps it" {
  diverge $'if a:\n  b\nc\n' $'if a:\n  b\n  x\nc\n' $'if a:\n  b\nd\n'
  run sandboxed_git rebase -q up
  [ "$status" -ne 0 ]
  printf '%s\n' 'if a:' '  b' x d >"$TEST_REPO/f" && git -C "$TEST_REPO" add f
  GIT_EDITOR=true sandboxed_git rebase --continue >/dev/null
  [ "$(trailers)" = "Authored-By: claude-code" ]
  run reviews
  [ -z "$output" ]
}

@test "a new commit at a rebase edit stop carries the trailer" {
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: base"
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: human"
  GIT_SEQUENCE_EDITOR="sed -i 1s/^pick/edit/" sandboxed_git rebase -q -i HEAD~1
  sandboxed_git commit -q --allow-empty -m "feat: x"
  [ "$(trailers)" = "Authored-By: claude-code" ]
}

@test "folding an agent fixup into a reviewed commit stamps it and drops the review" {
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: base"
  echo a >"$TEST_REPO/f" && git -C "$TEST_REPO" add f && git -C "$TEST_REPO" commit -q -m "feat: human" -m "Reviewed-By: r"
  echo b >"$TEST_REPO/f" && sandboxed_git commit -q -am "fixup! feat: human"
  echo c >"$TEST_REPO/g" && git -C "$TEST_REPO" add g && git -C "$TEST_REPO" commit -q -m "feat: later" -m "Reviewed-By: r"
  GIT_SEQUENCE_EDITOR=true sandboxed_git rebase -q -i --autosquash HEAD~3 >/dev/null
  [ "$(git -C "$TEST_REPO" log -1 --format=%s HEAD~1)" = "feat: human" ]
  [ "$(git -C "$TEST_REPO" log -1 --format=%B HEAD~1 | git interpret-trailers --parse)" = "Authored-By: claude-code" ]
  run trailers
  [ -z "$output" ]
  [ "$(reviews)" = "Reviewed-By: r" ]
}

@test "squashing an agent commit into a reviewed commit stamps it and drops the review" {
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: base"
  echo a >"$TEST_REPO/f" && git -C "$TEST_REPO" add f && git -C "$TEST_REPO" commit -q -m "feat: human" -m "Reviewed-By: r"
  echo b >"$TEST_REPO/g" && git -C "$TEST_REPO" add g && sandboxed_git commit -q -m "squash! feat: human"
  GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true sandboxed_git rebase -q -i --autosquash HEAD~2 >/dev/null
  [ "$(trailers)" = "Authored-By: claude-code" ]
  # The squash's message follows the review, which is then no trailer.
  run bash -c 'git -C "$1" log -1 --format=%B | grep "^Reviewed-By: "' _ "$TEST_REPO"
  [ -z "$output" ]
}

@test "amending a reviewed commit with a staged change stamps it and drops the review" {
  echo a >"$TEST_REPO/f" && git -C "$TEST_REPO" add f && git -C "$TEST_REPO" commit -q -m "feat: human" -m "Reviewed-By: r"
  echo b >"$TEST_REPO/f" && git -C "$TEST_REPO" add f
  sandboxed_git commit -q --amend --no-edit
  [ "$(trailers)" = "Authored-By: claude-code" ]
  run reviews
  [ -z "$output" ]
}

@test "amending a reviewed commit to move its change stamps it and drops the review" {
  printf '%s\n' a b c >"$TEST_REPO/f" && git -C "$TEST_REPO" add f && git -C "$TEST_REPO" commit -q -m "feat: base"
  printf '%s\n' a x b c >"$TEST_REPO/f" && git -C "$TEST_REPO" commit -q -am "feat: human" -m "Reviewed-By: r"
  printf '%s\n' a b c x >"$TEST_REPO/f" && git -C "$TEST_REPO" add f
  sandboxed_git commit -q --amend --no-edit
  [ "$(trailers)" = "Authored-By: claude-code" ]
  run reviews
  [ -z "$output" ]
}

@test "a merge a rebase recreates unchanged keeps its message" {
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: base"
  git -C "$TEST_REPO" checkout -q -b topic
  echo t >"$TEST_REPO/t" && git -C "$TEST_REPO" add t && git -C "$TEST_REPO" commit -q -m "feat: topic"
  git -C "$TEST_REPO" checkout -q -b side HEAD~1
  git -C "$TEST_REPO" merge -q --no-ff topic -m "feat: merge" -m "Reviewed-By: r"
  git -C "$TEST_REPO" checkout -q -b up HEAD~1
  echo u >"$TEST_REPO/u" && git -C "$TEST_REPO" add u && git -C "$TEST_REPO" commit -q -m "feat: other"
  git -C "$TEST_REPO" checkout -q side
  sandboxed_git rebase -q -r up
  [ "$(git -C "$TEST_REPO" rev-list --parents -1 HEAD | wc -w)" -eq 3 ]
  run trailers
  [ -z "$output" ]
  [ "$(reviews)" = "Reviewed-By: r" ]
}

@test "a merge after a rebase that stopped carries the trailer" {
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: base"
  git -C "$TEST_REPO" checkout -q -b side
  echo x >"$TEST_REPO/x" && git -C "$TEST_REPO" add x && git -C "$TEST_REPO" commit -q -m "feat: human"
  GIT_SEQUENCE_EDITOR="sed -i 1s/^pick/edit/" git -C "$TEST_REPO" rebase -q -i HEAD~1
  git -C "$TEST_REPO" rebase --continue >/dev/null
  # The finished rebase leaves REBASE_HEAD naming the change the merge brings.
  [ "$(git -C "$TEST_REPO" rev-parse REBASE_HEAD)" = "$(git -C "$TEST_REPO" rev-parse side)" ]
  git -C "$TEST_REPO" checkout -q -
  GIT_EDITOR=true sandboxed_git merge -q --no-ff side
  [ "$(trailers)" = "Authored-By: claude-code" ]
}

@test "a hand-written trailer for the agent is kept as the only one" {
  sandboxed_git commit -q --allow-empty -m "feat: x" -m "Authored-By: claude-code (m2)"
  [ "$(trailers)" = "Authored-By: claude-code (m2)" ]
}

@test "another agent's trailer is kept beside this agent's" {
  sandboxed_git commit -q --allow-empty -m "feat: x" -m "Authored-By: opencode"
  [ "$(trailers)" = $'Authored-By: opencode\nAuthored-By: claude-code' ]
}

# Writes an executable hook, from the remaining lines, into a hooks directory.
repo_hook() {
  mkdir -p "$1"
  printf '%s\n' '#!/usr/bin/env bash' "${@:3}" >"$1/$2"
  chmod +x "$1/$2"
}

@test "a failing repository pre-commit blocks a sandboxed commit" {
  repo_hook "$TEST_REPO/.git/hooks" pre-commit 'exit 1'
  run sandboxed_git commit -q --allow-empty -m "feat: x"
  [ "$status" -ne 0 ]
  run git -C "$TEST_REPO" rev-parse -q --verify HEAD
  [ -z "$output" ]
}

@test "a repository commit-msg hook runs on its message" {
  repo_hook "$TEST_REPO/.git/hooks" commit-msg 'git interpret-trailers --in-place --trailer "Checked: yes" "$1"'
  sandboxed_git commit -q --allow-empty -m "feat: x"
  git -C "$TEST_REPO" log -1 --format=%B | grep -qx "Checked: yes"
}

@test "a hook in the repository's own core.hooksPath runs" {
  git -C "$TEST_REPO" config core.hooksPath .husky
  repo_hook "$TEST_REPO/.husky" post-commit 'echo "$PWD" >"$(git rev-parse --git-dir)/post-commit-ran"'
  sandboxed_git commit -q --allow-empty -m "feat: x"
  [ "$(cat "$TEST_REPO/.git/post-commit-ran")" = "$TEST_REPO" ]
}

@test "a non-executable repository hook is skipped" {
  repo_hook "$TEST_REPO/.git/hooks" pre-commit 'exit 1'
  chmod -x "$TEST_REPO/.git/hooks/pre-commit"
  sandboxed_git commit -q --allow-empty -m "feat: x"
}

@test "a repository prepare-commit-msg runs and the trailer is added once" {
  repo_hook "$TEST_REPO/.git/hooks" prepare-commit-msg 'git interpret-trailers --in-place --trailer "Prepared: $2" "$1"'
  sandboxed_git commit -q --allow-empty -m "feat: x"
  git -C "$TEST_REPO" log -1 --format=%B | grep -qx "Prepared: message"
  [ "$(trailers)" = "Authored-By: claude-code" ]
}

@test "git init inside the sandbox creates a working repository" {
  sandboxed_git init -q "$BATS_TEST_TMPDIR/new"
  sandboxed_git init -q --bare "$BATS_TEST_TMPDIR/new.git"
  git -C "$BATS_TEST_TMPDIR/new" rev-parse --git-dir
  git -C "$BATS_TEST_TMPDIR/new.git" rev-parse --git-dir
}

@test "commits outside the sandbox are untouched" {
  git -C "$TEST_REPO" commit -q --allow-empty -m "feat: x"
  run trailers
  [ -z "$output" ]
}

@test "the hooks directory is denied to sandbox writes" {
  sandboxed_git status >/dev/null
  jq -e --arg hooks "$TOOLS/git-hooks" '.filesystem.denyWrite | index($hooks)' "$TEST_HOME/fence.json" >/dev/null
}
