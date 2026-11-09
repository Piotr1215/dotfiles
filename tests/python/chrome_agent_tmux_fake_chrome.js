// Runs the chrome-agent-tmux background.js against a fake chrome API and a
// scripted scenario (JSON path in argv[2]); prints what the extension did.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const scenario = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const source = fs.readFileSync(path.join(__dirname, '../../.config/chrome-agent-tmux/background.js'), 'utf8');

const groups = new Map();
const tabs = new Map();
const names = {};
const updates = [];
const host = [];
const timers = [];
const tick = () => new Promise((resolve) => setImmediate(resolve));

function event() {
  const listeners = [];
  return {
    listeners,
    addListener: (fn) => listeners.push(fn),
    fire: (...args) => setImmediate(() => listeners.forEach((fn) => fn(...args))),
  };
}

const chrome = {
  runtime: {
    lastError: undefined,
    sendNativeMessage(name, message, callback) {
      host.push({name, message});
      const reply = message.op === 'names'
        ? {names: Object.fromEntries(message.tabIds.filter((id) => names[id]).map((id) => [String(id), names[id]]))}
        : {switched: false};
      setImmediate(() => callback(reply));
    },
  },
  tabGroups: {
    onCreated: event(), onUpdated: event(), onRemoved: event(),
    async get(id) {
      if (!groups.has(id)) throw new Error('no group');
      return {...groups.get(id)};
    },
    async query() { return [...groups.values()].map((g) => ({...g})); },
    async update(id, props) {
      const group = groups.get(id);
      Object.assign(group, props);
      updates.push([id, props.title]);
      chrome.tabGroups.onUpdated.fire({...group});
      return {...group};
    },
  },
  tabs: {
    onActivated: event(), onUpdated: event(),
    async get(id) {
      if (!tabs.has(id)) throw new Error('no tab');
      return {...tabs.get(id)};
    },
    async query(filter) {
      return [...tabs.values()].filter((t) => Object.entries(filter).every(([k, v]) => t[k] === v)).map((t) => ({...t}));
    },
  },
  windows: {async get(id) { return {id, focused: true}; }},
};

const context = vm.createContext({
  chrome, console, Promise, Date, Map, Set, Error,
  setTimeout: (fn, ms) => timers.push({fn, ms}),
});

const steps = {
  load() { vm.runInContext(source, context, {filename: 'background.js'}); },
  group({group, title}) {
    groups.set(group, {id: group, title, windowId: 1});
    chrome.tabGroups.onCreated.fire({...groups.get(group)});
  },
  tab({tab, group}) {
    tabs.set(tab, {id: tab, groupId: group, windowId: 1, active: false});
    chrome.tabs.onUpdated.fire(tab, {groupId: group}, {...tabs.get(tab)});
  },
  map({tab, name}) { names[tab] = name; },
  title({group, title}) {
    // Another extension (Claude in Chrome) or the user sets the title.
    groups.get(group).title = title;
    chrome.tabGroups.onUpdated.fire({...groups.get(group)});
  },
  timers() { timers.splice(0).forEach(({fn}) => fn()); },
  activate({tab}) {
    for (const t of tabs.values()) t.active = t.id === tab;
    chrome.tabs.onActivated.fire({tabId: tab, windowId: 1});
  },
};

(async () => {
  for (const step of scenario) {
    steps[step.do](step);
    for (let i = 0; i < 40; i++) await tick();
  }
  const titles = Object.fromEntries([...groups.values()].map((g) => [g.id, g.title]));
  process.stdout.write(JSON.stringify({updates, titles, host, timers: timers.length}));
})();
