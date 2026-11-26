// Tab sweep. The host (scripts/__chrome_tab_sweep.py) picks the tabs to close:
// merged GitHub PRs and exact duplicate URLs. This worker closes them and,
// when the popup's "Report merged PRs to Gordon" box is ticked, has the host
// DM Gordon ("triage") the merged PRs it closed, never the duplicates. The work runs here, not in
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

// Every open tab, in the shape the host's plan op reads. unattended marks a
// sweep nobody clicked: the host then keeps merged-PR tabs in a live agent's
// tab group and the oldest copy of a duplicate.
async function plan(unattended = false) {
  const tabs = await chrome.tabs.query({});
  return host({op: 'plan', unattended, tabs: tabs.map((t) => ({
    id: t.id, url: t.url || t.pendingUrl || '', title: t.title || '',
    pinned: t.pinned, active: t.active, windowId: t.windowId, index: t.index, groupId: t.groupId,
  }))});
}

// Close the planned tabs that still show the planned URL, then report merged
// PRs if asked. In an unattended sweep, closing the tab Piotr is on (a link he
// just reopened) moves him to the copy that stays, in its own window.
async function closeTabs(rows, unattended = false) {
  const closed = [];
  await Promise.all((rows || []).map(async (row) => {
    try {
      const tab = await chrome.tabs.get(row.id);
      if (tab.pinned || (tab.url || tab.pendingUrl) !== row.url) return;
      await chrome.tabs.remove(row.id);
      closed.push(row);
      if (unattended && tab.active && row.kept) {
        const kept = await chrome.tabs.update(row.kept, {active: true});
        await chrome.windows.update(kept.windowId, {focused: true});
      }
    } catch (_) { /* the tab is already gone */ }
  }));
  let reported = false;
  let error = null;
  const {report} = await chrome.storage.local.get('report');
  if (closed.some((row) => row.reason === 'merged') && report === true) {
    try {
      const reply = await host({op: 'report', closed, report: true});
      reported = reply.reported === true;
      error = reply.error || null;
    } catch (e) { error = e.message; }
  }
  // A click's close shows its count on the badge, since the popup vanishes
  // when its window's active tab closes. A background close notes itself only
  // in the hover title: a number left on the icon read as tabs still waiting
  // (Piotr, 26 Nov: "instead it just shows me numbers").
  const s = closed.length === 1 ? '' : 's';
  if (closed.length && unattended) await chrome.action.setTitle({title: `Tab sweep: auto-closed ${closed.length} tab${s} at ${new Date().toTimeString().slice(0, 5)}`});
  else if (closed.length) await chrome.action.setBadgeText({text: String(closed.length)});
  return {closed, reported, error};
}

async function sweep(unattended = false) {
  const planned = await plan(unattended);
  return {...(await closeTabs(planned.close, unattended)), errors: planned.errors || []};
}

// Auto-close: sweep a moment after the last tab URL change, after a restart
// or an extension reload, when the box is ticked, and once a minute, since a
// PR that merges while its tab sits still changes no URL. Piotr, 26 Nov: "the
// tab sweep is marked auto so it should auto close tabs". Sweeps run one at a time.
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
chrome.alarms.onAlarm.addListener(() => schedule());
chrome.alarms.get('sweep').then((alarm) => alarm || chrome.alarms.create('sweep', {periodInMinutes: 1}));

chrome.runtime.onMessage.addListener((message, _sender, respond) => {
  const run = message?.op === 'plan' ? plan()
    : message?.op === 'close' ? closeTabs(message.rows)
    : message?.op === 'sweep' ? sweep()
    : null;
  if (!run) return false;
  run.then(respond, (e) => respond({error: e.message}));
  return true;
});
