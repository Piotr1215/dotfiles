# GitHub notification cleanup

Mark merged or closed pull request notifications Done, regardless of author or
notification reason. Keep open PR, issue and release notifications.

Requires Python 3 and an existing noninteractive `gh` login for github.com. The
script creates or stores no token. GitHub's notification API requires a classic
token; private PR metadata also requires the account's existing repo access.

## Preview and run

Preview sends GET requests only:

```sh
python3 scripts/__github_notifications.py
```

Apply rechecks each candidate's notification timestamp and PR state, then calls
`DELETE /notifications/threads/{id}` to mark it Done:

```sh
python3 -u scripts/__github_notifications.py --apply
```

Updated threads wait for the next run. Reopened PRs and threads with unreadable
metadata stay. API failures return a nonzero status and appear in the final summary.

The API can return threads already marked Done. The script records successful
writes in `${XDG_STATE_HOME:-$HOME/.local/state}/github-notifications/done.json`
and skips unchanged threads on later runs. A new timestamp triggers another
evaluation. Writes are atomic; apply runs share a lock. Keep this file when
updating the installed script. Use `--state-file PATH` to select another location.

## Personal cron installation

Install a copy independent of the feature worktree:

```sh
install -d -m 700 "$HOME/.local/libexec" "$HOME/.local/state/github-notifications"
install -m 755 scripts/__github_notifications.py "$HOME/.local/libexec/__github_notifications.py.new"
mv "$HOME/.local/libexec/__github_notifications.py.new" "$HOME/.local/libexec/__github_notifications.py"
```

Back up the crontab and preserve existing entries. Add this entry outside any
managed reminder block. With the system timezone set to Europe/Berlin, it runs
every 15 minutes, Monday to Friday, from 08:07 through 19:52.

```cron
# Mark merged and closed GitHub pull request notifications Done.
7,22,37,52 8-19 * * 1-5 /usr/bin/flock -n "$HOME/.local/state/github-notifications/cron.lock" $HOME/dev/dotfiles/scripts/__cron_run.sh __github_notifications -- /usr/bin/python3 -u "$HOME/.local/libexec/__github_notifications.py" --apply
```

The outer lock prevents overlapping cron wrappers from interleaving logs.
The wrapper path stays unquoted so the existing cron widget can parse its job name.
Successful runs return 0 and stay quiet. Each run writes a summary to the cron
dashboard and `~/.local/state/cron-jobs/__github_notifications.log`, without
sending a notification. The companion JSON file records the last run's status
and counts.

To stop automatic cleanup, remove only this comment and cron entry. Done threads
remain in GitHub's Done view for its documented retention period. The script
neither unsubscribes from threads nor changes review requests.

## Tests

```sh
python3 -m unittest discover -s tests/python -p test_github_notifications.py -v
```

Offline tests cover preview, open and closed PRs, pagination, changed/reopened
threads, unknown metadata, API failures, receipt persistence and overlapping runs.
The repository's Python CI discovers the test file automatically.

API and inbox behavior:
[notifications API](https://docs.github.com/en/rest/activity/notifications),
[inbox triage](https://docs.github.com/en/subscriptions-and-notifications/how-tos/viewing-and-triaging-notifications/managing-notifications-from-your-inbox).
