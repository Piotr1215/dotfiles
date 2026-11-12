import importlib.util
import json
import os
from pathlib import Path
import subprocess

import pytest

PATH = Path(__file__).resolve().parents[2] / "scripts" / "__handoff_navigate.py"
spec = importlib.util.spec_from_file_location("handoff_navigate", PATH)
nav = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nav)
UUID = "aa476008-cc54-48fe-8530-ea217db834e7"


@pytest.fixture(autouse=True)
def nav_log(tmp_path, monkeypatch):
    """Keep the navigator's state log out of the real home."""
    monkeypatch.setenv("HANDOFF_NAV_LOG", str(tmp_path / "nav.log"))
    (tmp_path / "nav.log").write_text("")
    return tmp_path / "nav.log"


def task(*annotations, tags=None):
    return {"uuid": UUID, "tags": ["piotr"] if tags is None else tags,
            "annotations": [{"description": text} for text in annotations]}


@pytest.mark.parametrize("url", [
    "http://github.com/a",
    "https://user@github.com/a", "https://github.com:443/a", "file:///tmp/a",
    "https://github.com\\@evil.test/a", "https://github.com/a\n",
    "http://claude.ai/artifact/id",
])
def test_rejects_unsafe_urls(url):
    with pytest.raises(ValueError):
        nav.checked_url(url)


def test_slack_target_wins_over_draft_links():
    row = task("target: slack:D0AQM8BAW64/1793917323.756099 https://loft-labs-inc.slack.com/archives/D0AQM8BAW64/p1793917323756099",
               "draft: https://github.com/loft-sh/ai-agents/pull/206")
    assert nav.destination(row) == "https://loft-labs-inc.slack.com/archives/D0AQM8BAW64/p1793917323756099"


@pytest.mark.parametrize("channel", ["C08EQAJQD24", "D0AQM8BAW64"])
def test_slack_top_target_accepts_channel_and_dm_links(channel):
    url = f"https://loft-labs-inc.slack.com/archives/{channel}"
    assert nav.destination(task(f"target: slack:{channel}/top {url}")) == url
    assert nav.destination(task(f"target: slack:{channel}/top")) == url
    with pytest.raises(ValueError, match="Slack target and permalink disagree"):
        nav.destination(task(f"target: slack:{channel}/top https://loft-labs-inc.slack.com/archives/COTHER"))
    message = f"{url}/p1793917323756099"
    assert nav.destination(task(f"target: slack:{channel}/top {message}")) == message


def test_slack_thread_permalink_and_target_without_link():
    stamp = "1793917323.756099"
    url = "https://loft-labs-inc.slack.com/archives/C0123/p1793917323756099"
    assert nav.destination(task(f"target: slack:C0123/{stamp} {url}")) == url
    assert nav.destination(task(f"target: slack:C0123/{stamp}")) == f"{url}?thread_ts={stamp}"


def test_slack_target_rejects_mismatched_permalink():
    with pytest.raises(ValueError, match=UUID):
        nav.destination(task("target: slack:C0123/1793917323.756099 https://github.com/archives/C0123/p1793917323756099"))


def test_floater_validation_identifies_task_from_environment(monkeypatch):
    monkeypatch.setenv("HANDOFF_TASK_UUID", UUID)
    row = task("target: slack:C0123/1793917323.756099 https://github.com/archives/C0123/p1793917323756099")
    del row["uuid"]
    with pytest.raises(ValueError, match=UUID):
        nav.destination(row)


@pytest.mark.parametrize(("annotation", "url"), [
    ("link: https://mail.google.com/mail/u/1/#inbox/abc", "https://mail.google.com/mail/u/1/#inbox/abc"),
    ("link: https://claude.ai/artifact/abc", "https://claude.ai/artifact/abc"),
    ("done-when: pr-reviewed loft-sh/architecture#26 since 2026-11-06", "https://github.com/loft-sh/architecture/pull/26"),
    ("done-when: pr-merged architecture#26", "https://github.com/loft-sh/architecture/pull/26"),
    ("done-when: linear DEVOPS-1825 released", "https://linear.app/loft/issue/DEVOPS-1825"),
])
def test_destination_forms(annotation, url):
    assert nav.destination(task(annotation)) == url


def test_tab_note_opens_console_url_and_suppresses_legacy_command(monkeypatch):
    row = task('tab: https://console.example.com/settings', 'cmd: xdg-open https://console.example.com/settings')
    assert nav.destination(row) == 'https://console.example.com/settings'
    assert nav.annotation_urls(row) == ['https://console.example.com/settings']
    monkeypatch.setattr(nav, 'open_command_window', lambda *args: pytest.fail('legacy command shown'))
    nav.act_on_kind(row)


def test_other_handoff_start_opens_newest_explicit_link(monkeypatch, tmp_path):
    uuid = "a1586e1a-affd-4fb2-b0bb-d387f3e9247d"
    url = "https://link.rippling.com/inbox?path=/inbox/&view=needs-attention"
    row = dict(task("mail: old mail", f"link: {url}"), uuid=uuid,
               start="20261112T080000Z", kind="other")
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    brief = tmp_path / "brief"
    brief.write_text(f"<!-- begin open -->\n{url}\n<!-- end open -->\n")
    calls = []
    def run(args, **kwargs):
        if args[-1] == "export":
            return subprocess.CompletedProcess(args, 0, json.dumps([row]))
        return subprocess.CompletedProcess(args, 0, str(brief) if "prepare" in args else "")
    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "")
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal: calls.append(urls))
    monkeypatch.setattr(nav, "live_agent_session", lambda _: "")
    floater_spec = importlib.util.spec_from_file_location("handoff_floater_file", PATH.with_name("__handoff_floater_file.py"))
    floater = importlib.util.module_from_spec(floater_spec)
    floater_spec.loader.exec_module(floater)
    assert floater.open_urls(row) == [url]
    assert nav.destination(row) == url
    assert nav.destination(dict(row, annotations=[{"entry": "1", "description": "link: https://old.example/page"},
                                                   {"entry": "2", "description": f"link: {url}"}])) == url
    assert nav.main(["start", uuid]) == 0
    assert calls == [[url]]


@pytest.mark.parametrize("url", ["http://example.com/a", "https://user@example.com/a", "https://example.com:443/a"])
def test_other_handoff_link_keeps_url_safety_checks(url):
    with pytest.raises(ValueError):
        nav.destination(task(f"link: {url}"))


def test_legacy_quoted_page_and_slack_permalink_are_destinations(monkeypatch):
    for url in ('https://mail.google.com/mail/?authuser=a@example.com#all/thread',
                'https://loft-labs-inc.slack.com/archives/C0123/p1700000000000100'):
        row = task(f"cmd: xdg-open '{url}'")
        assert nav.annotation_urls(row) == [url]
        monkeypatch.setattr(nav, 'open_command_window', lambda *args: pytest.fail('legacy command shown'))
        nav.act_on_kind(row)


def test_mail_sent_uses_newest_message_and_account(tmp_path, monkeypatch):
    binary = tmp_path / "notmuch"
    binary.write_text("#!/bin/sh\ncase \"$2\" in\n"
                      "--output=messages) printf '%s\\n' 'id:new+id@example.com' 'id:old@example.com';;\n"
                      f"--output=files) printf '%s\\n' '{Path.home()}/.local/share/mail/work@example.com/Inbox/new/file';;\n"
                      "esac\n")
    binary.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path))
    done = "done-when: mail-sent 000000000000cae0 since 2026-11-10"
    assert nav.destination(task(done)) == ("https://mail.google.com/mail/?authuser=work@example.com"
                                            "#search/rfc822msgid%3Anew%2Bid%40example.com")
    assert nav.destination(task(done, "link: https://github.com/a")) == "https://github.com/a"


def test_mail_sent_missing_notmuch_or_message_returns_none(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", str(tmp_path))
    row = task("done-when: mail-sent 000000000000cae0")
    assert nav.destination(row) is None
    binary = tmp_path / "notmuch"
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o755)
    assert nav.destination(row) is None


def test_ordinary_row_and_missing_destination_do_nothing():
    assert nav.destination(task("link: https://github.com/a", tags=[])) is None
    assert nav.destination(task("done-when: manual acknowledgement")) is None


def test_latest_field_wins_but_invalid_field_does_not_fall_through():
    assert nav.destination(task("link: https://github.com/old", "link: https://github.com/new")) == "https://github.com/new"
    with pytest.raises(ValueError):
        nav.destination(task("target: https://evil.test/", "link: https://github.com/good"))


def test_ambiguous_links_rejected():
    with pytest.raises(ValueError):
        nav.destination(task("link: https://github.com/a https://linear.app/b"))


def test_agent_session_uses_latest_annotation():
    assert nav.agent_session(task("agent: old-session", "agent: slack-reply-anvesh")) == "slack-reply-anvesh"
    assert nav.agent_session(task("link: https://github.com/a")) == ""


def test_handoff_owner_prefers_annotation_then_live_session(monkeypatch):
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "live-session")
    assert nav.handoff_owner(task("agent: owner", "tmux session newer")) == "owner"
    assert nav.handoff_owner(task("tmux session live-session")) == "live-session"
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "")
    assert nav.handoff_owner(task("link: https://github.com/a")) == "handoffs"


def test_annotation_urls_include_every_explicit_link_and_latest_target():
    assert nav.annotation_urls(task(
        "target: https://linear.app/loft/issue/DEVOPS-1",
        "link: https://app.notion.com/p/runbook",
        "link: https://app.notion.com/p/access",
    )) == [
        "https://linear.app/loft/issue/DEVOPS-1",
        "https://app.notion.com/p/runbook",
        "https://app.notion.com/p/access",
    ]


def test_agent_sessions_read_agent_and_tmux_session_notes_newest_first():
    row = task("agent: old-worker", "12:42 tmux session fada-s-key-acts (dotfiles): s acts per kind",
               "tmux session fada-constitution-s")
    assert nav.agent_sessions(row) == ["fada-constitution-s", "fada-s-key-acts", "old-worker"]
    assert nav.agent_session(row) == "fada-constitution-s"


def test_live_agent_session_skips_sessions_tmux_does_not_have(monkeypatch):
    calls = []
    monkeypatch.setattr(nav.subprocess, "run", lambda args, **kwargs: calls.append(args) or
                        subprocess.CompletedProcess(args, 0 if args[-1] == "=older-live" else 1))
    row = task("agent: older-live", "tmux session newest-gone")
    assert nav.live_agent_session(row) == "older-live"
    assert calls == [["tmux", "has-session", "-t", "=newest-gone"],
                     ["tmux", "has-session", "-t", "=older-live"]]
    monkeypatch.setattr(nav.subprocess, "run", lambda args, **kwargs: subprocess.CompletedProcess(args, 1))
    assert nav.live_agent_session(row) == ""


@pytest.mark.parametrize(("urls", "layout"), [
    (["https://loft-labs-inc.slack.com/archives/C0123"], "8"),
    (["https://github.com/a"], "2"),
    (["https://loft-labs-inc.slack.com/archives/C0123", "https://github.com/a"], "8"),
    (["https://github.com/a", "https://linear.app/b"], "2"),
])
def test_layout_and_url_arguments(monkeypatch, urls, layout):
    """Desktop Slack and browser pages use their respective layouts."""
    monkeypatch.setattr(nav, "terminal_monitor", lambda _: "HDMI-0")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    calls = []
    monkeypatch.setenv("HANDOFF_BROWSER_COMMAND", "/browser")
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append((args, kw)))
    nav.navigate_many(urls, "111")
    layouts = [(args, kw) for args, kw in calls if args[0].endswith("__layouts.sh")]
    assert [args[-1] for args, _ in layouts] == ([layout] if layout else [])
    if layout:
        assert layouts[0][1]["env"]["LAYOUT_ALACRITTY_WINDOW"] == "111"
    for url in urls:
        expected = nav.slack_deep_link(url) if "slack.com" in url else url
        assert any(expected in args for args, _ in calls)


def test_multiple_browser_links_open_once_as_background_tabs(monkeypatch):
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    monkeypatch.setattr(nav, "terminal_monitor", lambda _: "HDMI-0")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    calls = []
    monkeypatch.delenv("HANDOFF_BROWSER_COMMAND", raising=False)
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append((args, kw)))
    nav.navigate_many(["https://github.com/a", "https://linear.app/b", "https://github.com/a"], "111")
    assert [args[1:] for args, _ in calls[:-1]] == [["https://github.com/a"], ["https://linear.app/b"]]
    assert all(kw["timeout"] == 1.0 for _, kw in calls[:-1])


def test_draft_row_opens_slack_in_desktop(monkeypatch):
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    monkeypatch.setattr(nav, "terminal_monitor", lambda _: "HDMI-0")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    calls = []
    monkeypatch.delenv("HANDOFF_BROWSER_COMMAND", raising=False)
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args))
    nav.navigate_many([ENTERPRISE, "https://github.com/a"], "111", slack_tabs=True)
    assert calls[0] == [str(nav.ROOT / "__slack_open.sh"), nav.slack_deep_link(ENTERPRISE)]
    assert calls[1][1:] == ["https://github.com/a"]


@pytest.mark.parametrize("edited", ["", "https://github.com/edited"])
def test_work_reads_edits_and_stops_previous_task(monkeypatch, tmp_path, edited):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("TMUX_PANE", "%18")
    current = dict(task("draft: https://github.com/ignored", "agent: slack-reply-anvesh",
                        "link: https://app.notion.com/p/runbook",
                        "link: https://app.notion.com/p/access"), start="20261106T000000Z")
    old = dict(task(), uuid="bb476008-cc54-48fe-8530-ea217db834e7", start="20261105T000000Z")
    brief = tmp_path / "brief"
    brief.write_text(f"<!-- begin open -->\n{edited}\n<!-- end open -->\n")
    calls = []
    def run(args, **kw):
        calls.append(args)
        if args[-1] == "export":
            return subprocess.CompletedProcess(args, 0, json.dumps([old, current] if "+ACTIVE" in args else [current]))
        if "prepare" in args:
            assert kw["env"]["HANDOFF_TASK_UUID"] == UUID
            return subprocess.CompletedProcess(args, 0, str(brief))
        return subprocess.CompletedProcess(args, 0, "")
    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal, slack_tabs=False: calls.append((urls, terminal)))
    monkeypatch.setattr(nav, "live_agent_session", lambda row: nav.agent_session(row))
    monkeypatch.setattr(nav, "attach_agent_session", lambda session: calls.append(("agent", session)))
    assert nav.main(["start", UUID]) == 0
    assert (([edited] if edited else []) + ["https://app.notion.com/p/runbook", "https://app.notion.com/p/access"], "111") in calls
    assert ("agent", "slack-reply-anvesh") in calls
    assert any("stop" in call and "rc.hooks=off" in call for call in calls)
    # Not a Slack row: no brief floater (Piotr, 11 Nov 12:44).
    assert not any(isinstance(call, list) and "pin" in call for call in calls)
    assert nav.main(["stop", UUID]) == 0
    assert calls[-2][1:3] == ["close", UUID]
    assert calls[-1][-1] == "1"


def test_empty_open_block_and_fallback(tmp_path):
    brief = tmp_path / "brief"
    brief.write_text("<!-- begin open -->\n\n<!-- end open -->\n")
    assert nav.open_block(brief) == []


@pytest.mark.parametrize(("notes", "expected"), [
    (("link: https://github.com/a", "cmd: echo hello"),
     [("navigate", ["https://github.com/a"]), ("command", "echo hello")]),
    (("link: https://github.com/a",),
     [("navigate", ["https://github.com/a"]), ("agent", "agent-session")]),
    (("cmd: echo hello",), [("navigate", []), ("command", "echo hello")]),
])
def test_start_navigates_before_kind_action(monkeypatch, tmp_path, notes, expected):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("TMUX_PANE", "%18")
    row = dict(task(*notes, "agent: agent-session"), start="20261106T000000Z")
    brief = tmp_path / "brief"
    brief.write_text("<!-- begin open -->\n\n<!-- end open -->\n")
    calls = []

    def run(args, **kwargs):
        if args[-1] == "export":
            return subprocess.CompletedProcess(args, 0, json.dumps([row]))
        return subprocess.CompletedProcess(args, 0, str(brief) if "prepare" in args else "")

    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal, slack_tabs=False: calls.append(("navigate", urls)))
    monkeypatch.setattr(nav, "open_command_window", lambda uuid, command, focus=True: calls.append(("command", command)))
    monkeypatch.setattr(nav, "live_agent_session", lambda row: nav.agent_session(row))
    monkeypatch.setattr(nav, "attach_agent_session", lambda session: calls.append(("agent", session)))
    assert nav.main(["start", UUID]) == 0
    assert calls == expected


def test_empty_block_uses_done_when_and_navigation_failure_still_pins(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("TMUX_PANE", "%18")
    row = dict(task("done-when: pr-merged architecture#26"), start="20261106T000000Z", tags=["piotr", "draft"])
    brief = tmp_path / "brief"
    brief.write_text("<!-- begin open -->\n\n<!-- end open -->\n")
    calls = []

    def run(args, **kwargs):
        calls.append(args)
        if args[-1] == "export":
            return subprocess.CompletedProcess(args, 0, json.dumps([row]))
        return subprocess.CompletedProcess(args, 0, str(brief) if "prepare" in args else "")

    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    def fail(urls, terminal, slack_tabs=False):
        assert urls == ["https://github.com/loft-sh/architecture/pull/26"]
        raise OSError("navigation failed")
    monkeypatch.setattr(nav, "navigate_many", fail)
    with pytest.raises(OSError):
        nav.main(["start", UUID])
    assert calls[-1][1:3] == ["pin", UUID]


def test_non_handoff_never_opens_floater(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    calls = []
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args) or subprocess.CompletedProcess(args, 0, json.dumps([task(tags=[])])))
    assert nav.main([UUID]) == 0
    assert len(calls) == 1


def test_reply_permalink_matches_thread_target():
    url = "https://loft-labs-inc.slack.com/archives/C07G0T9HS4U/p1793971823896409?thread_ts=1793868031.988299&cid=C07G0T9HS4U"
    assert nav.destination(task("target: slack:C07G0T9HS4U/1793868031.988299 " + url)) == url
    with pytest.raises(ValueError):
        nav.destination(task("target: slack:C07G0T9HS4U/1793868031.988299 " + url.replace("thread_ts=1793868031", "thread_ts=1793868032")))


def test_delayed_old_worker_cannot_stop_newer(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    old = dict(task(), start="20261106T000000Z")
    new = dict(old, uuid="bb476008-cc54-48fe-8530-ea217db834e7", start="20261106T000005Z")
    calls = []
    def run(args, **kwargs):
        calls.append(args)
        return subprocess.CompletedProcess(args, 0, json.dumps([old, new] if "+ACTIVE" in args else [old]))
    monkeypatch.setattr(nav, "run", run)
    assert nav.main(["start", UUID]) == 0
    assert any("stop" in args and UUID in args for args in calls)
    assert not any("stop" in args and new["uuid"] in args for args in calls)


@pytest.mark.parametrize(("url", "expected"), [
    ("https://slack.com/archives/C123/p1234567890123456", "slack://channel?team=T0123&id=C123&message=1234567890.123456&thread_ts=1234567890.123456"),
    ("https://loft-labs-inc.slack.com/archives/C0123/p1793895191898810?thread_ts=1793895191.898809", "slack://channel?team=T0123&id=C0123&message=1793895191.898810&thread_ts=1793895191.898809"),
    ("https://loft-labs-inc.slack.com/archives/C08EQAJQD24", "slack://channel?team=T0123&id=C08EQAJQD24"),
    ("https://loft-labs-inc.slack.com/archives/C0123/p1793917323756099", "slack://channel?team=T0123&id=C0123&message=1793917323.756099&thread_ts=1793917323.756099"),
    ("https://loft-labs-inc.slack.com/archives/C0123/p1793917323756099?thread_ts=1793917323.756099", "slack://channel?team=T0123&id=C0123&message=1793917323.756099&thread_ts=1793917323.756099"),
])
def test_slack_desktop_links_never_open_browser(monkeypatch, url, expected):
    monkeypatch.setattr(nav, "terminal_monitor", lambda _: "HDMI-0")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    calls = []
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args))
    monkeypatch.setattr(nav.subprocess, "Popen", lambda *a, **kw: pytest.fail("opened Chrome"))
    nav.navigate_many([url], "111")
    assert calls[0] == [str(nav.ROOT / "__slack_open.sh"), expected]


def test_missing_slack_team_does_not_open_browser(monkeypatch, tmp_path):
    monkeypatch.delenv("SLACK_TEAM_ID", raising=False)
    monkeypatch.setenv("SLACK_OPEN_TEAMS_CONFIG", str(tmp_path / "missing"))
    with pytest.raises(ValueError, match="team ID missing"):
        nav.slack_deep_link("https://loft-labs-inc.slack.com/archives/C0123")


def test_start_leaves_agent_spawned_row_running(monkeypatch, tmp_path):
    """S on one handoff must not stop a row that key 4 handed to an agent (9 Nov)."""
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    current = dict(task(), start="20261109T125734Z")
    agent_row = dict(task(tags=["piotr", "claude", "started"]),
                     uuid="bb476008-cc54-48fe-8530-ea217db834e7", start="20261109T125651Z")
    calls = []
    def run(args, **kwargs):
        calls.append(args)
        if args[-1] == "export":
            return subprocess.CompletedProcess(args, 0, json.dumps([agent_row, current] if "+ACTIVE" in args else [current]))
        return subprocess.CompletedProcess(args, 0, "")
    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    monkeypatch.setattr(nav, "open_block", lambda _, **kwargs: [])
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal, slack_tabs=False: None)
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "")
    assert nav.main(["start", UUID]) == 0
    assert not any("stop" in args for args in calls)
    assert not any("pin" in args for args in calls)


ENTERPRISE = "https://vcluster-internal.enterprise.slack.com/archives/C0CE21P1C3H/p1793963101837439"


def test_enterprise_slack_permalink_target_opens_thread(monkeypatch):
    """Slack now hands out vcluster-internal.enterprise permalinks for the same workspace (9 Nov)."""
    row = task(f"target: slack:C0CE21P1C3H/1793963101.837439 {ENTERPRISE}")
    assert nav.destination(row) == ENTERPRISE
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    assert nav.slack_deep_link(ENTERPRISE) == (
        "slack://channel?team=T0123&id=C0CE21P1C3H"
        "&message=1793963101.837439&thread_ts=1793963101.837439")


def test_enterprise_slack_permalink_still_must_match_target():
    with pytest.raises(ValueError, match="Slack target and permalink disagree"):
        nav.destination(task(f"target: slack:C0CE21P1C3H/1793963101.837440 {ENTERPRISE}"))
    with pytest.raises(ValueError):
        nav.destination(task("target: slack:C0CE21P1C3H/1793963101.837439 "
                             "https://evil.enterprise.slack.com/archives/C0CE21P1C3H/p1793963101837439"))


def test_enterprise_slack_permalink_opens_desktop_beside_browser(monkeypatch):
    monkeypatch.setattr(nav, "terminal_monitor", lambda _: "HDMI-0")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    calls = []
    monkeypatch.setenv("HANDOFF_BROWSER_COMMAND", "/browser")
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args))
    nav.navigate_many([ENTERPRISE, "https://github.com/a"], "111")
    assert calls[0] == [str(nav.ROOT / "__slack_open.sh"), nav.slack_deep_link(ENTERPRISE)]
    assert ["/browser", "https://github.com/a"] in calls
    assert calls[-1][-1] == "8"


def test_brief_without_open_block_still_opens_task_links(monkeypatch, tmp_path):
    """S while the brief is open in the editor: prepare defers, so the block is missing (9 Nov)."""
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("TMUX_PANE", "%3")
    row = dict(task(f"target: slack:C0CE21P1C3H/1793963101.837439 {ENTERPRISE}",
                    "link: https://linear.app/loft/issue/DEVOPS-1798"), start="20261109T125819Z")
    brief = tmp_path / "brief"
    brief.write_text("# brief without an open block\n")
    calls = []
    def run(args, **kwargs):
        calls.append(args)
        if args[-1] == "export":
            return subprocess.CompletedProcess(args, 0, json.dumps([row]))
        return subprocess.CompletedProcess(args, 0, str(brief) if "prepare" in args else "")
    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal, slack_tabs=False: calls.append((urls, terminal)))
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "")
    assert nav.main(["start", UUID]) == 0
    assert ([ENTERPRISE, "https://linear.app/loft/issue/DEVOPS-1798"], "111") in calls
    assert not any(isinstance(call, list) and "pin" in call for call in calls)


# Kind actions on s (9 Nov, Piotr): "this would mean action on start so like
# [the push handoff] would open terminal with prepopulated push command".
PUSH = "git -C ~/dev/dotfiles push"


def fake_bin(tmp_path, name, body):
    path = tmp_path / name
    path.write_text("#!/usr/bin/env bash\n" + body)
    path.chmod(0o755)
    return path


@pytest.fixture
def fake_tmux(tmp_path, monkeypatch):
    """A tmux on disk that logs each argv NUL separated, one call per line."""
    log = tmp_path / "tmux.log"
    tmux = fake_bin(tmp_path, "tmux", f"""
printf '%s\\0' "$@" >> {log}; printf '\\n' >> {log}
case "$1" in
  display-message) if [[ "$*" == *'#{{session_id}}'* ]]; then echo '$9'; else echo '$4'; fi ;;
  new-window|new-pane) echo '%99' ;;
esac
""")
    monkeypatch.setenv("HANDOFF_TMUX_COMMAND", str(tmux))
    monkeypatch.setenv("TMUX_PANE", "%18")
    def calls():
        if not log.exists():
            return []
        return [line.split("\0") for line in log.read_text().split("\0\n") if line]
    return calls


@pytest.fixture
def fake_clipboard(tmp_path, monkeypatch):
    """xclip and wl-copy that keep what they were given; wl-copy fails on demand."""
    out = tmp_path / "clipboard"
    xclip = fake_bin(tmp_path, "xclip", f'printf "xclip %s\\n" "$*" >> {out}.argv; cat > {out}\n')
    wl = fake_bin(tmp_path, "wl-copy", f'printf "wl-copy\\n" >> {out}.argv; [[ -f {out}.wlfail ]] && exit 1; cat > {out}\n')
    monkeypatch.setenv("HANDOFF_XCLIP_COMMAND", str(xclip))
    monkeypatch.setenv("HANDOFF_WLCOPY_COMMAND", str(wl))
    monkeypatch.delenv("WAYLAND_DISPLAY", raising=False)
    return out


@pytest.mark.parametrize(("row", "kind"), [
    (dict(task(), kind="command"), "command"),
    (dict(task(tags=["piotr", "draft"]), kind="pr"), "pr"),
    (dict(task(), kind="bogus"), "other"),
    (task(tags=["piotr", "draft"]), "slack"),
    (task(f"cmd: {PUSH}"), "command"),
    (task("done-when: manual"), "other"),
])
def test_task_kind_reads_the_field_and_keeps_legacy_rows_working(row, kind):
    assert nav.task_kind(row) == kind


def test_newest_note_keeps_inner_lines_and_takes_the_latest():
    row = {"annotations": [
        {"entry": "20261109T100002Z", "description": "draft: Hi team\n- one\n- two"},
        {"entry": "20261109T100001Z", "description": "draft: older"},
        {"entry": "20261109T100003Z", "description": "what: not a draft"}]}
    assert nav.newest_note(row, "draft") == "Hi team\n- one\n- two"
    assert nav.newest_note(row, "cmd") == ""


def test_command_kind_types_the_command_in_a_focused_window(fake_tmux):
    """Piotr, 11 Nov: "the floating tmux window should always be in focus"."""
    hostile = "git push; echo $(touch /tmp/pwned) `id` 'q' \"d\" \\ $HOME"
    row = dict(task(f"cmd: {hostile}"), kind="command")
    assert nav.act_on_kind(row) == "command"
    calls = fake_tmux()
    assert calls[0] == ["display-message", "-p", "-t", "%18", "#{session_id}"]
    new = calls[1]
    assert new[:4] == ["new-window", "-P", "-F", "#{pane_id}"] and "-d" not in new
    assert new[new.index("-t") + 1] == "$9:"
    assert new[new.index("-n") + 1] == "handoff-" + UUID[:8]
    # The command is one argv element in the pane's environment, verbatim.
    tail = new[new.index("env"): ]
    assert tail[:3] == ["env", "HANDOFF_CMD=" + hostile, "HANDOFF_UUID=" + UUID]
    assert tail[3] == "HANDOFF_NAVIGATOR=" + str(PATH)
    assert tail[-2:] == ["zsh", "-i"]
    # Enter submits only the fixed prefill, not the command it queues.
    assert calls[2:] == [["send-keys", "-t", "%99", "-l", nav.PREFILL], ["send-keys", "-t", "%99", "Enter"],
                         ]
    assert all(hostile not in arg for call in calls[2:] for arg in call)
    assert "HANDOFF_CMD" in nav.PREFILL


def test_prefill_hook_verifies_once_after_the_command_exits_zero(tmp_path):
    """Piotr, 11 Nov: "once command is ran verify it and close task"."""
    log = tmp_path / "verify.log"
    navigator = fake_bin(tmp_path, "nav", f'printf "%s\\n" "$*" >> {log}\n')
    # sim runs the hooks the way an interactive prompt does around one command.
    script = (nav.PREFILL + "; read -z queued;"
              ' sim() { local f s; for f in $preexec_functions; do $f; done; eval "$1"; s=$?;'
              ' for f in $precmd_functions; do (exit $s); $f; done; };'
              " sim false; sim true; sim true;"   # a failed run stays armed; success verifies once
              ' print -r -- "${precmd_functions[*]}|${preexec_functions[*]}"')
    result = subprocess.run(["zsh", "-fc", script], capture_output=True, text=True, check=True,
                            env={"HANDOFF_CMD": "true", "HANDOFF_UUID": UUID,
                                 "HANDOFF_NAVIGATOR": str(navigator), "TERM": "dumb"})
    assert log.read_text() == f"verify {UUID}\n"
    assert "handoff_rc" not in result.stdout and "handoff_ran" not in result.stdout


def test_prefill_queues_command_without_executing_it(tmp_path):
    marker = tmp_path / "ran"
    command = f"printf done > {marker}"
    result = subprocess.run(["zsh", "-c", nav.PREFILL + '; read -z queued; print -r -- "$queued"'],
                            env={"HANDOFF_CMD": command, "TERM": "dumb"},
                            capture_output=True, text=True, check=True)
    assert result.stdout.strip() == command
    assert not marker.exists()


@pytest.mark.parametrize(("notes", "error"), [
    ((), "no cmd: note"),
    (("cmd: git push\nrm -rf ~",), "one line"),
    (("cmd: git push\tx",), "one line"),
])
def test_command_kind_without_a_usable_command_reports_and_opens_nothing(fake_tmux, capsys, notes, error):
    assert nav.act_on_kind(dict(task(*notes), kind="command")) == "failed"
    assert fake_tmux() == []
    assert error in capsys.readouterr().err


def test_command_kind_outside_tmux_reports_the_remedy(fake_tmux, monkeypatch, capsys):
    monkeypatch.delenv("TMUX_PANE")
    nav.act_on_kind(dict(task(f"cmd: {PUSH}"), kind="command"))
    assert fake_tmux() == []
    assert "press s in the handoffs view" in capsys.readouterr().err


def test_slack_kind_copies_the_newest_draft_with_xclip(fake_clipboard, fake_tmux):
    row = dict(task("draft: old text", "draft: Hi team\n- shipped `x`\n- next $y"), kind="slack")
    row["annotations"][0]["entry"], row["annotations"][1]["entry"] = "20261109T1", "20261109T2"
    assert nav.act_on_kind(row) == "slack"
    assert fake_clipboard.read_text() == "Hi team\n- shipped `x`\n- next $y"
    assert (fake_clipboard.parent / "clipboard.argv").read_text() == "xclip -selection clipboard\n"
    assert fake_tmux() == []


def test_slack_kind_prefers_wl_copy_on_wayland_and_falls_back_to_xclip(fake_clipboard, monkeypatch):
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-0")
    row = dict(task("draft: hello"), kind="slack")
    nav.act_on_kind(row)
    assert (fake_clipboard.parent / "clipboard.argv").read_text() == "wl-copy\n"
    (fake_clipboard.parent / "clipboard.wlfail").write_text("")
    fake_clipboard.write_text("")
    nav.act_on_kind(dict(task("draft: again"), kind="slack"))
    assert fake_clipboard.read_text() == "again"
    assert (fake_clipboard.parent / "clipboard.argv").read_text().splitlines()[-2:] == [
        "wl-copy", "xclip -selection clipboard"]


def test_slack_kind_without_a_clipboard_tool_says_what_to_install(monkeypatch, capsys):
    monkeypatch.setenv("HANDOFF_XCLIP_COMMAND", "/nonexistent/xclip")
    monkeypatch.delenv("WAYLAND_DISPLAY", raising=False)
    nav.act_on_kind(dict(task("draft: hello"), kind="slack"))
    assert "install xclip or wl-copy" in capsys.readouterr().err


def test_slack_kind_with_a_cmd_note_copies_the_draft_and_opens_the_command(fake_clipboard, fake_tmux):
    # 10 Nov, 9069 "Slack: signed transport receipts to Daniel": the row had a
    # draft for Daniel and a cmd: that opens the receipts in Xournal++; s only
    # copied the text. Piotr: "I think there should be app opening them".
    row = dict(task("draft: Hi Daniel, signed receipts are in the folder",
                    "cmd: xournalpp ~/Downloads/eigenbeleg-1.pdf"), kind="slack")
    assert nav.act_on_kind(row) == "slack"
    assert fake_clipboard.read_text() == "Hi Daniel, signed receipts are in the folder"
    calls = fake_tmux()
    # The draft brief keeps the keyboard, so the command pane opens unfocused.
    assert "-d" in calls[1] and "HANDOFF_CMD=xournalpp ~/Downloads/eigenbeleg-1.pdf" in calls[1]
    assert ["select-pane", "-t", "%99"] not in calls


@pytest.mark.parametrize("kind", ["pr", "ack", "other"])
def test_pr_ack_and_other_without_cmd_take_no_extra_action(fake_tmux, fake_clipboard, kind):
    row = dict(task("draft: hello", "done-when: pr-merged architecture#26"), kind=kind)
    assert nav.act_on_kind(row) == "none"
    assert fake_tmux() == []
    assert not fake_clipboard.exists()


def test_agent_row_attaches_live_session_in_a_focused_floating_pane(fake_tmux, monkeypatch):
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "fada-page-guard")
    row = task("12:40 guard the add path. tmux session fada-page-guard")
    assert nav.act_on_kind(row) == "agent"
    calls = fake_tmux()
    assert calls[0] == ["display-message", "-p", "-t", "%18", "#{session_name}"]
    new = calls[1]
    assert new[0] == "new-pane" and "-d" not in new and new[new.index("-T") + 1] == "agent fada-page-guard"
    assert new[new.index("--") + 1:] == ["env", "-u", "TMUX", os.environ["HANDOFF_TMUX_COMMAND"],
                                         "attach-session", "-t", "=fada-page-guard"]
    assert calls[2] == ["select-pane", "-t", "%99"]


def test_agent_row_never_nests_the_session_s_was_pressed_in(fake_tmux, monkeypatch, capsys):
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "$4")
    assert nav.act_on_kind(task("agent: $4")) == "failed"
    assert [c[0] for c in fake_tmux()] == ["display-message"]
    assert "is the session s was pressed in" in capsys.readouterr().err


def start_row(monkeypatch, tmp_path, row):
    """Run main start on one row with the floater, export and navigation faked."""
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("TMUX_PANE", "%18")
    row = dict(row, start="20261109T170000Z")
    brief = tmp_path / "brief"
    brief.write_text("<!-- begin open -->\n\n<!-- end open -->\n")
    order = []
    real_run = nav.run
    def run(args, **kwargs):
        if args and args[0] == "task":
            return subprocess.CompletedProcess(args, 0, json.dumps([row]))
        if "prepare" in args or "pin" in args or "focus" in args:
            order.append(("focus", str(args[2]), args[3]) if args[1] == "focus" else args[1])
            return subprocess.CompletedProcess(args, 0, str(brief))
        return real_run(args, **kwargs)
    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal, slack_tabs=False:
                        order.append(("open", urls) if not slack_tabs else ("open tabs", urls)))
    monkeypatch.setattr(nav, "live_agent_session", lambda row: "")
    monkeypatch.setattr(nav, "attach_agent_session", lambda session: order.append(("agent", session)))
    monkeypatch.setattr(nav, "wait_for_slack_focus", lambda: order.append("slack ready"))
    monkeypatch.setattr(nav, "show_slack_draft", lambda pane, terminal, runtime: order.append(("draft", pane, terminal)))
    assert nav.main(["start", row["uuid"]]) == 0
    return order


@pytest.mark.parametrize("kind", ["ack", "pr", "other", "command", "slack"])
def test_start_prefills_cmd_for_every_kind(monkeypatch, tmp_path, fake_tmux, kind):
    row = dict(task("brief: check credentials", "cmd: echo check", "what: done"),
               kind=kind, tags=["piotr", "ack"], uuid="3726e617-a1b2-464e-8eff-32fc4a2c658c")
    order = start_row(monkeypatch, tmp_path, row)
    calls = fake_tmux()
    assert "HANDOFF_CMD=echo check" in calls[1]
    assert calls[2:4] == [["send-keys", "-t", "%99", "-l", nav.PREFILL], ["send-keys", "-t", "%99", "Enter"]]
    assert not any(isinstance(item, tuple) and item[0] == "agent" for item in order)


def test_start_3726e617_selects_its_sts_command_without_running_it(monkeypatch, tmp_path, fake_tmux):
    row = {"uuid": "3726e617-a1b2-464e-8eff-32fc4a2c658c", "kind": "ack",
           "tags": ["ack", "piotr", "started", "work"], "annotations": [
               {"entry": "20261110T143936Z", "description": "brief: Start runs an STS check"},
               {"entry": "20261110T143945Z", "description": "cmd: aws sts get-caller-identity --profile sandbox-250811347731"},
               {"entry": "20261110T144008Z", "description": "what: profiles fixed"}]}
    start_row(monkeypatch, tmp_path, row)
    calls = fake_tmux()
    assert "HANDOFF_CMD=aws sts get-caller-identity --profile sandbox-250811347731" in calls[1]
    assert calls[2][4] == nav.PREFILL


def test_start_on_a_command_row_focuses_the_command_pane_without_a_brief(monkeypatch, tmp_path, fake_tmux):
    row = dict(task(f"cmd: {PUSH}", "agent: some-worker"), kind="command")
    order = start_row(monkeypatch, tmp_path, row)
    calls = fake_tmux()
    assert [c[0] for c in calls] == ["display-message", "new-window", "send-keys", "send-keys"]
    assert "HANDOFF_CMD=" + PUSH in calls[1]
    assert order == ["prepare", ("open", [])]


def test_start_on_a_slack_row_copies_the_draft_then_opens_the_thread_on_desktop(monkeypatch, tmp_path, fake_clipboard, fake_tmux):
    target = f"target: slack:C0CE21P1C3H/1793963101.837439 {ENTERPRISE}"
    row = dict(task(target, "draft: Hi Jan, merged."), tags=["piotr", "draft"], kind="slack")
    order = start_row(monkeypatch, tmp_path, row)
    assert fake_clipboard.read_text() == "Hi Jan, merged."
    assert fake_tmux() == [["select-window", "-t", "%18"]]
    assert order == ["prepare", ("open", [ENTERPRISE]), "pin", "slack ready", ("draft", "%18", "111"),
                     ("focus", row["uuid"], "%18")]



def test_draft_with_command_returns_to_floater_after_prefill(monkeypatch, tmp_path, fake_tmux, fake_clipboard):
    row = dict(task("draft: hello", "cmd: echo check"), tags=["piotr", "draft"], kind="slack")
    order = start_row(monkeypatch, tmp_path, row)
    calls = fake_tmux()
    assert calls[-1] == ["select-window", "-t", "%18"]
    assert calls[-3:-1] == [["send-keys", "-t", "%99", "-l", nav.PREFILL],
                            ["send-keys", "-t", "%99", "Enter"]]
    assert order[-2:] == [("draft", "%18", "111"), ("focus", row["uuid"], "%18")]


def test_slack_kind_without_draft_tag_also_focuses_the_draft(monkeypatch, tmp_path, fake_tmux, fake_clipboard):
    row = dict(task("draft: hello"), tags=["piotr"], kind="slack")
    order = start_row(monkeypatch, tmp_path, row)
    assert order == ["prepare", ("open", []), "pin", ("draft", "%18", "111"), ("focus", UUID, "%18")]
    assert fake_tmux() == [["select-window", "-t", "%18"]]


def test_start_on_a_pr_row_opens_the_pr_without_a_brief(monkeypatch, tmp_path, fake_tmux, fake_clipboard):
    row = dict(task("done-when: pr-merged architecture#26"), kind="pr")
    order = start_row(monkeypatch, tmp_path, row)
    assert order == ["prepare", ("open", ["https://github.com/loft-sh/architecture/pull/26"])]
    assert fake_tmux() == [] and not fake_clipboard.exists()
    assert "no action" not in (tmp_path / "nav.log").read_text()


def test_start_on_a_row_with_nothing_to_do_logs_it_and_shows_no_brief(monkeypatch, tmp_path, fake_tmux, fake_clipboard):
    row = dict(task("brief: read this", "done-when: manual"), kind="other")
    order = start_row(monkeypatch, tmp_path, row)
    assert order == ["prepare", ("open", [])]
    assert fake_tmux() == []
    assert f"handoff: no action on {UUID}" in (tmp_path / "nav.log").read_text()


def test_start_on_an_agent_row_attaches_its_live_session(monkeypatch, tmp_path, fake_tmux):
    """fada2a27 names its worker as `tmux session <name>`; s attaches it, focused."""
    row = dict(task("12:42 tmux session fada-s-key-acts (dotfiles): s acts per row kind"), kind="other")
    real_live, real_attach = nav.live_agent_session, nav.attach_agent_session
    real_subprocess_run = subprocess.run
    order = start_row(monkeypatch, tmp_path, dict(row))
    assert order == ["prepare", ("open", [])] and fake_tmux() == []   # start_row stubs: no live session
    # With tmux reporting the session alive, the same start attaches it.
    tmux = os.environ["HANDOFF_TMUX_COMMAND"]
    monkeypatch.setattr(nav, "live_agent_session", real_live)
    monkeypatch.setattr(nav, "attach_agent_session", real_attach)
    monkeypatch.setattr(nav.subprocess, "run", lambda args, **kw: subprocess.CompletedProcess(args, 0)
                        if args[:2] == [tmux, "has-session"] else real_subprocess_run(args, **kw))
    assert nav.act_on_kind(row) == "agent"
    calls = fake_tmux()
    assert [c[0] for c in calls] == ["display-message", "new-pane", "select-pane"]
    assert calls[1][-1] == "=fada-s-key-acts"


def test_verify_closes_the_row_when_its_probe_proves_done(tmp_path, monkeypatch, capsys):
    probe = fake_bin(tmp_path, "probe", f'echo "$*" > {tmp_path}/probe.argv; echo "{UUID[:8]} done: PR merged"; exit 2\n')
    tw = fake_bin(tmp_path, "tw", f'echo "$*" >> {tmp_path}/tw.argv\n')
    monkeypatch.setenv("HANDOFF_PROBE_COMMAND", str(probe))
    monkeypatch.setenv("HANDOFF_TW_WRAPPER", str(tw))
    assert nav.verify(task("cmd: gh pr merge 26", "done-when: pr-merged loft-sh/architecture#26")) == 0
    assert (tmp_path / "probe.argv").read_text() == f"run --uuid {UUID}\n"
    assert not (tmp_path / "tw.argv").exists()
    assert "closed aa476008 by done-when probe" in capsys.readouterr().err


def test_verify_keeps_an_unproved_row_open_with_the_reason(tmp_path, monkeypatch, capsys):
    probe = fake_bin(tmp_path, "probe", f'echo "{UUID[:8]} open: PR still open"; exit 0\n')
    tw = fake_bin(tmp_path, "tw", f'printf "%s|" "$@" >> {tmp_path}/tw.argv\n')
    monkeypatch.setenv("HANDOFF_PROBE_COMMAND", str(probe))
    monkeypatch.setenv("HANDOFF_TW_WRAPPER", str(tw))
    monkeypatch.setattr(nav, "task_export", lambda *args: [dict(task(), status="pending")])
    assert nav.verify(task("done-when: pr-merged loft-sh/architecture#26")) == 1
    assert (tmp_path / "tw.argv").read_text() == (
        f"--all|note|{UUID}|s: cmd exited 0; done-when not proved ({UUID[:8]} open: PR still open); row stays open|")
    output = capsys.readouterr()
    assert (output.out + output.err).count("row stays open") == 1


@pytest.mark.parametrize("notes", [(), ("done-when: manual Piotr reads the page",)])
def test_verify_without_a_machine_checkable_probe_never_runs_it(tmp_path, monkeypatch, notes):
    tw = fake_bin(tmp_path, "tw", f'printf "%s|" "$@" >> {tmp_path}/tw.argv\n')
    monkeypatch.setenv("HANDOFF_PROBE_COMMAND", "/nonexistent/probe")
    monkeypatch.setenv("HANDOFF_TW_WRAPPER", str(tw))
    monkeypatch.setattr(nav, "task_export", lambda *args: [dict(task(), status="pending")])
    assert nav.verify(task(*notes)) == 1
    assert "no machine-checkable done-when; row stays open" in (tmp_path / "tw.argv").read_text()



def test_verify_reports_previously_closed_probe_row_without_note(tmp_path, monkeypatch, capsys):
    probe = fake_bin(tmp_path, "probe", "exit 0\n")
    monkeypatch.setenv("HANDOFF_PROBE_COMMAND", str(probe))
    row = dict(task("done-when proved: merged (__handoff_probe.py)"), status="completed")
    monkeypatch.setattr(nav, "task_export", lambda *args: [row])
    monkeypatch.setenv("HANDOFF_TW_WRAPPER", str(tmp_path / "must-not-run"))
    assert nav.verify(task("done-when: pr-merged repo#1")) == 0
    output = capsys.readouterr()
    assert "already closed by done-when probe" in output.err
    assert "row stays open" not in output.err + output.out


def test_verify_handles_close_during_note(tmp_path, monkeypatch, capsys):
    tw = fake_bin(tmp_path, "tw", "exit 0\n")
    monkeypatch.setenv("HANDOFF_TW_WRAPPER", str(tw))
    rows = iter([dict(task(), status="pending"), dict(task(), status="completed")])
    monkeypatch.setattr(nav, "task_export", lambda *args: [next(rows)])
    assert nav.verify(task("done-when: manual check")) == 0
    assert "already closed by another action (actor unknown)" in capsys.readouterr().err


def test_xdg_open_filters_noise_but_preserves_errors(tmp_path):
    opener = fake_bin(tmp_path, "xdg-open", 'echo "Opening in existing browser session."; echo "zygote_linux.cc:662 Broken pipe" >&2; echo "real failure" >&2; exit 3\n')
    script = nav.PREFILL + '; read -z queued; xdg-open url; print -r -- "status=$?"'
    result = subprocess.run(["zsh", "-fc", script], capture_output=True, text=True,
                            env={"PATH": str(tmp_path) + ":/usr/bin:/bin", "HANDOFF_CMD": "true", "TERM": "dumb"})
    assert "Opening in existing" not in result.stdout
    assert "Broken pipe" not in result.stderr
    assert "real failure" in result.stderr and "status=3" in result.stdout


def test_note_failure_is_one_readable_line(tmp_path, monkeypatch, capsys):
    tw = fake_bin(tmp_path, "tw", 'echo "note denied" >&2; exit 1\n')
    monkeypatch.setenv("HANDOFF_TW_WRAPPER", str(tw))
    monkeypatch.setattr(nav, "task_export", lambda *args: [dict(task(), status="pending")])
    assert nav.verify(task("done-when: manual check")) == 1
    output = capsys.readouterr()
    assert output.err.count("handoff:") == 1
    assert "note denied" in output.err and "CalledProcessError" not in output.err

def test_verify_mode_reads_the_row_and_runs_its_probe(tmp_path, monkeypatch):
    row = task("done-when: pr-merged loft-sh/architecture#26")
    seen = []
    monkeypatch.setattr(nav, "run", lambda args, **kw: subprocess.CompletedProcess(args, 0, json.dumps([row])))
    monkeypatch.setattr(nav, "verify", lambda r: seen.append(r) or 0)
    assert nav.main(["verify", UUID]) == 0
    assert seen == [row]


def test_show_slack_draft_positions_live_buffer_and_restores_terminal(tmp_path, monkeypatch):
    import shutil
    import time

    nvim = shutil.which('nvim')
    if not nvim:
        pytest.skip('nvim is unavailable')
    socket = tmp_path / 'handoff-18.sock'
    brief = tmp_path / 'brief.md'
    brief.write_text('intro\n<!-- begin generated draft -->\n```\nold\n```\n'
                     '<!-- end generated draft -->\nmore\n'
                     '<!-- begin generated draft -->\n```\nlatest\n```\n'
                     '<!-- end generated draft -->\n')
    process = subprocess.Popen([nvim, '--headless', '-u', 'NONE', '--listen', str(socket), str(brief)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    real_run = nav.run
    calls = []
    def run(args, **kwargs):
        if args[0] == 'xdotool':
            calls.append(args)
            return subprocess.CompletedProcess(args, 0)
        return real_run(args, **kwargs)
    monkeypatch.setenv('HANDOFF_NVIM_COMMAND', nvim)
    monkeypatch.setattr(nav, 'run', run)
    try:
        for _ in range(100):
            if socket.exists():
                break
            time.sleep(0.05)
        nav.show_slack_draft('%18', '111', tmp_path)
        result = subprocess.run([nvim, '--server', str(socket), '--remote-expr', 'line(".")'],
                                capture_output=True, text=True, check=True, timeout=5)
        assert result.stdout.strip() == '10'
        assert calls == [['xdotool', 'windowactivate', '111']]
    finally:
        subprocess.run([nvim, '--server', str(socket), '--remote-expr', 'execute("qa!")'],
                       capture_output=True, timeout=5)
        process.wait(timeout=5)


@pytest.fixture
def fake_pages(tmp_path, monkeypatch):
    """Tab bridge, xdg-open and layout on disk, each logging its argv as one line."""
    log = tmp_path / "pages.log"
    record = f'printf "%s " "$(basename "$0")" "$@" >> {log}; printf "\\n" >> {log}\n'
    def setup(bridge_status, hang=False):
        monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
        tab = fake_bin(tmp_path, "tab", record + ("exec sleep 30\n" if hang else f"exit {bridge_status}\n"))
        fake_bin(tmp_path, "xdg-open", record)
        layout = fake_bin(tmp_path, "layout", record)
        monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ['PATH']}")
        monkeypatch.setenv("HANDOFF_TAB_COMMAND", str(tab))
        monkeypatch.setenv("HANDOFF_LAYOUT_COMMAND", str(layout))
        monkeypatch.delenv("HANDOFF_BROWSER_COMMAND", raising=False)
        monkeypatch.setattr(nav, "window_id", lambda _: "222")
        monkeypatch.setattr(nav, "terminal_monitor", lambda _: "HDMI-0")
        monkeypatch.setattr(nav.time, "sleep", lambda _: None)
        return lambda: [line.split() for line in log.read_text().splitlines()]
    return setup


DCA = ["https://github.com/loft-sh/.github/pull/11", "https://github.com/loft-sh"]


def test_stale_tab_bridge_falls_back_to_xdg_open_tabs(fake_pages, capsys):
    """Piotr, 11 Nov on dca07548: s opened nothing once the bridge extension went stale."""
    calls = fake_pages(1)
    nav.navigate_many(DCA, "111")
    assert [c for c in calls() if c[0] == "xdg-open"] == [["xdg-open", url] for url in DCA]
    assert not any("--new-window" in c for c in calls())
    assert calls()[-1] == ["layout", "2"]
    err = capsys.readouterr().err
    for url in DCA:
        assert f"handoff: tab bridge failed, fallback xdg-open {url}" in err


def test_live_tab_bridge_opens_background_tabs_without_xdg_open(fake_pages, capsys):
    calls = fake_pages(0)
    nav.navigate_many(DCA, "111")
    # No --focus: the broker neither raises nor tiles Chrome (11 Nov).
    assert calls() == [["tab", url] for url in DCA] + [["layout", "2"]]
    assert capsys.readouterr().err.count("handoff: opened via tab bridge") == 2


def test_hanging_tab_bridge_falls_back_within_about_a_second(fake_pages, nav_log):
    """Piotr, 11 Nov on the 8d1dd0a6 fallback: the right mail "but with huge delay"."""
    import time
    calls = fake_pages(0, hang=True)
    started = time.monotonic()
    nav.navigate_many([DCA[0]], "111")
    elapsed = time.monotonic() - started
    assert 0.9 <= elapsed < 2.0
    assert calls() == [["tab", DCA[0]], ["xdg-open", DCA[0]], ["layout", "2"]]
    assert f"handoff: tab bridge failed, fallback xdg-open {DCA[0]}" in nav_log.read_text()


@pytest.mark.parametrize("status", [0, 1])
def test_no_page_path_asks_for_a_new_window_or_focus(fake_pages, status):
    calls = fake_pages(status)
    nav.navigate_many(DCA, "111")
    nav.navigate_many([ENTERPRISE, DCA[0]], "111", slack_tabs=True)
    flat = [arg for call in calls() for arg in call]
    assert flat and "--new-window" not in flat and "--focus" not in flat
    for script in (PATH, PATH.with_name("__handoff_tab.py")):
        assert "--new-window" not in script.read_text()


def test_cmd_page_opens_beside_links_and_only_then_skips_the_command(monkeypatch):
    shown = []
    monkeypatch.setattr(nav, "open_command_window", lambda uuid, command: shown.append(command))
    row = task(f"link: {DCA[0]}", "cmd: xdg-open https://github.com/loft-sh/vcluster")
    assert nav.annotation_urls(row) == [DCA[0], "https://github.com/loft-sh/vcluster"]
    nav.act_on_kind(row)
    assert shown == []
    bad = task(f"link: {DCA[0]}", "cmd: xdg-open https://github.com:8443/loft-sh")
    assert nav.annotation_urls(bad) == [DCA[0]]
    nav.act_on_kind(bad)
    assert shown == ["xdg-open https://github.com:8443/loft-sh"]

@pytest.mark.parametrize("bridge_status", [0, 1])
@pytest.mark.parametrize("urls", [["https://github.com/a"], [ENTERPRISE],
                                  ["https://linear.app/a", "https://linear.app/b"]])
def test_link_paths_tile_real_layout_with_stubbed_windows(tmp_path, monkeypatch, bridge_status, urls):
    """Both browser paths send the real layout exact IDs on the terminal monitor."""
    import shutil
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    for name in ("__layouts.sh", "__lib_screen.sh"):
        shutil.copy(PATH.with_name(name), scripts / name)
    for name in ("__alacritty_font_scale.sh", "__panel_adapt.sh"):
        fake_bin(scripts, name, "exit 0\n")
    tiles = tmp_path / "tiles"
    fake_bin(tmp_path, "tab", f"exit {bridge_status}\n")
    fake_bin(tmp_path, "xdg-open", "exit 0\n")
    fake_bin(tmp_path, "gsettings", "exit 0\n")
    fake_bin(tmp_path, "gdbus", f'printf "%s\\n" "$*" >> "{tiles}"\n')
    fake_bin(tmp_path, "xdotool", 'case "$1" in search) echo 111;; getactivewindow) echo 111;; esac\n')
    fake_bin(tmp_path, "wmctrl", '''case "$*" in
-lG) echo '0x0000006f 0 2100 100 800 600 host terminal';;
-d) echo '0 * DG: 4000x1200 VP: 0,0 WA: 0,40 4000x1160';;
*) echo '0x000000de 0 google-chrome.Google-chrome host Chrome';;
esac
''')
    fake_bin(tmp_path, "xrandr", '''echo 'LEFT connected primary 2000x1200+0+0'
echo 'RIGHT connected 2000x1200+2000+0'
''')
    monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("HANDOFF_TAB_COMMAND", str(tmp_path / "tab"))
    monkeypatch.setenv("HANDOFF_LAYOUT_COMMAND", str(scripts / "__layouts.sh"))
    monkeypatch.delenv("HANDOFF_BROWSER_COMMAND", raising=False)
    nav.navigate_many(urls, "111", slack_tabs=True)
    calls = tiles.read_text().splitlines()
    assert len(calls) == 2
    if urls == [ENTERPRISE]:
        assert calls[0].endswith("TileXid 111 2000 40 1000 1160")
    else:
        assert calls[0].endswith("TileXid 222 2000 40 1000 1160")
        assert calls[1].endswith("TileXid 111 3000 40 1000 1160")


def test_missing_terminal_monitor_never_tiles(monkeypatch):
    calls = []
    monkeypatch.setattr(nav, "open_page", lambda url: None)
    monkeypatch.setattr(nav, "terminal_monitor", lambda _: "")
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args))
    nav.navigate_many(["https://github.com/a"], "111")
    assert calls == []


@pytest.mark.parametrize(("outputs", "expected"), [
    ("HDMI-0 connected primary 1920x1080+0+0", "HDMI-0"),
    ("HDMI-0 connected primary 100x100+0+0", "HDMI-0"),
    ("HDMI-0 connected primary 100x100-100-100", "HDMI-0"),
    ("HDMI-0 disconnected", "missing"),
])
def test_terminal_monitor_logs_geometry_and_result(monkeypatch, nav_log, outputs, expected):
    def run(args, **kwargs):
        output = "0x0000006f  0 100 200 800 600 host terminal\n" if args[0] == "wmctrl" else outputs
        return subprocess.CompletedProcess(args, 0, stdout=output)

    monkeypatch.setattr(nav, "run", run)
    assert nav.terminal_monitor("111") == (expected if expected != "missing" else "")
    assert f"terminal xid=111 geometry=100,200,800,600 monitor={expected}" in nav_log.read_text()


def test_terminal_monitor_logs_missing_terminal(nav_log):
    assert nav.terminal_monitor("") == ""
    assert "terminal xid=missing geometry=missing monitor=missing" in nav_log.read_text()


def test_tab_bridge_error_is_logged(tmp_path, monkeypatch, nav_log):
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    tab = fake_bin(tmp_path, "failed-tab", 'echo "bridge rejected request" >&2\nexit 1\n')
    fake_bin(tmp_path, "xdg-open", "exit 0\n")
    monkeypatch.setenv("PATH", f"{tmp_path}{os.pathsep}{os.environ['PATH']}")
    monkeypatch.setenv("HANDOFF_TAB_COMMAND", str(tab))
    nav.open_page("https://github.com/a")
    assert "handoff: tab bridge error: bridge rejected request" in nav_log.read_text()


@pytest.mark.parametrize("key", ["PYTEST_CURRENT_TEST", "BATS_TEST_FILENAME", "TASKDATA", "TASKRC"])
def test_test_context_never_falls_back_to_browser(monkeypatch, nav_log, key):
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    monkeypatch.delenv("BATS_TEST_FILENAME", raising=False)
    monkeypatch.delenv("TASKDATA", raising=False)
    monkeypatch.delenv("TASKRC", raising=False)
    monkeypatch.setenv(key, "/tmp/isolated")
    monkeypatch.setattr(nav, "run", lambda *args, **kwargs: pytest.fail("launched"))
    nav.open_page("https://github.com/a")
    assert "browser suppressed" in nav_log.read_text()
