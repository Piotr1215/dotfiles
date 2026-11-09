# Agent tab tmux switch

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

Keep this folder to what Chrome loads. Chrome refuses an unpacked extension holding any name that starts with "_" (a `__pycache__`, for one), and the reload then fails with no extension running, so no tab switches. `test_extension_folder_loads_in_chrome` guards it, and `test_chrome_agent_tmux_e2e.py` loads the folder into a real Chrome over the DevTools pipe (`Extensions.loadUnpacked`; branded Chrome ignores `--load-extension`) and fails with Chrome's own load error. Chrome keeps running the old service worker until the extension is reloaded, so a change here is live only after a successful reload.
