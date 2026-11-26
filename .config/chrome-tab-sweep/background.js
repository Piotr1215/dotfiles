// Tab sweep. The host (scripts/__chrome_tab_sweep.py) picks the tabs to close:
// merged GitHub PRs and exact duplicate URLs. This worker closes them and
// keeps what it closed in storage.local "pending" until Piotr sends it to
// Gordon with the popup's button. The work runs here, not in the popup,
// because Chrome closes the popup when its window's active tab closes.
const HOST = 'org.piotr.tab_sweep';

function host(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST, message, (reply) => {
      const error = chrome.runtime.lastError;
      if (error) reject(new Error(error.message));
      else if (reply?.error && !('close' in reply)) reject(new Error(reply.error));
      else resolve(reply);
    });
  });
}

// Every open tab, in the shape the host's plan op reads.
async function plan() {
  const tabs = await chrome.tabs.query({});
  return host({op: 'plan', tabs: tabs.map((t) => ({
    id: t.id, url: t.url || t.pendingUrl || '', title: t.title || '',
    pinned: t.pinned, active: t.active, windowId: t.windowId, index: t.index, groupId: t.groupId,
  }))});
}

// Close the planned tabs that still show the planned URL; add them to pending.
async function closeTabs(rows) {
  const closed = [];
  await Promise.all((rows || []).map(async (row) => {
    try {
      const tab = await chrome.tabs.get(row.id);
      if (tab.pinned || (tab.url || tab.pendingUrl) !== row.url) return;
      await chrome.tabs.remove(row.id);
      closed.push(row);
    } catch (_) { /* the tab is already gone */ }
  }));
  if (closed.length) {
    const {pending = []} = await chrome.storage.local.get('pending');
    await chrome.storage.local.set({pending: [...pending, ...closed].slice(-500)});
  }
  await chrome.action.setBadgeText({text: closed.length ? String(closed.length) : ''});
  return {closed};
}

async function sweep() {
  const planned = await plan();
  return {...(await closeTabs(planned.close)), errors: planned.errors || []};
}

chrome.runtime.onMessage.addListener((message, _sender, respond) => {
  const run = message?.op === 'plan' ? plan()
    : message?.op === 'close' ? closeTabs(message.rows)
    : message?.op === 'sweep' ? sweep()
    : null;
  if (!run) return false;
  run.then(respond, (e) => respond({error: e.message}));
  return true;
});
