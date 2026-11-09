// Resolve the activated tab again after each asynchronous lookup so a stale
// event cannot switch the terminal after a later tab activation.
let generation = 0;
chrome.tabs.onActivated.addListener(async ({tabId, windowId}) => {
  const current = ++generation;
  try {
    const tab = await chrome.tabs.get(tabId);
    if (current !== generation || !tab.active || tab.windowId !== windowId) return;
    const grouped = tab.groupId >= 0;
    const group = grouped ? await chrome.tabGroups.get(tab.groupId) : null;
    const siblings = grouped ? await chrome.tabs.query({groupId: tab.groupId}) : [];
    const active = await chrome.tabs.query({active: true, windowId});
    const window = await chrome.windows.get(windowId);
    if (current !== generation || active[0]?.id !== tabId || !window.focused) return;
    chrome.runtime.sendNativeMessage('org.piotr.agent_tab_tmux', {
      tabId,
      groupId: tab.groupId,
      groupTabIds: siblings.map((t) => t.id),
      owner: group?.title ?? '',
    }, () => {
      // The host can be unavailable when tmux is not running.
      void chrome.runtime.lastError;
    });
  } catch (_) {
    // Tabs and groups can disappear during activation.
  }
});

// Claude in Chrome titles every agent's tab group "Claude" behind a status
// emoji ("✅Claude", another emoji while working) and rewrites it whenever the
// status changes. Replace only the word with the agent names the native host
// maps the group's tab ids to, keeping the status prefix, and keep groups we
// titled in sync as tabs join. A group is ours to touch only while its title is
// that "Claude" form or still the exact title we last set, so a user's own
// group name is never overwritten and our own onUpdated echo changes nothing.
const HOST = 'org.piotr.agent_tab_tmux';
const STATUS_TITLE = /^(\P{L}*)claude\s*$/iu;
const RETRY_MS = [2000, 10000];
const FIGHT_MS = 2000;
const MAX_FIGHTS = 3;
const BACKOFF_MS = 60000;
const MAX_NAME_TABS = 200;
const applied = new Map();
const fights = new Map();
const running = new Set();
const queued = new Set();

function askHost(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendNativeMessage(HOST, message, (reply) => {
      void chrome.runtime.lastError;
      resolve(reply);
    });
  });
}

function statusPrefix(title) {
  const match = STATUS_TITLE.exec(title ?? '');
  return match ? match[1] : null;
}

function ownerNames(tabIds, names) {
  const owners = new Set();
  for (const id of tabIds) {
    const name = names?.[String(id)];
    if (typeof name === 'string' && name.trim()) owners.add(name.trim());
  }
  return [...owners].sort().join(', ');
}

// The status prefix to keep, or null when the group is not ours to retitle.
function ourPrefix(group) {
  const prefix = statusPrefix(group.title);
  if (prefix !== null) return prefix;
  const last = applied.get(group.id);
  return last && last.title === group.title ? last.prefix : null;
}

// A status change gives a new prefix, so an identical rewrite right after our
// write is the other extension fighting back: give up on that group for a while.
function fightingBack(groupId, title, now) {
  const state = fights.get(groupId) ?? {count: 0, until: 0};
  fights.set(groupId, state);
  if (now < state.until) return true;
  const last = applied.get(groupId);
  state.count = last && last.title === title && now - last.at < FIGHT_MS ? state.count + 1 : 0;
  if (state.count < MAX_FIGHTS) return false;
  state.count = 0;
  state.until = now + BACKOFF_MS;
  return true;
}

function retryLater(groupId, attempt) {
  if (attempt < RETRY_MS.length) setTimeout(() => renameGroup(groupId, attempt + 1), RETRY_MS[attempt]);
}

async function renameGroup(groupId, attempt = 0) {
  if (typeof groupId !== 'number' || groupId < 0) return;
  if (running.has(groupId)) {
    queued.add(groupId);
    return;
  }
  running.add(groupId);
  try {
    const group = await chrome.tabGroups.get(groupId);
    if (ourPrefix(group) === null) return;
    const tabs = await chrome.tabs.query({groupId});
    const ids = tabs.map((t) => t.id).slice(0, MAX_NAME_TABS);
    if (!ids.length) return;
    const reply = await askHost({op: 'names', tabIds: ids});
    const owners = ownerNames(ids, reply?.names);
    if (!owners) {
      // The ownership hook writes after the agent's tool call returns, so a
      // fresh group can be unmapped for a moment.
      retryLater(groupId, attempt);
      return;
    }
    const fresh = await chrome.tabGroups.get(groupId);
    const prefix = ourPrefix(fresh);
    if (prefix === null) return;
    const title = prefix + owners;
    // Write only a real change; this also ends our own onUpdated echo.
    if (fresh.title === title || statusPrefix(title) !== null) return;
    const now = Date.now();
    if (fightingBack(groupId, title, now)) return;
    applied.set(groupId, {title, prefix, at: now});
    await chrome.tabGroups.update(groupId, {title});
  } catch (_) {
    // Groups can close while we look them up.
  } finally {
    running.delete(groupId);
    if (queued.delete(groupId)) renameGroup(groupId);
  }
}

function renameIfStatusTitle(group) {
  if (statusPrefix(group.title) !== null) renameGroup(group.id);
}

chrome.tabGroups.onCreated.addListener(renameIfStatusTitle);
chrome.tabGroups.onUpdated.addListener(renameIfStatusTitle);
chrome.tabGroups.onRemoved.addListener((group) => {
  applied.delete(group.id);
  fights.delete(group.id);
});
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (typeof changeInfo.groupId === 'number' && changeInfo.groupId >= 0) renameGroup(changeInfo.groupId);
  else if (changeInfo.status === 'complete' && tab?.groupId >= 0) renameGroup(tab.groupId);
});
chrome.tabs.onActivated.addListener(async ({tabId}) => {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (tab.groupId >= 0) renameGroup(tab.groupId);
  } catch (_) {
    // The tab can close before the lookup.
  }
});
chrome.tabGroups.query({}).then((groups) => groups.forEach(renameIfStatusTitle), () => {});
