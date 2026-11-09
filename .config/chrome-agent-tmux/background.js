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

// Group names. Claude in Chrome titles a new group "Claude" behind a status
// emoji ("✅Claude") and later swaps only the emoji, keeping the rest. Replace
// the word with the agent names the host maps the group's tab ids to, so each
// group shows its agent. A group is ours to retitle only while its title is
// that "Claude" form or still the exact title we last set, so a person's own
// group name is never overwritten and our own onUpdated echo changes nothing.
//
// Claude in Chrome keeps group ownership in storage.session, which a reload or
// update of it clears. It then takes a group back only while the title, minus
// the emoji, is still "Claude", and otherwise opens a new one. So when it
// reloads, put "Claude" back on the groups we renamed and hold each one until
// its title changes again, which Claude in Chrome does once it owns the group.
const HOST = 'org.piotr.agent_tab_tmux';
const CLAUDE_IN_CHROME = 'fcoeoabgfenejglbffodgkkbkcdhcgfn';
const STATUS_TITLE = /^(\P{L}*)claude\s*$/iu;
const NO_LETTERS = /^\P{L}*$/u;
const RETRY_MS = [2000, 10000];
const FIGHT_MS = 2000;
const MAX_FIGHTS = 3;
const BACKOFF_MS = 60000;
const HELD_KEY = 'heldGroups';
const applied = new Map();
const fights = new Map();
const running = new Set();
const queued = new Set();
const restoring = new Set();
// Held titles live in storage.session so they outlast this service worker.
let held = {};
const heldLoaded = chrome.storage.session.get(HELD_KEY).then((stored) => {
  held = stored?.[HELD_KEY] ?? {};
}, () => {});

function saveHeld() {
  return chrome.storage.session.set({[HELD_KEY]: held}).catch(() => {});
}

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

// The agent names behind a group's tabs, "" when none are known yet.
async function groupOwners(groupId) {
  const tabs = await chrome.tabs.query({groupId});
  const ids = tabs.map((t) => t.id).slice(0, MAX_GROUP_TABS);
  if (!ids.length) return '';
  const reply = await askHost({op: 'names', tabIds: ids});
  return ownerNames(ids, reply?.names);
}

// The status prefix to keep, or null when the group is not ours to retitle.
function ourPrefix(group) {
  const prefix = statusPrefix(group.title);
  if (prefix !== null) return prefix;
  const last = applied.get(group.id);
  return last && last.title === group.title ? last.prefix : null;
}

// True while a group we gave back to Claude in Chrome still has that title.
async function stillHeld(group) {
  const title = held[group.id];
  if (title === undefined) return false;
  if (title === group.title) return true;
  delete held[group.id];
  await saveHeld();
  return false;
}

// A status change gives a new prefix, so an identical rewrite right after our
// write is another extension fighting back: give up on that group for a while.
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

async function renameGroup(groupId, attempt) {
  const group = await chrome.tabGroups.get(groupId);
  if (await stillHeld(group) || ourPrefix(group) === null) return;
  const owners = await groupOwners(groupId);
  if (!owners) {
    // The tab-owner hook writes after the agent's tool call returns, so a
    // fresh group can be unmapped for a moment.
    if (attempt < RETRY_MS.length) setTimeout(() => syncGroup(groupId, attempt + 1), RETRY_MS[attempt]);
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
}

// Give "Claude" back to a group whose title is its status prefix plus the
// agent names we would set, which is the title we wrote.
async function restoreGroup(groupId) {
  const group = await chrome.tabGroups.get(groupId);
  const title = group.title ?? '';
  if (statusPrefix(title) !== null) return;
  const owners = await groupOwners(groupId);
  if (!owners || !title.endsWith(owners)) return;
  const prefix = title.slice(0, title.length - owners.length);
  if (!NO_LETTERS.test(prefix)) return;
  const claude = prefix + 'Claude';
  held[groupId] = claude;
  await saveHeld();
  applied.delete(groupId);
  await chrome.tabGroups.update(groupId, {title: claude});
}

// One pass at a time per group, so a restore and a rename never interleave.
async function syncGroup(groupId, attempt = 0) {
  if (typeof groupId !== 'number' || groupId < 0) return;
  if (running.has(groupId)) {
    queued.add(groupId);
    return;
  }
  running.add(groupId);
  try {
    await heldLoaded;
    if (restoring.delete(groupId)) await restoreGroup(groupId);
    else await renameGroup(groupId, attempt);
  } catch (_) {
    // Groups can close while we look them up.
  } finally {
    running.delete(groupId);
    if (queued.delete(groupId)) syncGroup(groupId);
  }
}

function syncIfStatusTitle(group) {
  if (statusPrefix(group.title) !== null) syncGroup(group.id);
}

function claudeInChromeRestarted(info) {
  if (info?.id !== CLAUDE_IN_CHROME) return;
  chrome.tabGroups.query({}).then((groups) => {
    for (const group of groups) {
      restoring.add(group.id);
      syncGroup(group.id);
    }
  }, () => {});
}

chrome.tabGroups.onCreated.addListener(syncIfStatusTitle);
chrome.tabGroups.onUpdated.addListener(syncIfStatusTitle);
chrome.tabGroups.onRemoved.addListener((group) => {
  applied.delete(group.id);
  fights.delete(group.id);
  if (held[group.id] !== undefined) {
    delete held[group.id];
    saveHeld();
  }
});
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (typeof changeInfo.groupId === 'number' && changeInfo.groupId >= 0) syncGroup(changeInfo.groupId);
  else if (changeInfo.status === 'complete' && tab?.groupId >= 0) syncGroup(tab.groupId);
});
chrome.tabs.onActivated.addListener(async ({tabId}) => {
  try {
    const tab = await chrome.tabs.get(tabId);
    if (tab.groupId >= 0) syncGroup(tab.groupId);
  } catch (_) {
    // The tab can close before the lookup.
  }
});
chrome.management.onInstalled.addListener(claudeInChromeRestarted);
chrome.management.onEnabled.addListener(claudeInChromeRestarted);
chrome.tabGroups.query({}).then((groups) => groups.forEach(syncIfStatusTitle), () => {});
