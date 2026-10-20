#!/usr/bin/env bats
# Tests for the rebuild-only-when-needed patch in
# .local/share/gnome-shell/extensions/argos@pew.worldwidemann.com/button.js:
# an unchanged run is skipped, a label change leaves the menu alone, and a
# changed menu is built only once it is open.

EXT="$(cd "$BATS_TEST_DIRNAME/../../.local/share/gnome-shell/extensions/argos@pew.worldwidemann.com" && pwd)"

setup() {
    command -v gjs >/dev/null || skip "gjs not installed"
    WORK="$(mktemp -d)"
    # The real button.js, with its shell imports pointed at stubs: plain gjs
    # cannot load St, Clutter or the shell's resource:// modules.
    sed -e "s|'resource:///org/gnome/shell/ui/panelMenu.js'|'./stub-panelMenu.js'|" \
        -e "s|'resource:///org/gnome/shell/ui/popupMenu.js'|'./stub-popupMenu.js'|" \
        -e "s|'./lineview.js'|'./stub-lineview.js'|" \
        -e "s|'./menuitem.js'|'./stub-menuitem.js'|" \
        -e "s|'./utilities.js'|'./stub-utilities.js'|" \
        "$EXT/button.js" >"$WORK/button.js"

    # The menu counts rebuilds and, like the shell's, tells its
    # open-state-changed handlers (menu, open).
    cat >"$WORK/stub-panelMenu.js" <<'EOF'
import GObject from 'gi://GObject';
export const rebuilds = {count: 0};
export const Button = GObject.registerClass({Signals: {destroy: {}}},
class StubButton extends GObject.Object {
    _init() {
        super._init();
        const handlers = [];
        this.menu = {
            isOpen: false,
            items: [],
            removeAll() { rebuilds.count++; this.items = []; },
            addMenuItem(item) { this.items.push(item); },
            get numMenuItems() { return this.items.length; },
            connect(signal, fn) { if (signal === 'open-state-changed') handlers.push(fn); },
            setOpen(open) { this.isOpen = open; for (const fn of handlers) fn(this, open); },
        };
    }
});
EOF
    cat >"$WORK/stub-popupMenu.js" <<'EOF'
export class PopupSeparatorMenuItem {}
export class PopupSubMenuMenuItem { constructor() { this.menu = {}; } }
export class PopupMenuItem { connect() {} }
EOF
    cat >"$WORK/stub-lineview.js" <<'EOF'
export const shown = [];
export default class StubLineView {
    setMarkup(markup) { shown.push(markup); }
    setLine(line) { shown.push(line.text); }
}
EOF
    cat >"$WORK/stub-menuitem.js" <<'EOF'
export default class StubMenuItem {
    constructor(button, line) { this.text = line.text; }
}
EOF
    # spawnWithCallback hands back whatever the test queued, synchronously.
    cat >"$WORK/stub-utilities.js" <<'EOF'
export const script = {output: ""};
export function spawnWithCallback(cwd, argv, envp, flags, setup, callback) {
    callback(script.output);
}
export function parseLine(lineString) {
    const [text, attrs = ""] = lineString.split(" | ");
    return {
        text,
        isSeparator: /^-{3,}$/.test(text.trim()),
        menuLevel: 0,
        dropdown: /dropdown=false/.test(attrs) ? "false" : "true",
    };
}
export function getActor(obj) {
    obj._stubActor ??= {add_child() {}, visible: true};
    return obj._stubActor;
}
EOF
    # Each argument is one run's output, or OPEN / CLOSE for the menu.
    # Prints the rebuild count after each step, the labels set in order (the
    # first is argos's placeholder), and the item texts of the built menu.
    cat >"$WORK/run.js" <<'EOF'
import Gio from 'gi://Gio';
import ArgosButton from './button.js';
import {rebuilds} from './stub-panelMenu.js';
import {shown} from './stub-lineview.js';
import {script} from './stub-utilities.js';
const steps = ARGV.map(s => s.replaceAll("\\n", "\n"));
script.output = steps[0];
const button = new ArgosButton(Gio.File.new_for_path('/x/test.1s.sh'), {updateInterval: null});
const counts = [rebuilds.count];
for (const step of steps.slice(1)) {
    if (step === 'OPEN' || step === 'CLOSE') {
        button.menu.setOpen(step === 'OPEN');
    } else {
        script.output = step;
        button.update();
    }
    counts.push(rebuilds.count);
}
print(counts.join(' '));
print(shown.slice(1).join(','));
print(button.menu.items.filter(i => i.text).map(i => i.text).join(','));
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "an unchanged output touches neither the label nor the menu" {
    run timeout 20 gjs -m "$WORK/run.js" 'K\n---\nacct' 'K\n---\nacct' 'K\n---\nacct'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1 1 1" ]
    [ "${lines[1]}" = "K" ]
}

@test "a label change updates the label and leaves the menu alone" {
    run timeout 20 gjs -m "$WORK/run.js" 'A\n---\nacct' 'B\n---\nacct' 'C\n---\nacct'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1 1 1" ]
    [ "${lines[1]}" = "A,B,C" ]
}

@test "a label change neither rebuilds an open menu nor leaves one owed for the next open" {
    run timeout 20 gjs -m "$WORK/run.js" 'A\n---\nacct' 'B\n---\nacct' OPEN 'C\n---\nacct'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1 1 1 1" ]
    [ "${lines[1]}" = "A,B,C" ]
}

@test "a menu change while closed waits for the menu to open, then builds the latest" {
    run timeout 20 gjs -m "$WORK/run.js" 'K\n---\na' 'K\n---\nb' 'K\n---\nc' OPEN OPEN
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1 1 1 2 2" ]
    [ "${lines[2]}" = "c" ]
}

@test "a menu change while open is built at once" {
    run timeout 20 gjs -m "$WORK/run.js" 'K\n---\na' OPEN 'K\n---\nb' CLOSE
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1 1 2 2" ]
    [ "${lines[2]}" = "b" ]
}

@test "a cycling button restarts its cycle every run without rebuilding the menu" {
    run timeout 20 gjs -m "$WORK/run.js" 'on\noff\n---\na' 'on\noff\n---\na' 'on\noff\n---\na'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1 1 1" ]
    [ "${lines[1]}" = "on,on,on" ]
    [ "${lines[2]}" = "on,off,a" ]
}

@test "after a cycle ends, an unchanged output is skipped again" {
    run timeout 20 gjs -m "$WORK/run.js" 'on\noff' 'K' 'K' 'K'
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "on,K" ]
}
