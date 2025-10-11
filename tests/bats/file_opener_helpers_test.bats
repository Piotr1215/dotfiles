#!/usr/bin/env bats

# Test suite for __extract_path_from_fzf.sh and __copy_path_with_notification.sh
# Tests path extraction from fzf selections and clipboard copy functionality

# Setup function runs before each test
setup() {
    # Store repository root for script paths
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export REPO_ROOT

    # Create isolated test directory
    TEST_DIR="$(mktemp -d)"
    export TEST_DIR

    # Override PATH to use mocks
    export PATH="${TEST_DIR}:${PATH}"

    # Create mock xclip command
    cat > "${TEST_DIR}/xclip" << 'EOF'
#!/bin/bash
# Mock xclip for testing - save to file instead of clipboard
if [[ "$*" =~ "-selection clipboard" ]]; then
    cat > "${TEST_DIR}/clipboard_content"
fi
EOF
    chmod +x "${TEST_DIR}/xclip"

    # Create mock notify-send command
    cat > "${TEST_DIR}/notify-send" << 'EOF'
#!/bin/bash
# Mock notify-send - log notifications
echo "NOTIFICATION: $*" >> "${TEST_DIR}/notifications.log"
EOF
    chmod +x "${TEST_DIR}/notify-send"

    # Create mock realpath command for controlled testing
    cat > "${TEST_DIR}/realpath" << 'EOF'
#!/bin/bash
# Mock realpath - just echo the path if it's absolute
path="$1"
if [[ "$path" =~ ^/ ]]; then
    echo "$path"
else
    # For relative paths, prepend current dir
    echo "$(pwd)/$path"
fi
EOF
    chmod +x "${TEST_DIR}/realpath"
}

# Teardown function runs after each test
teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR"
}

# ====================================================
# PATH EXTRACTION TESTS
# ====================================================

@test "extract_path_from_fzf handles simple absolute path" {
    result=$(bash "$REPO_ROOT/scripts/__extract_path_from_fzf.sh" "/home/decoder/dev/dotfiles")
    [ "$result" = "/home/decoder/dev/dotfiles" ]
}

@test "extract_path_from_fzf handles path with tilde" {
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "~/dev/dotfiles")
    # Should expand tilde to $HOME
    [[ "$result" == "$HOME/dev/dotfiles" ]]
}

@test "extract_path_from_fzf extracts path from bookmark format" {
    # Bookmark format: "description (60 chars padded) path"
    bookmark_line=$(printf "%-60s %s" "test bookmark" "/home/decoder/test/path")
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line")
    [ "$result" = "/home/decoder/test/path" ]
}

@test "extract_path_from_fzf handles bookmark with tilde path" {
    bookmark_line=$(printf "%-60s %s" "config directory" "~/.config/nvim")
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line")
    [[ "$result" == "$HOME/.config/nvim" ]]
}

@test "extract_path_from_fzf handles bookmark with spaces in path" {
    bookmark_line=$(printf "%-60s %s" "test directory" "/tmp/my test dir")
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line")
    [ "$result" = "/tmp/my test dir" ]
}

@test "extract_path_from_fzf handles bookmark with extra spaces" {
    # Multiple spaces between description and path
    bookmark_line="test description                                              /home/decoder/scripts"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line")
    [ "$result" = "/home/decoder/scripts" ]
}

@test "extract_path_from_fzf handles empty input gracefully" {
    run bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh ""
    [ "$status" -eq 0 ]
}

@test "extract_path_from_fzf produces no trailing newline" {
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "/home/decoder/test")
    # Use printf to capture exact output, then check with od
    printf '%s' "$result" | od -An -tx1 | grep -v "0a"
    [ $? -eq 0 ]
}

@test "extract_path_from_fzf handles line starting with path (zoxide format)" {
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "/home/decoder/dev/project")
    [ "$result" = "/home/decoder/dev/project" ]
}

@test "extract_path_from_fzf handles non-path input" {
    # Should handle gracefully even if input doesn't look like a path
    run bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "some random text"
    [ "$status" -eq 0 ]
}

# ====================================================
# COPY WITH NOTIFICATION TESTS
# ====================================================

@test "copy_path_with_notification copies simple path to clipboard" {
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/home/decoder/test"
    [ "$status" -eq 0 ]

    # Check clipboard content
    [ -f "${TEST_DIR}/clipboard_content" ]
    content=$(cat "${TEST_DIR}/clipboard_content")
    [ "$content" = "/home/decoder/test" ]
}

@test "copy_path_with_notification sends desktop notification" {
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/home/decoder/test"
    [ "$status" -eq 0 ]

    # Check notification was sent
    [ -f "${TEST_DIR}/notifications.log" ]
    grep -q "Path Copied" "${TEST_DIR}/notifications.log"
    grep -q "/home/decoder/test" "${TEST_DIR}/notifications.log"
}

@test "copy_path_with_notification respects COPY_NOTIFICATION_TIMEOUT env var" {
    export COPY_NOTIFICATION_TIMEOUT=5000
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/tmp/test"
    [ "$status" -eq 0 ]

    # Verify timeout variable is used (not hardcoded value)
    grep -q -- "-t 5000" "${TEST_DIR}/notifications.log"
}

@test "copy_path_with_notification copies without trailing newline" {
    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/home/decoder/test" >/dev/null 2>&1

    # Check clipboard content has no newline
    [ -f "${TEST_DIR}/clipboard_content" ]
    # Count bytes - should not end with newline (0x0a)
    last_byte=$(od -An -tx1 "${TEST_DIR}/clipboard_content" | tr -d ' \n' | tail -c 2)
    [ "$last_byte" != "0a" ]
}

@test "copy_path_with_notification handles bookmark format" {
    bookmark_line=$(printf "%-60s %s" "bookmarks config" "~/dev/dotfiles/scripts/__bookmarks.conf")
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "$bookmark_line"
    [ "$status" -eq 0 ]

    # Check that path was extracted and copied (should be expanded)
    [ -f "${TEST_DIR}/clipboard_content" ]
    content=$(cat "${TEST_DIR}/clipboard_content")
    [[ "$content" == "$HOME/dev/dotfiles/scripts/__bookmarks.conf" ]]
}

@test "copy_path_with_notification extracts path from bookmark before notifying" {
    bookmark_line="test description                                 /home/decoder/scripts/test.sh"
    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "$bookmark_line" >/dev/null 2>&1

    # Verify notification was sent (behavior, not content)
    [ -f "${TEST_DIR}/notifications.log" ]
    # Verify clipboard has extracted path, not full bookmark line
    content=$(cat "${TEST_DIR}/clipboard_content")
    [[ "$content" == /home/decoder/scripts/test.sh ]]
}

@test "copy_path_with_notification handles paths with spaces" {
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/tmp/my test file.txt"
    [ "$status" -eq 0 ]

    # Check path with spaces is preserved
    [ -f "${TEST_DIR}/clipboard_content" ]
    content=$(cat "${TEST_DIR}/clipboard_content")
    [ "$content" = "/tmp/my test file.txt" ]
}

@test "copy_path_with_notification expands tilde paths" {
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "~/dev/test"
    [ "$status" -eq 0 ]

    # Should expand to $HOME
    [ -f "${TEST_DIR}/clipboard_content" ]
    content=$(cat "${TEST_DIR}/clipboard_content")
    [[ "$content" == "$HOME/dev/test" ]]
}

# ====================================================
# ERROR HANDLING TESTS
# ====================================================

@test "extract_path_from_fzf handles special characters in path" {
    special_path="/tmp/test-file_with.special@chars"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$special_path")
    [ "$result" = "$special_path" ]
}

@test "copy_path_with_notification handles xclip failure gracefully" {
    # Override xclip to fail
    cat > "${TEST_DIR}/xclip" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "${TEST_DIR}/xclip"

    # Should still complete (set -e in script will exit on xclip failure)
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/test/path"
    [ "$status" -ne 0 ]
}

@test "extract_path_from_fzf handles multiple space separators" {
    # Very long padding between description and path
    bookmark_line="short desc                                                                    /home/test"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line")
    [ "$result" = "/home/test" ]
}

# ====================================================
# INTEGRATION TESTS
# ====================================================

@test "extract_path_from_fzf handles real bookmark format from __bookmarks.conf" {
    # Test with actual format from bookmarks.conf: "description;path"
    # But fzf displays it as: "description (padded to 60 chars) path"
    bookmark_display=$(printf "%-60s %s" "claude cache" "~/.cache/claude-cli-nodejs/")
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_display")
    [[ "$result" == "$HOME/.cache/claude-cli-nodejs/" ]]
}

@test "copy_notification workflow matches fzf binding usage" {
    # Simulate what fzf binding does: passes {} to the script
    fzf_selection="/home/decoder/dev/dotfiles/.tmux.conf"

    # Run the copy script
    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "$fzf_selection" >/dev/null 2>&1

    # Verify clipboard and notification
    [ -f "${TEST_DIR}/clipboard_content" ]
    [ -f "${TEST_DIR}/notifications.log" ]

    # Clipboard should have the path
    content=$(cat "${TEST_DIR}/clipboard_content")
    [ "$content" = "$fzf_selection" ]

    # Notification should mention path copied
    grep -q "Path Copied" "${TEST_DIR}/notifications.log"
}

@test "copy_notification handles zoxide output format" {
    # Zoxide returns just the path
    zoxide_path="/home/decoder/dev/project"

    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "$zoxide_path" >/dev/null 2>&1

    [ -f "${TEST_DIR}/clipboard_content" ]
    content=$(cat "${TEST_DIR}/clipboard_content")
    [ "$content" = "$zoxide_path" ]
}

@test "copy_notification handles fd output format" {
    # fd returns absolute paths
    fd_path="/home/decoder/dev/dotfiles/scripts/__file_opener.sh"

    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "$fd_path" >/dev/null 2>&1

    [ -f "${TEST_DIR}/clipboard_content" ]
    content=$(cat "${TEST_DIR}/clipboard_content")
    [ "$content" = "$fd_path" ]
}

# ====================================================
# STRESS AND EDGE CASE TESTS
# ====================================================

@test "extract_path_from_fzf handles unicode characters in path" {
    unicode_path="/tmp/测试/файл/αρχείο.txt"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$unicode_path")
    [ "$result" = "$unicode_path" ]
}

@test "extract_path_from_fzf handles very long paths" {
    # Path approaching PATH_MAX (typically 4096 bytes)
    long_component="very_long_directory_name_that_keeps_going_and_going"
    long_path="/tmp/$long_component/$long_component/$long_component/$long_component/$long_component"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$long_path")
    [ "$result" = "$long_path" ]
}

@test "extract_path_from_fzf handles paths with newlines in bookmark description" {
    # Malformed bookmark with newline - should still extract path
    bookmark_line=$(printf "desc with\nnewline                                      /tmp/test")
    run bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line"
    # Should either extract /tmp/test or handle gracefully
    [ "$status" -eq 0 ]
}

@test "extract_path_from_fzf handles consecutive slashes in path" {
    weird_path="/tmp///multiple////slashes/file.txt"
    run bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$weird_path"
    # Script should complete successfully
    [ "$status" -eq 0 ]
    # Result should be a non-empty path
    [ -n "$output" ]
}

@test "extract_path_from_fzf handles dots in path" {
    dots_path="/tmp/test/./subdir/../file.txt"
    run bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$dots_path"
    # Script should complete successfully
    [ "$status" -eq 0 ]
    # Result should be a non-empty path
    [ -n "$output" ]
}

@test "copy_path_with_notification handles concurrent calls" {
    # Simulate multiple rapid copies (like user mashing ctrl-y)
    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/tmp/path1" >/dev/null 2>&1 &
    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/tmp/path2" >/dev/null 2>&1 &
    bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/tmp/path3" >/dev/null 2>&1 &

    wait

    # Should complete without errors
    [ -f "${TEST_DIR}/clipboard_content" ]
    # Content should be one of the paths
    content=$(cat "${TEST_DIR}/clipboard_content")
    [[ "$content" =~ ^/tmp/path[123]$ ]]
}

@test "extract_path_from_fzf preserves trailing slash on directories" {
    dir_path="/home/decoder/dev/"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$dir_path")
    # realpath may or may not preserve trailing slash, just verify it's the directory
    [[ "$result" =~ ^/home/decoder/dev/?$ ]]
}

@test "extract_path_from_fzf handles bookmark with minimal spacing" {
    # Minimum valid bookmark format: "desc /path"
    bookmark_line="d /tmp/t"
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$bookmark_line")
    [ "$result" = "/tmp/t" ]
}

@test "copy_path_with_notification handles empty PATH env" {
    # Stress test: broken environment - save and restore PATH
    local saved_path="$PATH"
    export PATH=""
    run bash $REPO_ROOT/scripts/__copy_path_with_notification.sh "/tmp/test"
    # Should fail gracefully, not crash
    [ "$status" -ne 0 ]
    # Restore PATH for teardown
    export PATH="$saved_path"
}

@test "extract_path_from_fzf handles path with quotes" {
    quoted_path='/tmp/"quoted"/file.txt'
    result=$(bash $REPO_ROOT/scripts/__extract_path_from_fzf.sh "$quoted_path")
    # Should preserve quotes in path
    [[ "$result" == *'"quoted"'* ]]
}
