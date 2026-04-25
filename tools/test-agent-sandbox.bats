#!/usr/bin/env bats
# Tests for tools/agent-sandbox.sh

SANDBOX_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/agent-sandbox.sh"
PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_file() {
  # Locate bwrap from PATH or Nix store so tests work regardless of which
  # shell environment invokes bats.
  if [[ "$(uname -s)" == "Linux" ]] && [[ -z "${BWRAP_PATH:-}" ]]; then
    if command -v bwrap &>/dev/null; then
      export BWRAP_PATH="$(command -v bwrap)"
    else
      for candidate in /nix/store/*-bubblewrap-*/bin/bwrap; do
        if [[ -x "$candidate" ]]; then
          export BWRAP_PATH="$candidate"
          break
        fi
      done
    fi
  fi
}

@test "sandbox blocks access to HOME root" {
  local secret="$HOME/sandbox-test-secret-$$.txt"
  echo "secret data" > "$secret"
  run "$SANDBOX_SCRIPT" cat "$secret"
  rm -f "$secret"
  [ "$status" -ne 0 ]
}

@test "sandbox blocks access to HOME sibling directories" {
  local sibling="$HOME/.sandbox-test-sibling-$$"
  mkdir -p "$sibling"
  echo "sibling data" > "$sibling/secret.txt"
  run "$SANDBOX_SCRIPT" cat "$sibling/secret.txt"
  rm -rf "$sibling"
  [ "$status" -ne 0 ]
}

@test "sandbox allows access to project files" {
  run "$SANDBOX_SCRIPT" cat "$PROJECT_DIR/README.md"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "AGENT_WORK_DIR is set inside sandbox" {
  run "$SANDBOX_SCRIPT" bash -c 'echo "$AGENT_WORK_DIR"'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "sandbox can write to and read from AGENT_WORK_DIR" {
  run "$SANDBOX_SCRIPT" bash -c 'echo "test" > "$AGENT_WORK_DIR/test.txt" && cat "$AGENT_WORK_DIR/test.txt"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"test"* ]]
}

@test "sandbox can write to /tmp" {
  local tmpfile
  tmpfile=$(mktemp -u -t sandbox-test-XXXXXX)
  run "$SANDBOX_SCRIPT" bash -c "echo test > $tmpfile"
  [ "$status" -eq 0 ]
  [ -f "$tmpfile" ]
  rm -f "$tmpfile"
}

@test "git is accessible inside sandbox" {
  run "$SANDBOX_SCRIPT" git --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"git version"* ]]
}

@test "git commands work in project directory" {
  run "$SANDBOX_SCRIPT" git -C "$PROJECT_DIR" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ ("On branch"|"HEAD detached"|"nothing to commit") ]]
}

@test "basic shell utilities are available" {
  for util in ls cat grep sed awk find; do
    run "$SANDBOX_SCRIPT" bash -c "command -v $util"
    [ "$status" -eq 0 ]
  done
}

@test "/nix/store is accessible and read-only" {
  run "$SANDBOX_SCRIPT" ls /nix/store
  [ "$status" -eq 0 ]
  run "$SANDBOX_SCRIPT" bash -c 'touch /nix/store/test 2>/dev/null'
  [ "$status" -ne 0 ]
}

@test "network access works" {
  if ! command -v curl &>/dev/null; then
    skip "curl not available"
  fi
  run "$SANDBOX_SCRIPT" curl -s --max-time 5 https://www.google.com
  [ "$status" -eq 0 ]
}

@test "/proc is accessible on Linux" {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "not applicable on $(uname -s)"
  fi
  run "$SANDBOX_SCRIPT" cat /proc/self/status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Name:"* ]]
}


@test "personal SSH keys require AGENT_SANDBOX_SSH=true" {
  if [[ ! -d "$HOME/.ssh" ]]; then
    skip "no ~/.ssh directory"
  fi
  local key="$HOME/.ssh/test-personal-key-$$"
  echo "personal key" > "$key"

  run "$SANDBOX_SCRIPT" cat "$key"
  local default_status=$status
  rm -f "$key"
  echo "personal key" > "$key"

  run env AGENT_SANDBOX_SSH=true "$SANDBOX_SCRIPT" cat "$key"
  local ssh_status=$status
  rm -f "$key"

  [ "$default_status" -ne 0 ]
  [ "$ssh_status" -eq 0 ]
}

@test ".git/config is read-only inside sandbox" {
  run "$SANDBOX_SCRIPT" bash -c "git -C '$PROJECT_DIR' config user.name 'Sandbox Test'"
  [ "$status" -ne 0 ]
}

@test "git identity resolves through symlinked gitconfig include chain" {
  local test_home dotfiles_dir nested_config real_gitconfig
  test_home=$(mktemp -d)
  dotfiles_dir=$(mktemp -d)
  nested_config="$dotfiles_dir/.gitconfig-identity"
  real_gitconfig="$dotfiles_dir/.gitconfig"

  printf '[user]\n  email = test@example.com\n' > "$nested_config"
  printf '[include]\n  path = %s\n' "$nested_config" > "$real_gitconfig"
  ln -s "$real_gitconfig" "$test_home/.gitconfig"

  mkdir -p "$test_home/.config/nixsmith"
  echo "dummy" > "$test_home/.config/nixsmith/github-token"

  # Mount the temp dirs explicitly so macOS sandbox-exec profile allows access.
  # HOME override alone is insufficient on macOS because the profile bakes in
  # HOME_DIR at launch time from the real HOME, not the overridden value.
  run env HOME="$test_home" \
    SANDBOX_EXTRA_RO="$test_home:$dotfiles_dir" \
    "$SANDBOX_SCRIPT" bash -c 'git config user.email'
  rm -rf "$test_home" "$dotfiles_dir"

  echo "# output: $output" >&3
  [ "$status" -eq 0 ]
  [ "$output" = "test@example.com" ]
}

@test "IN_AGENT_SANDBOX is set inside sandbox" {
  run "$SANDBOX_SCRIPT" bash -c 'echo "$IN_AGENT_SANDBOX"'
  echo "# output: $output" >&3
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "SANDBOX_EXTRA_RW grants write access to extra paths" {
  local extra_dir
  extra_dir=$(mktemp -d)
  run env SANDBOX_EXTRA_RW="$extra_dir" "$SANDBOX_SCRIPT" bash -c "echo ok > $extra_dir/test.txt && cat $extra_dir/test.txt"
  rm -rf "$extra_dir"
  echo "# output: $output" >&3
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "agent config directories are writable" {
  mkdir -p "$HOME/.config/opencode" "$HOME/.claude"
  run "$SANDBOX_SCRIPT" bash -c 'touch ~/.config/opencode/sandbox-test.txt && rm ~/.config/opencode/sandbox-test.txt'
  [ "$status" -eq 0 ]
  run "$SANDBOX_SCRIPT" bash -c 'touch ~/.claude/sandbox-test.txt && rm ~/.claude/sandbox-test.txt'
  [ "$status" -eq 0 ]
}

@test "multi-hop symlink chain is accessible inside sandbox" {
  local chain_dir
  chain_dir=$(mktemp -d)
  echo "content" > "$chain_dir/real-file"
  ln -s "$chain_dir/real-file" "$chain_dir/link-c"
  ln -s "$chain_dir/link-c"    "$chain_dir/link-b"
  ln -s "$chain_dir/link-b"    "$chain_dir/link-a"

  run env SANDBOX_EXTRA_RO="$chain_dir/link-a" "$SANDBOX_SCRIPT" cat "$chain_dir/link-a"
  rm -rf "$chain_dir"

  echo "# output: $output" >&3
  [ "$status" -eq 0 ]
  [ "$output" = "content" ]
}
