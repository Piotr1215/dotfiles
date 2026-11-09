// Resolve the activated tab again after each asynchronous lookup so a stale
// event cannot switch the terminal after a later tab activation.
let generation = 0;
chrome.tabs.onActivated.addListener(async ({tabId, windowId}) => {
  const current = ++generation;
  try {
    const tab = await chrome.tabs.get(tabId);
    if (current !== generation || !tab.active || tab.windowId !== windowId || tab.groupId < 0) return;
    const group = await chrome.tabGroups.get(tab.groupId);
    const active = await chrome.tabs.query({active: true, windowId});
    const window = await chrome.windows.get(windowId);
    if (current !== generation || active[0]?.id !== tabId || !window.focused || !group.title) return;
    chrome.runtime.sendNativeMessage('org.piotr.agent_tab_tmux', {owner: group.title}, () => {
      // The host can be unavailable when tmux is not running.
      void chrome.runtime.lastError;
    });
  } catch (_) {
    // Tabs and groups can disappear during activation.
  }
});
