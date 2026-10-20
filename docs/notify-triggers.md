# Notification triggers

A reminder can fire on a desktop popup instead of a clock. `remind add "<label>" --on-notify '<regex>' [--delay 10m] --action exec --command '<cmd>'` creates one; it stays active and fires once per matching popup, with Gordon's session out of the loop.

## Three tiers for a popup

| Tier | File | Who decides |
|---|---|---|
| never reaches Gordon | `~/.claude/mods/notify-watch/ignore.txt` | nobody, the mod drops it |
| automatic action | on-notify reminders in the JSONL store | the reminder engine, no judgment |
| Gordon's judgment | `~/.claude/mods/notify-watch/actions.md` | Gordon, per prompt |

## Mechanism

`reminder-watch.service` (user unit, `__reminder.sh watch`) tails `~/.local/state/notifications.log` from its own byte cursor (`~/.local/state/reminders/notify.cursor`), one pass per inotify event or every 5 seconds. Each pass is `remind match`: read the complete lines past the cursor, persist the cursor, then test each line against every active record's `on_notify` regex (jq `test`, the dialect JS `RegExp` shares for these patterns). A match fires `fire <id>` now with the record on stdin and in `$REMINDER_MATCH`, or with `--delay` writes the record to `matches/<token>` and queues `fire <id> <token>` in at queue `n` (queue `r` is rebuilt by `sync` and would reap it).

Rejected: a hook inside `__notification_logger.py` (a matching bug would stop the log Gordon reads; the logger stays a dumb D-Bus eavesdropper), `tail -F` with no cursor (loses the lines that land during a restart), letting the notify-watch mod run the actions (down whenever Gordon is down, restarting, or compacting, which is exactly when the standup session must still start), and a per-fire line in the mod's prompt to say "consumed" (a race between two readers of one file; the pattern file below makes consumption a function of the store, not of timing).

## Data flow

1. `notification-logger.service` appends `date time\tapp\tsummary\tbody`.
2. `remind match` (watcher pass): freshness, dedupe, regex, fire or queue.
3. `fire <id> [token]`: runs `--command` with the popup on stdin and `$REMINDER_MATCH`, never interpolated. Exit 0 is success, logged to `fire.log` and `runs/<id>.log`, nothing else. Non-zero is an error: one line to Gordon through the notification log (`notify_gordon`, the `--to gordon` path), mail when `--notify mail`. The record stays active either way.
4. `sync` derives `~/.local/state/reminders/notify-patterns.txt` (one active `on_notify` regex per line, same format as `ignore.txt`) next to the at jobs and the crontab block. The notify-watch mod reads it as a second ignore source, so a popup an on-notify reminder claims never reaches Gordon; Gordon hears about it only through the error line.
5. Every `match` pass touches `notify.alive`. The mod applies the pattern file only while that heartbeat is under 30 seconds old; otherwise the popup reaches Gordon as before and the prompt note says the watcher is down. Lines whose app is `reminder` are never pattern-filtered, so error lines always get through.

## Failure modes

- Replay after a restart or reboot: a line whose timestamp is older than `REMINDER_NOTIFY_WINDOW` (900s) is skipped and logged as `stale`.
- Log rewrite (`trim_if_big` shrinks the file in place): a cursor past EOF or not on a line boundary resets to 0; the window and the dedupe file (`notify.seen`, sha of the record, pruned past the window) keep that from refiring.
- At most once per popup and reminder: the cursor is written before any fire; `notify.seen` covers cursor resets.
- Popup text in a shell: the popup travels as stdin and an env var; the at job body carries only the id and a hex token; `.command` is the only text `bash -c` sees, and it is the author's.
- Loop: a record whose app field is `reminder` (the engine's own gordon lines) never triggers, so an error line cannot re-match.
- Watcher down, crashed or never enabled: the heartbeat goes stale, the mod stops applying the patterns, and Gordon sees the popup and the note. A match the watcher finds late is logged as `stale` and nothing more: Gordon already had the popup, and a line per old match replays history into his session (six such lines on the first live run, before the first pass started at EOF).
- First run with no cursor: starts at the end of the log, the mod's rule, so history never fires or logs.
- Hung command: `timeout` (`REMINDER_NOTIFY_TIMEOUT`, 120s) ends it and the run is an error.
- Delayed fire while the box was off: atd runs overdue queue `n` jobs at boot; `fire.log` records `late`.

## Not done

`--on-notify` takes only `--action exec`; `show` and `open` would need a dialog that cannot snooze an eventful record. `--on-hit` and `--on-miss` do not apply (exit 0 is the whole verdict).
