# Agent tab tmux switch

When a grouped tab is activated in a focused window, Chrome sends the host its URL, tab id, the group's tab ids (at most 200) and the group title. Ungrouped tabs send nothing. A click on a group's name sends the group details without a tab id or URL: it only collapses or expands the group and activates no tab, so the extension keeps each group's last collapsed state in `storage.session` (the service worker sleeps between clicks) and reads a change in a focused window as a click. When the group holds the active tab, Chrome first activates a tab outside it; the group click still wins. The host picks the pane in this order:

For a tab in the `handoffs` group, the host first matches its URL against pending handoff annotations and briefs. A unique match with a live declared owner switches to that owner; otherwise the group goes to Gordon as before. This also works when the owner starts after the tab was opened.

1. `tab_id`: the tab's newest line in `${XDG_STATE_HOME:-~/.local/state}/agent-tabs/tabs.jsonl`, written by the Claude tab-owner hook (`~/.claude/scripts/__chrome_tab_owner_hook.py`) on every Claude in Chrome tool call. Claude in Chrome titles every group "Claude" behind a status emoji, so this is how Claude tabs switch.
2. `group_sibling`: the newest mapped tab in the same group, for a tab the agent opened but never named in a tool call, and for a click on the group's name.
3. `title`: the pane whose `@agent_name` is the group title minus any leading status symbol ("✅gordon" reads "gordon"), in the session of that name if there is one, else the only such pane. This is how Codex groups switch, and how a renamed Claude group still switches when its tab map is stale (a Chrome restart gives every tab a new id) or the agent moved to a new pane. A title naming several agents switches nothing.

A pane that no longer exists is skipped. The host switches only when exactly one tmux client is attached, and never changes browser focus. A Claude session records its tabs only once it runs with the hook (`~/.claude` 870cf284, 9 Nov 10:28); a session started earlier, or a stable agent whose generated `role-settings.json` predates it, has unmapped tabs that leave tmux alone until it restarts.

## Group names

The extension also renames each Claude group to its agent: "✅Claude" becomes "✅gordon", and several agents in one group read "✅gordon, kendra". It asks the host (`{"op": "names", "tabIds": [...]}`, which never touches tmux) for the `@agent_name`, else the tmux session, recorded for the group's tabs. Claude in Chrome later swaps only the status emoji, so the name stays. A group no agent maps to keeps "Claude", and a title a person set is never touched. Claude Code can name the group itself only through a desktop-app rename behind a server-side flag (`allow_chrome_tab_group_title`, Claude Code 2.1.319), so the CLI agents cannot.

Claude in Chrome keeps group ownership in `storage.session`, which its own reload or update clears. It then takes a group back only while the title, minus the emoji, is still "Claude"; otherwise it opens a new group and the agent loses its old tabs. So when Claude in Chrome reloads, updates or is re-enabled (`management` events), the extension puts "Claude" back on every group it renamed and holds it until Claude in Chrome changes the title again, which it does only on a group it owns. A Chrome restart gives every group a new id, so Claude in Chrome opens new groups then whatever the title.

The native host manifest is installed at
`~/.config/google-chrome/NativeMessagingHosts/org.piotr.agent_tab_tmux.json`.
Run `python3 scripts/__chrome_agent_tmux_install.py` from this checkout to
install it again or update its absolute path after moving the checkout. Load this directory as an unpacked Chrome extension with
Developer mode enabled. The manifest key fixes its extension ID so Chrome can
match the native host's allowed origin.

Keep this folder to what Chrome loads. Chrome refuses an unpacked extension holding any name that starts with "_" (a `__pycache__`, for one), and the reload then fails with no extension running, so no tab switches. `test_extension_folder_loads_in_chrome` guards it, and `test_chrome_agent_tmux_e2e.py` loads the folder into a real Chrome over the DevTools pipe (`Extensions.loadUnpacked`; branded Chrome ignores `--load-extension`) and fails with Chrome's own load error. Chrome keeps running the old service worker until the extension is reloaded, so the extension reloads itself.

## Self-reload

Every 30 seconds (`self-reload` alarm) the service worker hashes `manifest.json` and its service worker file, read fresh from disk. When the hash differs from the loaded one and holds for one more tick, the extension asks the host (`{"op": "check"}`) whether the folder would load: no name starting with "_", a manifest naming an existing service worker, and `node --check` on it. Only then does it call `chrome.runtime.reload()`, so a committed or saved change goes live about a minute after the last edit with no click. A refused change keeps the running code and is not sent to the host again until the files change. Each start after a reload sends `{"op": "loaded", "hash": ...}`, so `agent-tabs/host.log` shows when a change went live, and a `check` line with `"loadable": false` names why one did not.

`chrome.runtime.reload()` needs Developer mode, which loading an unpacked extension already requires; with it off, Chrome leaves the extension disabled. The first version with this code still needs one reload by hand. The e2e tests run in a profile with Developer mode on and edit a copy of this folder (`AGENT_TAB_EXTENSION_DIR` points the host at it).
