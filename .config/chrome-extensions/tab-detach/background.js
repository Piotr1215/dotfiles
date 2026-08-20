// Existing extensions can only move a tab out. They cannot put it back where it
// came from, because they never record where that was. "Next window" is a guess
// that lands wrong as soon as a third window exists. This records the origin
// window and index at detach time so reattach is exact.
//
// Shared by the chrome and firefox builds. `browser` is firefox's promise
// namespace; chrome's MV3 `chrome` returns promises too when no callback is
// passed, so one file serves both.

const api = globalThis.browser ?? chrome;
const key = id => `origin${id}`;

// A browser cannot run a local command, so the tiling goes out through a native
// messaging host. Sent after the window already exists, which is why nothing
// here has to wait or retry.
const HOST = 'com.dotfiles.layouts';
const layout = n => api.runtime.sendNativeMessage(HOST, { layout: n }).catch(() => {});

async function detach(tab) {
	const siblings = await api.tabs.query({ windowId: tab.windowId });
	if (siblings.length < 2) return; // a lone tab has nothing to detach from
	await api.storage.session.set({
		[key(tab.id)]: { windowId: tab.windowId, index: tab.index }
	});
	await api.windows.create({ tabId: tab.id, focused: true });
	layout('3'); // browser+browser, same as ctrl+alt+d
}

async function reattach(tab) {
	const origin = (await api.storage.session.get(key(tab.id)))[key(tab.id)];
	let target = origin?.windowId;
	if (target !== undefined) {
		try { await api.windows.get(target); } catch { target = undefined; }
	}
	if (target === undefined) {
		// Origin window was closed. Fall back to any other normal window.
		const windows = await api.windows.getAll({ windowTypes: ['normal'] });
		target = windows.find(w => w.id !== tab.windowId)?.id;
		if (target === undefined) return;
	}
	await api.tabs.move(tab.id, { windowId: target, index: origin?.index ?? -1 });
	await api.tabs.update(tab.id, { active: true });
	await api.windows.update(target, { focused: true });
	await api.storage.session.remove(key(tab.id));
	layout('5'); // max browser, same as ctrl+alt+e
}

const actions = { 'detach-tab': detach, 'reattach-tab': reattach };

api.commands.onCommand.addListener(async command => {
	const [tab] = await api.tabs.query({ active: true, currentWindow: true });
	if (tab && actions[command]) await actions[command](tab);
});

// Firefox will not give an extension command a chord the browser already uses,
// and ctrl+d is its bookmark key. The page may swallow it though, so the
// firefox build's content script catches ctrl+d and relays it here.
api.runtime.onMessage.addListener((message, sender) => {
	if (sender.tab && actions[message?.command]) actions[message.command](sender.tab);
});
