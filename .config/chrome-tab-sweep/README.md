# Tab sweep

A toolbar button (a white broom on GitHub's merged purple) that closes two kinds of tabs:

- tabs of a GitHub pull request that is merged, including its `/files`, `/commits` and `/checks` pages
- exact duplicate URLs, keeping one copy

Click the icon (or set a shortcut at `chrome://extensions/shortcuts`). The popup lists what would close; "Close N tabs" closes them. Tick "Auto-close, no click needed" and the extension sweeps on its own: 1.5 seconds after any tab changes URL, after a Chrome restart or an extension reload, when the box is ticked, and once a minute, since a PR that merges while its tab sits still changes no URL. A click then closes at once with no list. After a click the icon badge shows how many tabs it closed, since the popup itself vanishes when its window's active tab closes. A background close leaves no number on the icon (Piotr, 26 Nov: auto-close "just shows me numbers"); hover the icon to see when it last closed tabs and how many. Ctrl+Shift+T brings tabs back one at a time.

Gordon hears only about merged PRs, and only while "Report merged PRs to Gordon" is ticked: then every close that took a merged-PR tab, by click or auto-close, sends him one DM naming the PRs. Duplicate closes never reach him. It is off by default (Piotr, 26 Nov: reporting each close "is mostly noise", "either send all or don't", "report to gordon should only send closed prs not other tabs").

## Rules

- Pinned tabs never close.
- A tab inside a tab group never closes as a duplicate. Agents work in their own groups and Claude in Chrome tracks each tab by id, so the agent's copy stays and the loose copy closes. A duplicate set keeps a pinned copy, else a grouped one, else, on a click, the active one, else the first by window and position.
- Auto-close in the background keeps the oldest copy instead of the active one, and if it closes the tab you are on, it moves you to the copy that stays. Reopening a link you already have open lands you on the older tab, so unsaved typing in it survives.
- Merged-PR tabs close wherever they are, groups included, on a click. A sweep nobody clicked (auto-close in the background) keeps a merged-PR tab only in a live agent's tab group, so an agent reading a merged PR keeps its tab. A group is an agent's when one of its tabs is in the Claude tab-owner map (`~/.local/state/agent-tabs/tabs.jsonl`, read through `scripts/__chrome_agent_tmux.py`) and that tmux pane still lives. Other groups, like the "handoffs" group the handoff board opens for Piotr, lose their merged-PR tabs too. Codex agents' tabs are not in that map.
- A PR GitHub cannot resolve (no access, deleted repo) stays open; the popup shows the gh error.
- A tab whose URL changed between the list and the click stays open.

## How it works

`background.js` sends every tab to the native host `scripts/__chrome_tab_sweep.py` (`org.piotr.tab_sweep`). The host asks GitHub which PRs are merged in one batched `gh api graphql` call, so private loft-sh repos work through Piotr's gh login, and returns the tabs to close. The worker closes them and, with the report box ticked and a merged PR among them, sends the closed list back with `"report": true`, and the host DMs `triage` (Gordon) the merged PRs through `~/.claude/scripts/snd` as `tab-sweep`, for example:

    Chrome tab sweep closed the tabs of 1 merged PR: loft-sh/vcluster#12.

A report op without `"report": true`, or without a merged PR, sends nothing. `TAB_SWEEP_TO` sends the DM to another agent.

## Install

    python3 scripts/__chrome_tab_sweep_install.py

writes `~/.config/google-chrome/NativeMessagingHosts/org.piotr.tab_sweep.json`, its allowed origin computed from the manifest `key` (extension id `pdejgjilnnoghdaafhjfcfbohpacfcie`). Then load this folder once at `chrome://extensions` with "Load unpacked". Keep the folder to what Chrome loads: Chrome refuses an unpacked extension holding a name that starts with `_`.

## Tests

    pytest tests/python/test_chrome_tab_sweep.py tests/python/test_chrome_tab_sweep_e2e.py

The e2e file loads this folder into headless Chrome over the DevTools pipe and sweeps real tabs through the real host, with fake `gh` and `snd`.
