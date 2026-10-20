#!/usr/bin/env bats
# Tests for the argos script launcher in
# .local/share/gnome-shell/extensions/argos@pew.worldwidemann.com/spawn.js

EXT="$(cd "$BATS_TEST_DIRNAME/../../.local/share/gnome-shell/extensions/argos@pew.worldwidemann.com" && pwd)"

setup() {
    WORK="$(mktemp -d)"
    # Builtins only, so the script forks nothing and every clone in a trace is
    # the launcher's own.
    printf '#!/bin/sh\necho "line one"\necho "version=$ARGOS_VERSION"\necho oops >&2\n' >"$WORK/script.sh"
    chmod +x "$WORK/script.sh"
    # GNOME Shell wraps the GLib.spawn_* calls with a child_setup that forces
    # fork(), so the runner poisons them: the launcher must not touch them.
    cat >"$WORK/run.js" <<EOF
import GLib from 'gi://GLib';
import {spawnWithCallback} from 'file://$EXT/spawn.js';
for (const f of ['spawn_async', 'spawn_async_with_pipes', 'spawn_async_with_fds', 'spawn_async_with_pipes_and_fds'])
    GLib[f] = () => { throw new Error('GLib.' + f + ' called'); };
const loop = new GLib.MainLoop(null, false);
spawnWithCallback(null, [ARGV[0] ?? '$WORK/script.sh'], [...GLib.get_environ(), 'ARGOS_VERSION=2'], 0, null, out => {
    print(out.trimEnd());
    loop.quit();
});
loop.run();
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "spawn.js and utilities.js parse as ES modules" {
    run node --check "$EXT/spawn.js"
    [ "$status" -eq 0 ]
    run node --check "$EXT/utilities.js"
    [ "$status" -eq 0 ]
}

@test "utilities.js still routes spawnWithCallback through spawn.js" {
    run grep -c "^export {spawnWithCallback} from './spawn.js';" "$EXT/utilities.js"
    [ "$output" = "1" ]
}

@test "callback gets the script's stdout and env, without GLib.spawn_* and without stderr" {
    command -v gjs >/dev/null || skip "gjs not installed"
    run timeout 20 gjs -m "$WORK/run.js"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'line one\nversion=2')" ]
}

@test "callback fires at stdout EOF, not when the script exits" {
    command -v gjs >/dev/null || skip "gjs not installed"
    printf '#!/bin/sh\necho early\nexec >&-\nsleep 3\n' >"$WORK/closes.sh"
    chmod +x "$WORK/closes.sh"
    local start=$SECONDS
    run timeout 20 gjs -m "$WORK/run.js" "$WORK/closes.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "early" ]
    [ $((SECONDS - start)) -lt 2 ]
}

@test "the script is launched through vfork, never fork" {
    command -v gjs >/dev/null || skip "gjs not installed"
    strace -o /dev/null true 2>/dev/null || skip "strace not usable"
    run timeout 20 strace -f -e trace=clone,clone3,vfork,fork -o "$WORK/trace" gjs -m "$WORK/run.js"
    [ "$status" -eq 0 ]
    grep -q 'CLONE_VFORK' "$WORK/trace"
    ! grep -Eq 'clone\(.*SIGCHLD|vfork\(|fork\(' "$WORK/trace"
}
