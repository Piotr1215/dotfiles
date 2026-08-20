// Existing extensions can only move a tab out. They cannot put it back where it
// came from, because they never record where that was. "Next window" is a guess
// that lands wrong as soon as a third window exists. This records the origin
// window and index at detach time so reattach is exact.

const key = id => `origin${id}`;

// Chrome cannot run a local command, so the tiling goes out through a native
// messaging host. Sent after the window already exists, which is why nothing
// here has to wait or retry.
const HOST = 'com.dotfiles.layouts';
const layout = n =>
	chrome.runtime.sendNativeMessage(HOST, { layout: n }, () => void chrome.runtime.lastError);

chrome.commands.onCommand.addListener(async command => {
	const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
	if (!tab) return;

	if (command === 'detach-tab') {
		const siblings = await chrome.tabs.query({ windowId: tab.windowId });
		if (siblings.length < 2) return; // a lone tab has nothing to detach from
		await chrome.storage.session.set({
			[key(tab.id)]: { windowId: tab.windowId, index: tab.index }
		});
		await chrome.windows.create({ tabId: tab.id, focused: true });
		layout('3'); // browser+browser, same as ctrl+alt+d
		return;
	}

	if (command === 'reattach-tab') {
		const origin = (await chrome.storage.session.get(key(tab.id)))[key(tab.id)];
		let target = origin?.windowId;
		if (target !== undefined) {
			try { await chrome.windows.get(target); } catch { target = undefined; }
		}
		if (target === undefined) {
			// Origin window was closed. Fall back to any other normal window.
			const windows = await chrome.windows.getAll({ windowTypes: ['normal'] });
			target = windows.find(w => w.id !== tab.windowId)?.id;
			if (target === undefined) return;
		}
		await chrome.tabs.move(tab.id, { windowId: target, index: origin?.index ?? -1 });
		await chrome.tabs.update(tab.id, { active: true });
		await chrome.windows.update(target, { focused: true });
		await chrome.storage.session.remove(key(tab.id));
		layout('5'); // max browser, same as ctrl+alt+e
	}
});
