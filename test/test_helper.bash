#!/usr/bin/env bash

# Test helper functions for __github_issue_sync.sh tests

# Load the main script without executing it
load_github_sync_functions() {
    # Source just the functions, not the main execution
    source <(sed '/^main$/,$d' /home/decoder/dev/dotfiles/scripts/__github_issue_sync.sh)
}

# Mock API responses using fixtures
mock_github_api() {
    local fixture_file="$1"
    cat > "${TEST_DIR}/gh" << EOF
#!/bin/bash
case "\$*" in
    *"search/issues"*)
        cat /home/decoder/dev/dotfiles/test/fixtures/${fixture_file}
        ;;
    *)
        echo "Mock GitHub API: \$*" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "${TEST_DIR}/gh"
}

mock_linear_api() {
    local fixture_file="$1"
    local http_code="${2:-200}"
    
    cat > "${TEST_DIR}/curl" << EOF
#!/bin/bash
if [[ "\$*" =~ "linear.app" ]]; then
    cat /home/decoder/dev/dotfiles/test/fixtures/${fixture_file}
    echo "${http_code}"
else
    /usr/bin/curl "\$@"
fi
EOF
    chmod +x "${TEST_DIR}/curl"
}

# Create test taskwarrior environment
setup_test_taskwarrior() {
    export TASKDATA="${TEST_DIR}/taskwarrior"
    mkdir -p "$TASKDATA"
    
    # Create minimal taskrc
    cat > "${TEST_DIR}/taskrc" << 'EOF'
data.location=${TASKDATA}
confirmation=no
EOF
    export TASKRC="${TEST_DIR}/taskrc"
}

# Verify temp file cleanup
verify_no_temp_files() {
    local temp_count
    temp_count=$(find /tmp -name "tmp.*" -user "$(whoami)" 2>/dev/null | wc -l)
    [ "$temp_count" -eq 0 ]
}

# Assert task command was called with specific arguments
assert_task_called_with() {
    local expected_args="$1"
    grep -q "$expected_args" "${TEST_DIR}/task_commands.log"
}

# Clean test environment
clean_test_env() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR TASKDATA TASKRC
}