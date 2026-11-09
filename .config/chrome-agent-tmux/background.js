// Resolve the activated tab again after each asynchronous lookup so a stale
// event cannot switch the terminal after a later tab activation.
//
// Claude in Chrome titles every agent's group "Claude" behind a status emoji,
// so the title cannot name the agent. The host maps the tab id, then the
// group's other tab ids, to the pane recorded by the Claude tab-owner hook,
// and falls back to the title, which Codex sets to the agent's name.
const MAX_GROUP_TABS = 200;
let generation = 0;
chrome.tabs.onActivated.addListener(async ({tabId, windowId}) => {
  const current = ++generation;
  try {
    const tab = await chrome.tabs.get(tabId);
    if (current !== generation || !tab.active || tab.windowId !== windowId || tab.groupId < 0) return;
    const group = await chrome.tabGroups.get(tab.groupId);
    const siblings = await chrome.tabs.query({groupId: tab.groupId});
    const active = await chrome.tabs.query({active: true, windowId});
    const window = await chrome.windows.get(windowId);
    if (current !== generation || active[0]?.id !== tabId || !window.focused) return;
    chrome.runtime.sendNativeMessage('org.piotr.agent_tab_tmux', {
      tabId,
      groupId: tab.groupId,
      groupTabIds: siblings.map((t) => t.id).slice(0, MAX_GROUP_TABS),
      owner: group.title ?? '',
    }, () => {
      // The host can be unavailable when tmux is not running.
      void chrome.runtime.lastError;
    });
  } catch (_) {
    // Tabs and groups can disappear during activation.
  }
});
