# Agent tab tmux switch

Claude in Chrome titles every agent group "Claude", so titles cannot identify an agent. Chrome now sends the activated `tabId`, its `groupId`, the ids of all tabs in that group and the group title. The host reads `${XDG_STATE_HOME:-~/.local/state}/agent-tabs/tabs.jsonl` (append-only, newest line per `tab_id` wins, written by a Claude hook), tries the tab id, then the newest group sibling, and switches the single attached client to that tmux pane (session, window and pane) if it still exists. The title match below stays as the last fallback. Replies carry `rule`: `tab_id`, `group_sibling` or `title`. Reload the unpacked extension in chrome://extensions after changing `background.js`.

The extension also retitles groups named "Claude" with an optional leading status emoji (any case, such as "✅Claude"): it asks the host with `{"op": "names", "tabIds": [...]}`, which returns the recorded `@agent_name` (else the tmux session) per tab id and never touches tmux, then replaces only the word, so "✅Claude" becomes "✅gordon" or "✅gordon, kendra". Unmapped groups and titles a person set stay as they are. It re-applies when Claude in Chrome rewrites the title on a status change or a tab joins, writes only when the title would change, and backs off for a minute after three identical rewrites within 2 seconds of its own. Tests: `tests/python/test_chrome_agent_tmux_rename.py` runs `background.js` in node against a fake chrome API.

Chrome sends activated tab group titles to the native host. The host switches
only if a pane in the exact matching session has the same `@agent_name`, and
only if exactly one tmux client is attached. Other tabs and ambiguous clients
leave tmux alone. The host never changes browser focus.

The native host manifest is installed at
`~/.config/google-chrome/NativeMessagingHosts/org.piotr.agent_tab_tmux.json`.
Run `python3 scripts/__chrome_agent_tmux_install.py` from this checkout to
install it again or update its absolute path after moving the checkout. Load this directory as an unpacked Chrome extension with
Developer mode enabled. The manifest key fixes its extension ID so Chrome can
match the native host's allowed origin.

Keep this folder to what Chrome loads. Chrome refuses an unpacked extension holding any name that starts with "_" (a `__pycache__`, for one), and the reload then fails with no extension running, so no tab switches. `test_extension_folder_loads_in_chrome` guards it. Chrome keeps running the old service worker until the extension is reloaded, so a change here is live only after a successful reload.
