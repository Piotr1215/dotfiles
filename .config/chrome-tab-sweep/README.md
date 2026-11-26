# Tab sweep

A toolbar button (a white broom on GitHub's merged purple) that closes two kinds of tabs:

- tabs of a GitHub pull request that is merged, including its `/files`, `/commits` and `/checks` pages
- exact duplicate URLs, keeping one copy

Click the icon (or set a shortcut at `chrome://extensions/shortcuts`). The popup lists what would close; "Close N tabs" closes them. Tick "Auto-close, no click needed" and the extension sweeps on its own: 1.5 seconds after any tab changes URL, after a Chrome restart or an extension reload, and when the box is ticked. A click then closes at once with no list. The icon badge shows how many tabs the last close took, since the popup itself vanishes when its window's active tab closes. Ctrl+Shift+T brings tabs back one at a time.

Gordon hears about closes only while "Report closes to Gordon" is ticked: then every close, by click or auto-close, sends him one DM, and unticked none do. It is off by default (Piotr, 26 Nov: reporting each close "is mostly noise", "either send all or don't").

## Rules

- Pinned tabs never close.
- A tab inside a tab group never closes as a duplicate. Agents work in their own groups and Claude in Chrome tracks each tab by id, so the agent's copy stays and the loose copy closes. A duplicate set keeps a pinned copy, else a grouped one, else the active one, else the first by window and position.
- Merged-PR tabs close wherever they are, groups included, on a click. A sweep nobody clicked (auto-close in the background) leaves every tab in a tab group open, so an agent reading a merged PR keeps its tab.
- A PR GitHub cannot resolve (no access, deleted repo) stays open; the popup shows the gh error.
- A tab whose URL changed between the list and the click stays open.

## How it works

`background.js` sends every tab to the native host `scripts/__chrome_tab_sweep.py` (`org.piotr.tab_sweep`). The host asks GitHub which PRs are merged in one batched `gh api graphql` call, so private loft-sh repos work through Piotr's gh login, and returns the tabs to close. The worker closes them and, with the report box ticked, sends the closed list back with `"report": true`, and the host DMs `triage` (Gordon) through `~/.claude/scripts/snd` as `tab-sweep`, for example:

    Chrome tab sweep closed 3 tabs. Merged PRs (1): loft-sh/vcluster#12. Duplicates (2): https://docs.example/page x2.

A report op without `"report": true` sends nothing. Duplicate URLs go to the bus without their query string or fragment, so a token in a link stays off it. `TAB_SWEEP_TO` sends the DM to another agent.

## Install

    python3 scripts/__chrome_tab_sweep_install.py

writes `~/.config/google-chrome/NativeMessagingHosts/org.piotr.tab_sweep.json`, its allowed origin computed from the manifest `key` (extension id `pdejgjilnnoghdaafhjfcfbohpacfcie`). Then load this folder once at `chrome://extensions` with "Load unpacked". Keep the folder to what Chrome loads: Chrome refuses an unpacked extension holding a name that starts with `_`.

## Tests

    pytest tests/python/test_chrome_tab_sweep.py tests/python/test_chrome_tab_sweep_e2e.py

The e2e file loads this folder into headless Chrome over the DevTools pipe and sweeps real tabs through the real host, with fake `gh` and `snd`.
