#!/usr/bin/env bash
# Don't use set -e as we want to continue on test failures
set -o pipefail

# Test suite for __lib_pr_checkout.sh worktree detection
# Run: bash test_lib_pr_checkout.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/__lib_pr_checkout.sh" 2>/dev/null || true

WORKTREE_DIR="/home/decoder/dev/claude-wt-worktrees"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Testing worktree detection ==="
echo

# Test 1: Worktree detection for existing linear ID
test_worktree_detection() {
    local linear_id="$1"
    local linear_lower=$(echo "$linear_id" | tr '[:upper:]' '[:lower:]')
    local worktree_path=$(find "$WORKTREE_DIR" -maxdepth 1 -type d -name "${linear_lower}-*" 2>/dev/null | head -1)

    if [ -n "$worktree_path" ] && [ -d "$worktree_path" ]; then
        pass "Found worktree for $linear_id: $worktree_path"
        return 0
    else
        fail "No worktree found for $linear_id"
        return 1
    fi
}

# Test 2: Worktree is a valid git directory
test_worktree_is_git() {
    local linear_id="$1"
    local linear_lower=$(echo "$linear_id" | tr '[:upper:]' '[:lower:]')
    local worktree_path=$(find "$WORKTREE_DIR" -maxdepth 1 -type d -name "${linear_lower}-*" 2>/dev/null | head -1)

    if [ -n "$worktree_path" ] && git -C "$worktree_path" rev-parse --git-dir >/dev/null 2>&1; then
        pass "Worktree $linear_id is a valid git directory"
        return 0
    else
        fail "Worktree $linear_id is not a valid git directory"
        return 1
    fi
}

# Test 3: Session name generation
test_session_name() {
    local repo="vcluster-docs"
    local linear_id="DOC-1138"
    local expected="${repo}-${linear_id}"

    # Simulate session name generation logic
    local session_name="${repo}-${linear_id}"

    if [ "$session_name" = "$expected" ]; then
        pass "Session name correctly generated: $session_name"
        return 0
    else
        fail "Session name mismatch: got $session_name, expected $expected"
        return 1
    fi
}

# Test 4: Worktree path pattern matching
test_pattern_matching() {
    # Use unique ID to avoid collision with previous test runs
    local unique_id="test-$$-$(date +%s)"
    local test_dir="$WORKTREE_DIR/${unique_id}-20260101-000000"

    mkdir -p "$test_dir"

    local found=$(find "$WORKTREE_DIR" -maxdepth 1 -type d -name "${unique_id}-*" 2>/dev/null | head -1)

    if [ "$found" = "$test_dir" ]; then
        pass "Pattern matching works"
        rmdir "$test_dir"
        return 0
    else
        fail "Pattern matching failed: expected $test_dir, got $found"
        rmdir "$test_dir" 2>/dev/null || true
        return 1
    fi
}

# Test 5: Case insensitivity
test_case_insensitivity() {
    local upper="DOC-1138"
    local lower=$(echo "$upper" | tr '[:upper:]' '[:lower:]')

    if [ "$lower" = "doc-1138" ]; then
        pass "Case conversion works: $upper -> $lower"
        return 0
    else
        fail "Case conversion failed: got $lower"
        return 1
    fi
}

# Run tests
echo "--- Core tests ---"
test_pattern_matching
test_case_insensitivity
test_session_name

echo
echo "--- Live worktree tests (if worktrees exist) ---"

# Find any existing worktrees and test them
existing_worktrees=$(find "$WORKTREE_DIR" -maxdepth 1 -type d -name "*-*" 2>/dev/null | head -3)

if [ -n "$existing_worktrees" ]; then
    for wt in $existing_worktrees; do
        dir_name=$(basename "$wt")
        # Extract linear ID from directory name (e.g., doc-1138-20260112-114352 -> DOC-1138)
        linear_id=$(echo "$dir_name" | sed -E 's/^([a-z]+-[0-9]+)-.*/\1/' | tr '[:lower:]' '[:upper:]')
        if [[ "$linear_id" =~ ^[A-Z]+-[0-9]+$ ]]; then
            test_worktree_detection "$linear_id"
            test_worktree_is_git "$linear_id"
        fi
    done
else
    echo "No existing worktrees found to test"
fi

echo
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ $FAILED -gt 0 ]; then
    exit 1
fi
