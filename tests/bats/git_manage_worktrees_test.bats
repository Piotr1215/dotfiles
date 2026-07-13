#!/usr/bin/env bats

# Test suite for __git_manage_worktrees.sh
#
# Focus: the main (primary) worktree must NEVER be deletable. A regression here
# once did `rm -rf` on the loft-prod main clone via the prune fallback path.

SCRIPT="/home/decoder/dev/dotfiles/scripts/__git_manage_worktrees.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    MAIN="${TEST_DIR}/main"
    LINKED="${TEST_DIR}/linked"

    git init -q "$MAIN"
    git -C "$MAIN" -c user.email=t@t.io -c user.name=tester \
        commit -q --allow-empty -m init
    git -C "$MAIN" worktree add -q -b feature "$LINKED" >/dev/null 2>&1

    export TEST_DIR MAIN LINKED SCRIPT
}

teardown() {
    [ -n "${TEST_DIR:-}" ] && rm -rf "$TEST_DIR"
}

@test "is_main_worktree tells the main worktree apart from a linked one" {
    run bash -c '
        cd "$MAIN"
        source "$SCRIPT"
        if is_main_worktree "$MAIN";   then echo "MAIN=main";     else echo "MAIN=linked";   fi
        if is_main_worktree "$LINKED"; then echo "LINKED=main";   else echo "LINKED=linked"; fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAIN=main"* ]]
    [[ "$output" == *"LINKED=linked"* ]]
}

@test "remove_worktree_entry refuses the main worktree and leaves it intact" {
    run bash -c '
        cd "$MAIN"
        source "$SCRIPT"
        remove_worktree_entry "$MAIN" "master"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"REFUSING to remove main worktree"* ]]
    # The real clone and its git dir must survive untouched.
    [ -d "$MAIN" ]
    [ -e "$MAIN/.git" ]
}

@test "remove_worktree_entry still removes a genuine linked worktree" {
    run bash -c '
        cd "$MAIN"
        source "$SCRIPT"
        remove_worktree_entry "$LINKED" "feature"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed worktree"* ]]
    [ ! -d "$LINKED" ]
}

@test "is_main_worktree is not fooled by a trailing slash on the main path" {
    run bash -c '
        cd "$MAIN"
        source "$SCRIPT"
        if is_main_worktree "$MAIN/"; then echo "guarded"; else echo "UNGUARDED"; fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"guarded"* ]]
}
