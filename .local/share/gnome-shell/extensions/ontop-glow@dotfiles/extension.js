// PROJECT: window_manager
// GNOME Shell extension: glow around always-on-top windows.
//
// An on-top window looks like any other, so the only way to tell was opening
// its title-bar menu. This follows Mutter's own above state rather than a key,
// so Super+Shift+T, the title-bar "Always on Top" and wmctrl all light it.

import GObject from 'gi://GObject';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const GLOW_STYLE =
    'border: 3px solid rgba(189, 147, 249, 0.95);' +
    'border-radius: 8px;' +
    'box-shadow: 0 0 14px 3px rgba(189, 147, 249, 0.6);';

// Frame to outer border edge. Equal to the border width, so the line hugs the
// frame. The glow sits just below the window in the stack, so the window
// covers the inner half of the shadow and none of its own content.
const PAD = 3;

export default class OnTopGlowExtension extends Extension {
    enable() {
        this._watched = new Map();  // MetaWindow -> signal ids
        this._glows = new Map();    // MetaWindow -> {glow, actor, ids, actorId, binding}

        this._createdId = global.display.connect('window-created',
            (_display, win) => this._watch(win));
        // Any restack can put another window between a glow and its window.
        this._restackedId = global.display.connect('restacked',
            () => this._glows.forEach((_g, win) => this._restack(win)));

        for (const actor of global.get_window_actors())
            this._watch(actor.meta_window);
    }

    disable() {
        global.display.disconnect(this._createdId);
        global.display.disconnect(this._restackedId);
        for (const win of [...this._watched.keys()])
            this._unwatch(win);
        this._watched = null;
        this._glows = null;
    }

    _watch(win) {
        if (this._watched.has(win))
            return;
        this._watched.set(win, [
            win.connect('notify::above', () => this._sync(win)),
            // A window mapped already above has no actor at window-created
            // and never fires notify::above, so it is lit when first shown.
            win.connect('shown', () => this._sync(win)),
            win.connect('unmanaged', () => this._unwatch(win)),
        ]);
        this._sync(win);
    }

    _unwatch(win) {
        this._unglow(win);
        (this._watched.get(win) || []).forEach(id => win.disconnect(id));
        this._watched.delete(win);
    }

    _sync(win) {
        if (win.is_above())
            this._glow(win);
        else
            this._unglow(win);
    }

    _glow(win) {
        if (this._glows.has(win))
            return;
        const actor = win.get_compositor_private();
        if (!actor)
            return;

        const glow = new St.Widget({style: GLOW_STYLE, reactive: false});
        global.window_group.add_child(glow);
        const place = () => this._place(win, glow);
        this._glows.set(win, {
            glow,
            actor,
            ids: [
                win.connect('position-changed', place),
                win.connect('size-changed', place),
            ],
            actorId: actor.connect('destroy', () => this._unglow(win)),
            // Minimized, on another workspace, or mid-close: the window
            // actor hides and the glow goes with it.
            binding: actor.bind_property('visible', glow, 'visible',
                GObject.BindingFlags.SYNC_CREATE),
        });
        place();
        this._restack(win);
    }

    _unglow(win) {
        const g = this._glows.get(win);
        if (!g)
            return;
        g.ids.forEach(id => win.disconnect(id));
        g.actor.disconnect(g.actorId);
        g.binding.unbind();
        g.glow.destroy();
        this._glows.delete(win);
    }

    // Clipped to the window's monitor: side-by-side screens share an edge, and
    // an unclipped glow on a window touching it bleeds onto the other screen.
    _place(win, glow) {
        const frame = win.get_frame_rect();
        const mon = global.display.get_monitor_geometry(win.get_monitor());
        const x1 = Math.max(frame.x - PAD, mon.x);
        const y1 = Math.max(frame.y - PAD, mon.y);
        const x2 = Math.min(frame.x + frame.width + PAD, mon.x + mon.width);
        const y2 = Math.min(frame.y + frame.height + PAD, mon.y + mon.height);
        glow.set_position(x1, y1);
        glow.set_size(Math.max(0, x2 - x1), Math.max(0, y2 - y1));
    }

    _restack(win) {
        const g = this._glows.get(win);
        if (g && g.actor.get_parent() === global.window_group)
            global.window_group.set_child_below_sibling(g.glow, g.actor);
    }
}
