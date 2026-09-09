import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {install, uninstall} from './leakfix.js';

export default class PopupMenuLeakFix extends Extension {
    enable() {
        this._orig = install(PopupMenu.PopupMenuBase, PopupMenu.PopupSubMenuMenuItem);
    }

    disable() {
        uninstall(PopupMenu.PopupMenuBase, this._orig);
        this._orig = null;
    }
}
