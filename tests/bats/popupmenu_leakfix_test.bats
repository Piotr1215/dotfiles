#!/usr/bin/env bats
# Tests for .local/share/gnome-shell/extensions/popupmenu-leakfix@dotfiles

EXT="$BATS_TEST_DIRNAME/../../.local/share/gnome-shell/extensions/popupmenu-leakfix@dotfiles"

@test "metadata uuid matches the directory name" {
    run jq -r .uuid "$EXT/metadata.json"
    [ "$status" -eq 0 ]
    [ "$output" = "popupmenu-leakfix@dotfiles" ]
}

@test "extension.js and leakfix.js parse as ES modules" {
    run node --check "$EXT/extension.js"
    [ "$status" -eq 0 ]
    run node --check "$EXT/leakfix.js"
    [ "$status" -eq 0 ]
}

@test "destroying a submenu item disconnects its tracker from the parent menu" {
    run node --input-type=module -e "
        import {install} from '$EXT/leakfix.js';
        class Base { addMenuItem(item) { item.added = true; } }
        class Sub {
            constructor() { this.handlers = []; this.menu = { released: null, disconnectObject(o) { this.released = o; } }; }
            connect(sig, fn) { this.handlers.push([sig, fn]); }
            destroy() { this.handlers.forEach(([s, fn]) => s === 'destroy' && fn()); }
        }
        install(Base, Sub);
        const parent = new Base(); const item = new Sub();
        parent.addMenuItem(item);
        if (!item.added) throw new Error('original addMenuItem not called');
        if (item.menu.released !== null) throw new Error('released before destroy');
        item.destroy();
        if (item.menu.released !== parent) throw new Error('tracker not released on destroy');
        console.log('ok');
    "
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "plain items are passed through untouched" {
    run node --input-type=module -e "
        import {install} from '$EXT/leakfix.js';
        class Base { addMenuItem(item) { item.added = true; } }
        class Sub {}
        install(Base, Sub);
        const item = { connect() { throw new Error('connect called on plain item'); } };
        new Base().addMenuItem(item);
        console.log(item.added);
    "
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "uninstall restores the original addMenuItem" {
    run node --input-type=module -e "
        import {install, uninstall} from '$EXT/leakfix.js';
        class Base { addMenuItem() {} }
        const before = Base.prototype.addMenuItem;
        const orig = install(Base, class {});
        if (Base.prototype.addMenuItem === before) throw new Error('not patched');
        uninstall(Base, orig);
        console.log(Base.prototype.addMenuItem === before);
    "
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}
