// Tab sweep. The host (scripts/__chrome_tab_sweep.py) picks the tabs to close:
// merged GitHub PRs and exact duplicate URLs. This worker closes them and,
// when the popup's "Report closes to Gordon" box is ticked, has the host DM
// Gordon ("triage") the list: every close or none. The work runs here, not in
// the popup, because Chrome closes the popup when its window's active tab closes.
// With "Auto-close" ticked it also sweeps on its own, with no click.
const HOST = 'org.piotr.tab_sweep';

function host(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST, message, (reply) => {
      const error = chrome.runtime.lastError;
      if (error) reject(new Error(error.message));
      else if (reply?.error && !('close' in reply) && !('reported' in reply)) reject(new Error(reply.error));
      else resolve(reply);
    });
  });
}

// Every open tab, in the shape the host's plan op reads. keepGrouped leaves
// every tab in a tab group open, merged PR or not, for sweeps nobody clicked.
async function plan(keepGrouped = false) {
  const tabs = await chrome.tabs.query({});
  return host({op: 'plan', keep_grouped: keepGrouped, tabs: tabs.map((t) => ({
    id: t.id, url: t.url || t.pendingUrl || '', title: t.title || '',
    pinned: t.pinned, active: t.active, windowId: t.windowId, index: t.index, groupId: t.groupId,
  }))});
}

// Close the planned tabs that still show the planned URL, then report if asked.
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
  let reported = false;
  let error = null;
  const {report} = await chrome.storage.local.get('report');
  if (closed.length && report === true) {
    try {
      const reply = await host({op: 'report', closed, report: true});
      reported = reply.reported === true;
      error = reply.error || null;
    } catch (e) { error = e.message; }
  }
  // Only a close sets the badge: the popup clears it, and the frequent empty
  // background sweeps would wipe it before Piotr sees it.
  if (closed.length) await chrome.action.setBadgeText({text: String(closed.length)});
  return {closed, reported, error};
}

async function sweep(keepGrouped = false) {
  const planned = await plan(keepGrouped);
  return {...(await closeTabs(planned.close)), errors: planned.errors || []};
}

// Auto-close: sweep a moment after the last tab URL change, after a restart
// or an extension reload, and when the box is ticked. Piotr, 26 Nov: "the tab sweep is marked auto so
// it should auto close tabs". Sweeps run one at a time.
let timer = null;
let queue = Promise.resolve();
function schedule() {
  clearTimeout(timer);
  timer = setTimeout(() => {
    queue = queue.then(async () => {
      const {auto} = await chrome.storage.local.get('auto');
      if (auto === true) await sweep(true);
    }).catch(() => {});
  }, 1500);
}
chrome.tabs.onUpdated.addListener((_id, change) => { if (change.url) schedule(); });
chrome.runtime.onStartup.addListener(schedule);
chrome.runtime.onInstalled.addListener(schedule);
chrome.storage.onChanged.addListener((change) => { if (change.auto?.newValue === true) schedule(); });

chrome.runtime.onMessage.addListener((message, _sender, respond) => {
  const run = message?.op === 'plan' ? plan()
    : message?.op === 'close' ? closeTabs(message.rows)
    : message?.op === 'sweep' ? sweep()
    : null;
  if (!run) return false;
  run.then(respond, (e) => respond({error: e.message}));
  return true;
});
