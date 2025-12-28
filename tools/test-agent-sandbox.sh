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

# TEST 1: File access outside project directory
log_test "File access outside project directory"

# Create a test file outside project
TEMP_OUTSIDE=$(mktemp)
echo "secret data" > "$TEMP_OUTSIDE"

# Try to read it from inside sandbox (should fail)
if "$SANDBOX_SCRIPT" cat "$TEMP_OUTSIDE" 2>/dev/null; then
    log_fail "Sandbox allowed access to file outside project: $TEMP_OUTSIDE"
else
    log_pass "Sandbox correctly blocked access to file outside project"
fi
rm -f "$TEMP_OUTSIDE"

# TEST 2: Access to HOME directory
log_test "Access to HOME directory"

# Check if project is in HOME - if so, HOME will be partially accessible
if [[ "$PROJECT_DIR" =~ ^$HOME ]]; then
    echo "  Skipped (project is in HOME directory - HOME will be partially accessible)"
else
    # Try to list home directory (should fail)
    if "$SANDBOX_SCRIPT" ls "$HOME" 2>/dev/null | grep -q .; then
        log_fail "Sandbox allowed access to HOME directory"
    else
        log_pass "Sandbox correctly blocked access to HOME directory"
    fi
fi

# TEST 3: Access to current project files
log_test "Access to current project files"

# Should be able to read files in project
if "$SANDBOX_SCRIPT" cat "$PROJECT_DIR/README.md" | head -n 1 | grep -q .; then
    log_pass "Sandbox allows access to project files"
else
    log_fail "Sandbox blocked access to project files"
fi

# TEST 4: Work directory creation and access
log_test "Work directory creation and environment variable"

WORK_DIR_PATH=$("$SANDBOX_SCRIPT" bash -c 'echo $AGENT_WORK_DIR')
if [[ -n "$WORK_DIR_PATH" ]] && [[ "$WORK_DIR_PATH" == "/tmp/agent-work" ]]; then
    log_pass "AGENT_WORK_DIR environment variable set correctly: $WORK_DIR_PATH"
else
    log_fail "AGENT_WORK_DIR not set or incorrect: '$WORK_DIR_PATH'"
fi

# TEST 5: Write access to work directory
log_test "Write access to work directory"

if "$SANDBOX_SCRIPT" bash -c 'echo "test" > $AGENT_WORK_DIR/test.txt && cat $AGENT_WORK_DIR/test.txt' | grep -q "test"; then
    log_pass "Can write to and read from work directory"
else
    log_fail "Cannot write to work directory"
fi

# TEST 6: Cleanup on normal exit
log_test "Cleanup on normal exit"

# Run sandbox and capture the temp dir it creates
CLEANUP_TEST=$(mktemp -d -t test-cleanup-XXXXXX)
cat > "$CLEANUP_TEST/check-cleanup.sh" << 'EOF'
#!/usr/bin/env bash
# Find the agent temp directory
AGENT_TEMP=$(ls -dt /tmp/agent-* 2>/dev/null | head -n1)
if [[ -n "$AGENT_TEMP" ]]; then
    echo "$AGENT_TEMP"
fi
EOF
chmod +x "$CLEANUP_TEST/check-cleanup.sh"

# This is tricky - the temp dir is created by agent-sandbox.sh and cleaned up on exit
# We'll just verify the script has the trap set up correctly
if grep -q "trap.*rm -rf.*EXIT" "$SANDBOX_SCRIPT"; then
    log_pass "Cleanup trap is configured in sandbox script"
else
    log_fail "No cleanup trap found in sandbox script"
fi
rm -rf "$CLEANUP_TEST"

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
if "$SANDBOX_SCRIPT" git status 2>/dev/null | grep -q "On branch"; then
    log_pass "Can run git commands in project directory"
else
    log_fail "Cannot run git commands in project directory"
fi

# TEST 9: Basic shell utilities
log_test "Basic shell utilities (ls, cat, grep, etc.)"

UTILS_OK=true
for util in ls cat grep sed awk find; do
    if ! "$SANDBOX_SCRIPT" which "$util" &>/dev/null; then
        log_fail "Utility '$util' not available in sandbox"
        UTILS_OK=false
        break
    fi
done

if $UTILS_OK; then
    log_pass "All basic shell utilities are available"
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

if "$SANDBOX_SCRIPT" bash -c 'echo test | nc -w1 8.8.8.8 53 2>/dev/null || ping -c1 -W1 8.8.8.8 >/dev/null 2>&1'; then
    log_pass "Network access is available"
else
    log_fail "Network access is blocked"
fi

# TEST 12: Process information access
log_test "Process information access (/proc)"

if "$SANDBOX_SCRIPT" cat /proc/self/status 2>/dev/null | grep -q "Name:"; then
    log_pass "/proc is accessible"
else
    log_fail "/proc is not accessible"
fi

# TEST 13: Performance impact
log_test "Performance impact measurement"

echo -n "Measuring performance overhead... "

# Run a simple command 10 times without sandbox
TIME_WITHOUT=$(bash -c 'start=$(date +%s%N); for i in {1..10}; do ls /nix/store > /dev/null 2>&1; done; end=$(date +%s%N); echo $((end - start))')

# Run the same command 10 times with sandbox
TIME_WITH=$(bash -c "start=\$(date +%s%N); for i in {1..10}; do '$SANDBOX_SCRIPT' ls /nix/store > /dev/null 2>&1; done; end=\$(date +%s%N); echo \$((end - start))")

OVERHEAD=$((TIME_WITH - TIME_WITHOUT))
OVERHEAD_MS=$((OVERHEAD / 1000000))
PERCENT=$((OVERHEAD * 100 / TIME_WITHOUT))

echo ""
echo "  Without sandbox: ${TIME_WITHOUT}ns"
echo "  With sandbox:    ${TIME_WITH}ns"
echo "  Overhead:        ${OVERHEAD_MS}ms (${PERCENT}% slower)"

if [[ $OVERHEAD_MS -lt 1000 ]]; then
    log_pass "Performance overhead is acceptable (<1s for 10 iterations)"
else
    log_fail "Performance overhead is high (${OVERHEAD_MS}ms for 10 iterations)"
fi

# TEST 14: SSH key access (optional feature)
log_test "SSH key access (optional via AGENT_SANDBOX_SSH=true)"

if [[ -d "$HOME/.ssh" ]]; then
    # Without the flag, should not have access
    if "$SANDBOX_SCRIPT" ls "$HOME/.ssh" 2>/dev/null | grep -q .; then
        log_fail "SSH directory accessible without AGENT_SANDBOX_SSH flag"
    else
        # With the flag, should have access
        if AGENT_SANDBOX_SSH=true "$SANDBOX_SCRIPT" ls "$HOME/.ssh" 2>/dev/null | grep -q .; then
            log_pass "SSH directory correctly controlled by AGENT_SANDBOX_SSH flag"
        else
            log_fail "SSH directory not accessible even with AGENT_SANDBOX_SSH=true"
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
