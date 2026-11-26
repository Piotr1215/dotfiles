// The popup shows what the sweep would close and closes it on a click, or,
// with auto-close on, sweeps as soon as it opens (background.js also sweeps
// on its own then, as tabs change). background.js does the work,
// and reports every close to Gordon while "Report closes to Gordon" is ticked.
const status = document.getElementById('status');
const list = document.getElementById('list');
const button = document.getElementById('close');
const auto = document.getElementById('auto');
const report = document.getElementById('report');

function show(rows, errors) {
  list.replaceChildren(...rows.map((row) => {
    const item = document.createElement('li');
    const why = document.createElement('span');
    why.className = 'why';
    why.textContent = row.reason === 'merged' ? 'merged' : 'duplicate';
    item.append(why, row.reason === 'merged' ? `${row.pr} ${row.title}` : (row.title || row.url));
    item.title = row.url;
    return item;
  }));
  for (const error of errors || []) {
    const item = document.createElement('li');
    item.className = 'error';
    item.textContent = error;
    list.append(item);
  }
}

function done(result) {
  if (result.error && !result.closed) { status.textContent = result.error; status.className = 'error'; return; }
  const sent = result.reported ? ', reported to Gordon' : result.error ? `, Gordon report failed: ${result.error}` : '';
  status.textContent = `Closed ${result.closed.length} tab${result.closed.length === 1 ? '' : 's'}${sent}.`;
  show(result.closed, result.errors);
  button.hidden = true;
}

async function review() {
  const planned = await chrome.runtime.sendMessage({op: 'plan'});
  if (planned.error) { status.textContent = planned.error; status.className = 'error'; return; }
  const rows = planned.close;
  status.textContent = rows.length ? `${rows.length} of ${planned.tabs} tabs to close:` : `Nothing to close in ${planned.tabs} tabs.`;
  show(rows, planned.errors);
  button.hidden = !rows.length;
  button.textContent = `Close ${rows.length} tab${rows.length === 1 ? '' : 's'}`;
  button.onclick = async () => {
    button.disabled = true;
    done(await chrome.runtime.sendMessage({op: 'close', rows}));
  };
}

(async () => {
  chrome.action.setBadgeText({text: ''});
  const settings = await chrome.storage.local.get(['auto', 'report']);
  auto.checked = settings.auto === true;
  report.checked = settings.report === true;
  auto.onchange = () => chrome.storage.local.set({auto: auto.checked});
  report.onchange = () => chrome.storage.local.set({report: report.checked});
  if (auto.checked) done(await chrome.runtime.sendMessage({op: 'sweep'}));
  else await review();
})();
