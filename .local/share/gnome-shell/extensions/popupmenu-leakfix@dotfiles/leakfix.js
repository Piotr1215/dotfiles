// Pure patch logic, kept free of shell imports so a plain node test can
// exercise it. extension.js passes the real classes in.
//
// GNOME Shell 46 PopupMenuBase.addMenuItem() wires a submenu with
//   menuItem.menu.connectObject('active-changed', ..., this)
// and nothing ever calls menuItem.menu.disconnectObject(this) when the item is
// destroyed. The SignalManager keeps a tracker keyed by the dead submenu, the
// tracker keeps the submenu, the submenu keeps its item and subtree. On a menu
// that rebuilds its items (Argos every second, tailscale-status on refresh)
// this grew to 30k dead PopupSubMenuMenuItems and 250k wrapped GObjects in one
// day, and every GC then stalled the compositor for 300-500ms.
// Upstream main still carries the same code (checked 2026-09-09).

/**
 * Wrap addMenuItem so a submenu item releases its tracker when destroyed.
 * @param {Function} PopupMenuBase - class whose prototype gets patched
 * @param {Function} PopupSubMenuMenuItem - class of items that leak
 * @returns {Function} the original addMenuItem, for uninstall
 */
export function install(PopupMenuBase, PopupSubMenuMenuItem) {
    const proto = PopupMenuBase.prototype;
    const orig = proto.addMenuItem;
    proto.addMenuItem = function (menuItem, position) {
        orig.call(this, menuItem, position);
        if (menuItem instanceof PopupSubMenuMenuItem)
            menuItem.connect('destroy', () => menuItem.menu.disconnectObject(this));
    };
    return orig;
}

/**
 * Restore the original addMenuItem.
 * @param {Function} PopupMenuBase - class whose prototype was patched
 * @param {Function} orig - value returned by install()
 */
export function uninstall(PopupMenuBase, orig) {
    PopupMenuBase.prototype.addMenuItem = orig;
}
