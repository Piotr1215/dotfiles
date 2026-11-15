// PROJECT: window_manager
// GNOME Shell extension: DBus window tiling + focus dimmer.
// Runs inside Mutter — synchronous operations, signal-driven dimming.

import Meta from 'gi://Meta';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const IFACE = `
<node>
  <interface name="org.gnome.Shell.Extensions.TileHelper">
    <method name="Tile">
      <arg type="s" direction="in" name="wmClass"/>
      <arg type="i" direction="in" name="x"/>
      <arg type="i" direction="in" name="y"/>
      <arg type="i" direction="in" name="width"/>
      <arg type="i" direction="in" name="height"/>
      <arg type="b" direction="out" name="success"/>
    </method>
    <method name="Maximize">
      <arg type="s" direction="in" name="wmClass"/>
      <arg type="b" direction="out" name="success"/>
    </method>
    <method name="Minimize">
      <arg type="s" direction="in" name="wmClass"/>
      <arg type="b" direction="out" name="success"/>
    </method>
    <method name="TileXid">
      <arg type="u" direction="in" name="xid"/>
      <arg type="i" direction="in" name="x"/>
      <arg type="i" direction="in" name="y"/>
      <arg type="i" direction="in" name="width"/>
      <arg type="i" direction="in" name="height"/>
      <arg type="b" direction="out" name="success"/>
    </method>
    <method name="MaximizeXid">
      <arg type="u" direction="in" name="xid"/>
      <arg type="b" direction="out" name="success"/>
    </method>
    <method name="MinimizeXid">
      <arg type="u" direction="in" name="xid"/>
      <arg type="b" direction="out" name="success"/>
    </method>
    <method name="Debug">
      <arg type="s" direction="out" name="info"/>
    </method>
  </interface>
</node>`;

// Windows that participate in focus dimming
const PRESET_CLASSES = [
    'alacritty', 'navigator', 'librewolf', 'slack', 'code',
];

const DIM_EFFECT_NAME = 'tile-helper-dim';
const DIM_BRIGHTNESS = -0.3;

function _isPresetWindow(win) {
    if (win.get_window_type() !== Meta.WindowType.NORMAL) return false;
    const cls = (win.get_wm_class() || '').toLowerCase();
    const inst = (win.get_wm_class_instance() || '').toLowerCase();
    return PRESET_CLASSES.some(p => cls === p || inst === p);
}

function _findByClass(wmClass) {
    const target = wmClass.toLowerCase();
    return global.get_window_actors()
        .map(a => a.meta_window)
        .filter(w => w.get_window_type() === Meta.WindowType.NORMAL)
        .find(w => {
            const cls = (w.get_wm_class() || '').toLowerCase();
            const inst = (w.get_wm_class_instance() || '').toLowerCase();
            return cls === target || inst === target;
        });
}

function _findByXid(xid) {
    const hex = `0x${xid.toString(16)}`;
    return global.get_window_actors()
        .map(a => a.meta_window)
        .find(w => w.get_description() === hex);
}

// Placement is instant: skip the shell's next effect (minimize, unminimize,
// maximize or unmaximize) on this window. Call it only right before a state
// change that fires one, or the skip lingers and eats a later effect.
// Replaces the enable-animations toggle __layouts.sh flipped on every
// keypress, which gsd-xsettings broadcast to every GTK client: browsers read
// it as prefers-reduced-motion and restyled twice per layout.
function _skipEffect(win) {
    const actor = win.get_compositor_private();
    if (actor)
        Main.wm.skipNextEffect(actor);
}

function _unminimize(win) {
    if (!win.minimized) return;
    _skipEffect(win);
    win.unminimize();
}

function _maximize(win) {
    if (win.get_maximized() === Meta.MaximizeFlags.BOTH) return;
    _skipEffect(win);
    win.maximize(Meta.MaximizeFlags.BOTH);
}

function _minimize(win) {
    if (win.minimized) return;
    _skipEffect(win);
    win.minimize();
}

function _tileWindow(win, x, y, width, height) {
    if (!win) return false;
    _unminimize(win);
    if (win.get_maximized()) {
        _skipEffect(win);
        win.unmaximize(Meta.MaximizeFlags.BOTH);
    }
    // Callers (wmctrl/xdotool-based scripts) pass physical X11 pixels.
    // On a scaled monitor Mutter's move_resize_frame takes the POSITION in
    // logical coords (physical = logical * scale) while SIZE stays physical.
    // St scale_factor is the X11 UI scale (2 at 200%, 1 at 100%).
    // Divide only x/y by it; at 100% scale this is identity.
    const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor || 1;
    win.move_resize_frame(false, x / scale, y / scale, width, height);
    win.activate(global.get_current_time());
    return true;
}

export default class TileHelperExtension {
    enable() {
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(
            Gio.DBus.session,
            '/org/gnome/Shell/Extensions/TileHelper'
        );

        // Focus dimmer: react to focus changes instantly
        this._focusId = global.display.connect('notify::focus-window',
            () => this._updateDimming());
        this._wsId = global.workspace_manager.connect('active-workspace-changed',
            () => this._updateDimming());
    }

    disable() {
        // Remove all dim effects before disconnecting
        this._resetAllDimming();

        global.display.disconnect(this._focusId);
        global.workspace_manager.disconnect(this._wsId);
        this._focusId = null;
        this._wsId = null;

        this._dbus.unexport();
        this._dbus = null;
    }

    _updateDimming() {
        const focused = global.display.focus_window;
        const workspace = global.workspace_manager.get_active_workspace();

        // Find visible preset windows on current workspace
        const presetActors = global.get_window_actors().filter(a => {
            const w = a.meta_window;
            return _isPresetWindow(w) && !w.minimized
                && w.get_workspace() === workspace;
        });

        if (presetActors.length < 2) {
            // Single window or none — remove all dim effects
            presetActors.forEach(a => this._removeDim(a));
            return;
        }

        // Compare by description (XID hex) — GJS object identity is unreliable
        const focusedDesc = focused ? focused.get_description() : '';
        for (const actor of presetActors) {
            if (actor.meta_window.get_description() === focusedDesc)
                this._removeDim(actor);
            else
                this._applyDim(actor);
        }
    }

    _applyDim(actor) {
        if (actor.get_effect(DIM_EFFECT_NAME)) return;
        const effect = new Clutter.BrightnessContrastEffect();
        effect.set_brightness(DIM_BRIGHTNESS);
        actor.add_effect_with_name(DIM_EFFECT_NAME, effect);
    }

    _removeDim(actor) {
        const effect = actor.get_effect(DIM_EFFECT_NAME);
        if (effect) actor.remove_effect(effect);
    }

    _resetAllDimming() {
        for (const actor of global.get_window_actors()) {
            this._removeDim(actor);
        }
    }

    // --- DBus: class-based methods ---
    Tile(wmClass, x, y, width, height) {
        return _tileWindow(_findByClass(wmClass), x, y, width, height);
    }

    Maximize(wmClass) {
        const win = _findByClass(wmClass);
        if (!win) return false;
        _unminimize(win);
        _maximize(win);
        win.activate(global.get_current_time());
        return true;
    }

    Minimize(wmClass) {
        const win = _findByClass(wmClass);
        if (!win) return false;
        _minimize(win);
        return true;
    }

    // --- DBus: XID-based methods ---
    TileXid(xid, x, y, width, height) {
        return _tileWindow(_findByXid(xid), x, y, width, height);
    }

    MaximizeXid(xid) {
        const win = _findByXid(xid);
        if (!win) return false;
        _unminimize(win);
        _maximize(win);
        win.activate(global.get_current_time());
        return true;
    }

    MinimizeXid(xid) {
        const win = _findByXid(xid);
        if (!win) return false;
        _minimize(win);
        return true;
    }

    Debug() {
        const wins = global.get_window_actors()
            .map(a => a.meta_window)
            .filter(w => w.get_window_type() === Meta.WindowType.NORMAL);
        const lines = wins.map(w => {
            const desc = w.get_description();
            const cls = w.get_wm_class() || '';
            const inst = w.get_wm_class_instance() || '';
            return `desc="${desc}" class="${cls}" inst="${inst}" preset=${_isPresetWindow(w)}`;
        });
        return lines.join('\n');
    }
}
