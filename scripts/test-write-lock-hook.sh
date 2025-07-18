#!/usr/bin/env bash
# Test script for the write-lock hook
set -e

HOOK_SCRIPT="/home/decoder/dev/dotfiles/scripts/mcp-write-lock-guard.sh"
LOCK_FILE="/var/tmp/mcp-write-lock.json"

echo "=== Testing MCP Write Lock Hook ==="

# Function to test hook with given input
test_hook() {
    local test_name="$1"
    local input_json="$2"
    local expected_exit_code="$3"
    
    echo -e "\n--- Test: $test_name ---"
    echo "Input: $input_json"
    
    # Run hook and capture exit code
    if echo "$input_json" | "$HOOK_SCRIPT"; then
        exit_code=0
    else
        exit_code=$?
    fi
    
    echo "Exit code: $exit_code (expected: $expected_exit_code)"
    
    if [ "$exit_code" -eq "$expected_exit_code" ]; then
        echo "✅ PASS"
    else
        echo "❌ FAIL: Expected exit code $expected_exit_code but got $exit_code"
        exit 1
    fi
}

# Clean up any existing lock file
rm -f "$LOCK_FILE"

# Test 1: Non-write tool should always pass
test_hook "Non-write tool (Bash)" \
    '{"tool_name": "Bash", "session_id": "test-123"}' \
    0

# Test 2: Write tool with no lock file should pass
test_hook "Write tool with no lock file" \
    '{"tool_name": "Write", "session_id": "test-123"}' \
    0

# Test 3: Create lock file (unlocked)
echo '{"locked": false, "lockedBy": null, "reason": null}' > "$LOCK_FILE"
test_hook "Write tool with unlocked state" \
    '{"tool_name": "Edit", "session_id": "test-123"}' \
    0

# Test 4: Create lock file (locked)
echo '{"locked": true, "lockedBy": "minimi-presence", "reason": "Minimi is watching"}' > "$LOCK_FILE"
test_hook "Write tool with locked state (non-fat-owl)" \
    '{"tool_name": "MultiEdit", "session_id": "test-123"}' \
    2

# Test 5: Test fat-owl bypass
# First create a fake fat-owl agent tracking file
FAT_OWL_FILE="/tmp/claude_agent_test-fat-owl.json"
cat > "$FAT_OWL_FILE" <<EOF
{
  "agent_id": "agent-test-fat-owl",
  "agent_name": "fat-owl",
  "session_id": "test-fat-owl-session",
  "registered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

test_hook "Write tool with locked state (fat-owl)" \
    '{"tool_name": "Write", "session_id": "test-fat-owl-session"}' \
    0

# Clean up
rm -f "$FAT_OWL_FILE"
rm -f "$LOCK_FILE"

echo -e "\n=== All tests passed! ==="