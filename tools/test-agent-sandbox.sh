#!/usr/bin/env bash
# Test script for agent-sandbox.sh
#
# Tests the following requirements:
# 1. Can agent access files outside project dir?
# 2. Does mktemp work directory get created?
# 3. Is cleanup reliable on exit?
# 4. Do agents have necessary tool access (git, editors)?
# 5. Performance impact measurement

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_SCRIPT="$SCRIPT_DIR/agent-sandbox.sh"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}[TEST $TESTS_RUN]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Check prerequisites
if [[ ! -x "$SANDBOX_SCRIPT" ]]; then
    echo "Error: $SANDBOX_SCRIPT not found or not executable"
    exit 1
fi

# Check if bwrap is available (either in PATH or nix store)
BWRAP_AVAILABLE=false
if command -v bwrap &>/dev/null; then
    BWRAP_AVAILABLE=true
else
    # Check nix store
    for candidate in /nix/store/*-bubblewrap-*/bin/bwrap; do
        if [[ -x "$candidate" ]]; then
            BWRAP_AVAILABLE=true
            break
        fi
    done
fi

if ! $BWRAP_AVAILABLE; then
    echo "Error: bubblewrap (bwrap) not found. Install with: nix-shell -p bubblewrap"
    exit 1
fi

echo "======================================"
echo "Agent Sandbox Validation Tests"
echo "======================================"
echo "Project dir: $PROJECT_DIR"
echo "Sandbox script: $SANDBOX_SCRIPT"
echo ""
echo "=== Pre-Sandbox Environment ==="
echo "HOST PATH: $PATH"
echo ""
echo "Utilities BEFORE sandbox:"
for util in ls cat grep sed awk find git; do
    command -v "$util" 2>/dev/null && echo "  $util: $(command -v $util)" || echo "  $util: NOT FOUND"
done
echo ""
echo "=== Testing Sandbox Environment ==="
echo "Sandbox PATH: $("$SANDBOX_SCRIPT" bash -c 'echo $PATH')"
echo ""
echo "Utilities INSIDE sandbox:"
for util in ls cat grep sed awk find git; do
    "$SANDBOX_SCRIPT" bash -c "command -v $util" 2>/dev/null && echo "  $util: $("$SANDBOX_SCRIPT" bash -c "command -v $util")" || echo "  $util: NOT FOUND"
done
echo ""
echo "Debugging: Is /nix mounted in sandbox?"
"$SANDBOX_SCRIPT" bash -c 'ls -la /nix 2>&1' | head -3
echo ""
echo "Debugging: Can we directly execute ls from /nix/store?"
"$SANDBOX_SCRIPT" bash -c '/nix/store/d75200gb22v7p0703h5jrkgg8bqydk5q-coreutils-9.8/bin/ls --version 2>&1' | head -1
echo ""
echo "=== Running Tests ==="
echo ""

# TEST 1: File access outside project directory (except /tmp)
log_test "File access outside project directory (except /tmp)"

# /tmp is intentionally mounted for agent work directory
# Test that HOME root is NOT accessible even if project is a subdirectory of HOME
TEMP_OUTSIDE="$HOME/sandbox-test-secret.txt"
echo "secret data" > "$TEMP_OUTSIDE"

# Try to read it from inside sandbox (should fail even if project is in HOME)
if "$SANDBOX_SCRIPT" cat "$TEMP_OUTSIDE" 2>/dev/null; then
    log_fail "Sandbox allowed access to HOME root: $TEMP_OUTSIDE"
    rm -f "$TEMP_OUTSIDE"
else
    log_pass "Sandbox correctly blocked access to HOME root (only project dir accessible)"
    rm -f "$TEMP_OUTSIDE"
fi

# TEST 2: Access to HOME directory siblings
log_test "Access to HOME directory siblings"

# Even if project is in HOME, sandbox should only mount the project path
# Test access to a HOME sibling directory that's not the project
TEST_SIBLING="$HOME/.sandbox-test-sibling-dir"
mkdir -p "$TEST_SIBLING"
echo "sibling data" > "$TEST_SIBLING/secret.txt"

# Try to access the sibling directory (should fail)
if "$SANDBOX_SCRIPT" cat "$TEST_SIBLING/secret.txt" 2>/dev/null; then
    log_fail "Sandbox allowed access to HOME sibling directory: $TEST_SIBLING"
    rm -rf "$TEST_SIBLING"
else
    log_pass "Sandbox correctly blocked access to HOME siblings (only project path accessible)"
    rm -rf "$TEST_SIBLING"
fi

# TEST 3: Access to current project files
log_test "Access to current project files"

# Should be able to read files in project
if "$SANDBOX_SCRIPT" cat "$PROJECT_DIR/README.md" | head -n 1 | grep -q .; then
    log_pass "Sandbox allows access to project files"
else
    log_fail "Sandbox blocked access to project files"
fi

# TEST 4: Work directory environment variable
log_test "Work directory environment variable"

WORK_DIR_PATH=$("$SANDBOX_SCRIPT" bash -c 'echo $AGENT_WORK_DIR')
if [[ -n "$WORK_DIR_PATH" ]] && [[ "$WORK_DIR_PATH" == "/tmp" ]]; then
    log_pass "AGENT_WORK_DIR environment variable set correctly: $WORK_DIR_PATH"
else
    log_fail "AGENT_WORK_DIR not set or incorrect: '$WORK_DIR_PATH' (expected: /tmp)"
fi

# TEST 5: Write access to work directory
log_test "Write access to work directory"

if "$SANDBOX_SCRIPT" bash -c 'echo "test" > $AGENT_WORK_DIR/test.txt && cat $AGENT_WORK_DIR/test.txt' | grep -q "test"; then
    log_pass "Can write to and read from work directory"
else
    log_fail "Cannot write to work directory"
fi

# TEST 6: /tmp write access
log_test "/tmp write access"

# Verify sandbox can write to /tmp (needed for agent work directory)
TEMP_TEST_FILE=$(mktemp -u -t sandbox-test-XXXXXX)
"$SANDBOX_SCRIPT" bash -c "echo test > $TEMP_TEST_FILE"

if [[ -f "$TEMP_TEST_FILE" ]]; then
    rm -f "$TEMP_TEST_FILE"
    log_pass "Sandbox can write to /tmp"
else
    log_fail "Cannot write to /tmp from sandbox"
fi

# TEST 7: Git access
log_test "Git tool access"

if "$SANDBOX_SCRIPT" git --version 2>/dev/null | grep -q "git version"; then
    log_pass "Git is accessible in sandbox"
else
    log_fail "Git is not accessible in sandbox"
fi

# TEST 8: Can run git commands in project
log_test "Git commands in project directory"

cd "$PROJECT_DIR"
git_output=$("$SANDBOX_SCRIPT" git status 2>&1)
if echo "$git_output" | grep -qE "(On branch|HEAD detached|nothing to commit)"; then
    log_pass "Can run git commands in project directory"
else
    log_fail "Cannot run git commands. Output: $git_output"
fi

# TEST 9: Basic shell utilities
log_test "Basic shell utilities (ls, cat, grep, etc.)"

UTILS_OK=true
missing_utils=()
for util in ls cat grep sed awk find; do
    if ! "$SANDBOX_SCRIPT" bash -c "command -v $util" &>/dev/null; then
        missing_utils+=("$util")
        UTILS_OK=false
    fi
done

if $UTILS_OK; then
    log_pass "All basic shell utilities are available"
else
    sandbox_path=$("$SANDBOX_SCRIPT" bash -c 'echo $PATH')
    log_fail "Missing utilities: ${missing_utils[*]}. Sandbox PATH: $sandbox_path"
fi

# TEST 10: /nix store access (read-only)
log_test "/nix store access (read-only)"

# Check if /nix/store is accessible (temporarily disable pipefail for grep)
set +o pipefail
NIX_ACCESSIBLE=$("$SANDBOX_SCRIPT" ls /nix/store 2>/dev/null | grep -q . && echo "yes" || echo "no")
set -o pipefail

if [[ "$NIX_ACCESSIBLE" == "yes" ]]; then
    # Verify it's read-only by trying to write
    if ! "$SANDBOX_SCRIPT" bash -c 'touch /nix/store/test 2>/dev/null'; then
        log_pass "/nix store is accessible and read-only"
    else
        log_fail "/nix store is writable (should be read-only)"
    fi
else
    log_fail "/nix store is not accessible"
fi

# TEST 11: Network access
log_test "Network access"

# Use curl instead of ping (ping requires CAP_NET_RAW which may not be available in CI)
if command -v curl &>/dev/null; then
    if "$SANDBOX_SCRIPT" curl -s --max-time 5 https://www.google.com &>/dev/null; then
        log_pass "Network access is working"
    else
        log_fail "Network access failed (curl to google.com failed)"
    fi
else
    echo "  Skipped (curl not available)"
fi

# TEST 12: Process information access
log_test "Process information access (/proc)"

if "$SANDBOX_SCRIPT" cat /proc/self/status 2>/dev/null | grep -q "Name:"; then
    log_pass "/proc is accessible"
else
    log_fail "/proc is not accessible"
fi

# TEST 13: Sandbox startup performance
log_test "Sandbox startup performance (10 iterations)"

echo -n "Measuring startup overhead... "

# Run a simple command 10 times without sandbox
TIME_WITHOUT=$(bash -c 'start=$(date +%s%N); for i in {1..10}; do ls /nix/store > /dev/null 2>&1; done; end=$(date +%s%N); echo $((end - start))')

# Run the same command 10 times with sandbox (measures startup cost, not runtime)
TIME_WITH=$(bash -c "start=\$(date +%s%N); for i in {1..10}; do '$SANDBOX_SCRIPT' ls /nix/store > /dev/null 2>&1; done; end=\$(date +%s%N); echo \$((end - start))")

OVERHEAD=$((TIME_WITH - TIME_WITHOUT))
OVERHEAD_MS=$((OVERHEAD / 1000000))
OVERHEAD_PER_START=$((OVERHEAD_MS / 10))
PERCENT=$((OVERHEAD * 100 / TIME_WITHOUT))

echo ""
echo "  Without sandbox: ${TIME_WITHOUT}ns ($(($TIME_WITHOUT / 10000000))ms per iteration)"
echo "  With sandbox:    ${TIME_WITH}ns ($(($TIME_WITH / 10000000))ms per iteration)"
echo "  Startup overhead: ${OVERHEAD_PER_START}ms per sandbox start"
echo "  Total overhead:   ${OVERHEAD_MS}ms (${PERCENT}% slower for 10 starts)"

if [[ $OVERHEAD_MS -lt 1000 ]]; then
    log_pass "Sandbox startup overhead acceptable (<1s for 10 iterations, ~${OVERHEAD_PER_START}ms per start)"
else
    log_fail "Sandbox startup overhead high (${OVERHEAD_MS}ms for 10 iterations, ~${OVERHEAD_PER_START}ms per start)"
fi

# TEST 14: SSH key access control
log_test "SSH key access control"

if [[ -d "$HOME/.ssh" ]]; then
    # Sandbox mounts agent-* keys by default (agent-github, agent-gitea, etc.) for git operations
    # AGENT_SANDBOX_SSH=true mounts the full ~/.ssh directory including personal keys
    
    # Create a test personal key file
    TEST_KEY="$HOME/.ssh/test-personal-key"
    echo "personal key" > "$TEST_KEY"
    
    # Default behavior: personal keys should NOT be accessible
    if "$SANDBOX_SCRIPT" cat "$TEST_KEY" 2>/dev/null | grep -q "personal"; then
        log_fail "Personal SSH keys accessible by default (should require AGENT_SANDBOX_SSH=true)"
        rm -f "$TEST_KEY"
    else
        # With AGENT_SANDBOX_SSH=true: personal keys SHOULD be accessible
        if AGENT_SANDBOX_SSH=true "$SANDBOX_SCRIPT" cat "$TEST_KEY" 2>/dev/null | grep -q "personal"; then
            log_pass "Personal keys require AGENT_SANDBOX_SSH=true (agent keys always available)"
            rm -f "$TEST_KEY"
        else
            log_fail "Personal keys not accessible even with AGENT_SANDBOX_SSH=true"
            rm -f "$TEST_KEY"
        fi
    fi
else
    echo "  Skipped (no ~/.ssh directory)"
fi

# Summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Tests run:    $TESTS_RUN"
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
else
    echo "Tests failed: $TESTS_FAILED"
fi
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
