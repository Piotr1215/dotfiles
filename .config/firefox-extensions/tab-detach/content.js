// Ctrl+D is firefox's bookmark chord and an extension command cannot claim it,
// but a page can: preventDefault on keydown stops the bookmark dialog for every
// chord firefox does not reserve (it reserves ctrl+t, ctrl+w, ctrl+n and a few
// more, not ctrl+d). Capture phase on window, registered at document_start, so
// it runs before the page's own handlers and whatever they stop.
//
// Limits: does nothing on about: pages, where content scripts cannot run, or
// when focus is in the URL bar, which is chrome, not content.
window.addEventListener('keydown', event => {
	if (!event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) return;
	if (event.code !== 'KeyD') return;
	event.preventDefault();
	event.stopImmediatePropagation();
	browser.runtime.sendMessage({ command: 'detach-tab' });
}, true);
