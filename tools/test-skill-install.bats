#!/usr/bin/env bats
# How shell entry installs this repo's skills into a shared skills directory.

TOOLS="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  SOURCE="$BATS_TEST_TMPDIR/skills"
  TARGET="$TEST_HOME/.agents/skills"
  mkdir -p "$TARGET" "$SOURCE/kept" "$SOURCE/dropped" "$BATS_TEST_TMPDIR/checkout" "$BATS_TEST_TMPDIR/bin"
  # The agent sandbox refuses rsync; the removal under test does not depend on it.
  printf '%s\n' '#!/usr/bin/env bash' 'cp -R "${@: -2:1}." "${@: -1}"' >"$BATS_TEST_TMPDIR/bin/rsync"
  chmod +x "$BATS_TEST_TMPDIR/bin/rsync"
  echo kept >"$SOURCE/kept/SKILL.md"
  echo dropped >"$SOURCE/dropped/SKILL.md"
}

# Lets bats clean up the read-only skill directories.
teardown() {
  chmod -R u+w "$TEST_HOME"
}

# Enters the shell the way both agent shells do, with SOURCE as the repo's skills.
enter_shell() {
  env HOME="$TEST_HOME" PATH="$BATS_TEST_TMPDIR/bin:$PATH" TOOLS_DIR="$TOOLS" AGENTS_SKILLS_DIR="$SOURCE" \
    AGENT_ENV_CONFIG_DIR="$BATS_TEST_TMPDIR/config" SKIP_AGENT_SETUP=true \
    bash -c 'cd "$1" && source "$2"' _ "$BATS_TEST_TMPDIR/checkout" "$TOOLS/setup-shared-shell.sh"
}

# Plants a skill installed by another source, or by an earlier install.
plant() {
  mkdir -p "$TARGET/$1"
  echo "$1" >"$TARGET/$1/SKILL.md"
}

@test "a skill deleted from the repo is removed on the next entry" {
  enter_shell
  [ -f "$TARGET/dropped/SKILL.md" ]
  mv "$SOURCE/dropped" "$BATS_TEST_TMPDIR/dropped-from-repo"
  chmod 0555 "$TARGET/kept" "$TARGET/dropped"
  enter_shell
  [ ! -e "$TARGET/dropped" ]
  [ -f "$TARGET/kept/SKILL.md" ]
}

@test "skills from other sources are left untouched" {
  plant other
  plant mojo-create-pull-request
  enter_shell
  mv "$SOURCE/dropped" "$BATS_TEST_TMPDIR/dropped-from-repo"
  enter_shell
  [ -f "$TARGET/other/SKILL.md" ]
}

@test "the stale fsm-era skills are removed when no manifest exists yet" {
  plant mojo-create-pull-request
  plant mojo-update-pull-request
  plant mojo-review-response
  plant other
  chmod 0555 "$TARGET/mojo-review-response"
  enter_shell
  [ ! -e "$TARGET/mojo-create-pull-request" ]
  [ ! -e "$TARGET/mojo-update-pull-request" ]
  [ ! -e "$TARGET/mojo-review-response" ]
  [ -f "$TARGET/other/SKILL.md" ]
  [ -f "$TARGET/kept/SKILL.md" ]
}

@test "a symlink in place of a dropped skill is left alone" {
  enter_shell
  mv "$SOURCE/dropped" "$BATS_TEST_TMPDIR/dropped-from-repo"
  rm -r "$TARGET/dropped"
  mkdir -p "$BATS_TEST_TMPDIR/own"
  echo own >"$BATS_TEST_TMPDIR/own/SKILL.md"
  chmod 0555 "$BATS_TEST_TMPDIR/own"
  ln -s "$BATS_TEST_TMPDIR/own" "$TARGET/dropped"
  enter_shell
  [ -L "$TARGET/dropped" ]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/own")" = 555 ]
  chmod u+w "$BATS_TEST_TMPDIR/own"
}
