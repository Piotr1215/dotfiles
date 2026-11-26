// The popup shows what the sweep would close and closes it on a click, or,
// with auto-close on, sweeps as soon as it opens. background.js does the work.
// Closed tabs wait in storage.local "pending" until "Tell Gordon" sends them.
const status = document.getElementById('status');
const list = document.getElementById('list');
const button = document.getElementById('close');
const auto = document.getElementById('auto');
const tell = document.getElementById('tell');

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
  status.textContent = `Closed ${result.closed.length} tab${result.closed.length === 1 ? '' : 's'}.`;
  show(result.closed, result.errors);
  button.hidden = true;
}

// One DM to Gordon, only on a click, with every close since the last one sent.
async function offerTell() {
  const {pending = []} = await chrome.storage.local.get('pending');
  tell.hidden = !pending.length;
  tell.disabled = false;
  tell.textContent = `Tell Gordon about ${pending.length} closed tab${pending.length === 1 ? '' : 's'}`;
  tell.onclick = async () => {
    tell.disabled = true;
    const reply = await chrome.runtime.sendNativeMessage('org.piotr.tab_sweep', {op: 'report', closed: pending, report: true})
      .catch((e) => ({error: e.message}));
    if (reply?.reported) {
      await chrome.storage.local.remove('pending');
      tell.hidden = true;
      status.textContent = `Told Gordon about ${pending.length} closed tab${pending.length === 1 ? '' : 's'}.`;
    } else {
      status.textContent = `Gordon report failed: ${reply?.error}`;
      status.className = 'error';
      tell.disabled = false;
    }
  };
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
    await offerTell();
  };
}

(async () => {
  chrome.action.setBadgeText({text: ''});
  auto.checked = (await chrome.storage.local.get('auto')).auto === true;
  auto.onchange = () => chrome.storage.local.set({auto: auto.checked});
  if (auto.checked) done(await chrome.runtime.sendMessage({op: 'sweep'}));
  else await review();
  await offerTell();
})();
