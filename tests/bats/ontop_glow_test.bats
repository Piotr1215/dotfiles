#!/usr/bin/env bats
# Tests for .local/share/gnome-shell/extensions/ontop-glow@dotfiles

EXT="$BATS_TEST_DIRNAME/../../.local/share/gnome-shell/extensions/ontop-glow@dotfiles"

# Import extension.js under node with gi:// and resource:// stubbed out, so the
# pure geometry can run without GNOME Shell.
load_extension() {
    node --input-type=module -e "
        import {register} from 'node:module';
        register('data:text/javascript,' + encodeURIComponent(\`
            export async function resolve(spec, ctx, next) {
                if (spec.startsWith('gi://'))
                    return {shortCircuit: true, url: 'data:text/javascript,export default {}'};
                if (spec.startsWith('resource://'))
                    return {shortCircuit: true, url: 'data:text/javascript,export class Extension {}'};
                return next(spec, ctx);
            }\`));
        const {default: OnTopGlow} = await import('$EXT/extension.js');
        const ext = new OnTopGlow();
        $1
    "
}

@test "metadata uuid matches the directory name" {
    run jq -r .uuid "$EXT/metadata.json"
    [ "$status" -eq 0 ]
    [ "$output" = "ontop-glow@dotfiles" ]
}

@test "extension.js parses as an ES module" {
    run node --check "$EXT/extension.js"
    [ "$status" -eq 0 ]
}

@test "the glow hugs the frame by the pad on every side" {
    run load_extension "
        globalThis.global = {display: {get_monitor_geometry: () => ({x: 0, y: 0, width: 2560, height: 1600})}};
        const win = {get_frame_rect: () => ({x: 100, y: 200, width: 400, height: 300}), get_monitor: () => 0};
        const glow = {set_position(x, y) { this.pos = [x, y]; }, set_size(w, h) { this.size = [w, h]; }};
        ext._place(win, glow);
        console.log(glow.pos.join(','), glow.size.join(','));
    "
    [ "$status" -eq 0 ]
    [ "$output" = "97,197 406,306" ]
}

@test "a window touching the shared screen edge does not glow onto the other screen" {
    run load_extension "
        globalThis.global = {display: {get_monitor_geometry: () => ({x: 0, y: 0, width: 2560, height: 1600})}};
        const win = {get_frame_rect: () => ({x: 2160, y: 200, width: 400, height: 300}), get_monitor: () => 0};
        const glow = {set_position(x, y) { this.pos = [x, y]; }, set_size(w, h) { this.size = [w, h]; }};
        ext._place(win, glow);
        console.log(glow.pos.join(','), glow.size.join(','));
    "
    [ "$status" -eq 0 ]
    [ "$output" = "2157,197 403,306" ]
}
