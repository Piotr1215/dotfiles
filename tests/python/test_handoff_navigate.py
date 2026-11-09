import importlib.util
import json
from pathlib import Path
import subprocess

import pytest

PATH = Path(__file__).resolve().parents[2] / "scripts" / "__handoff_navigate.py"
spec = importlib.util.spec_from_file_location("handoff_navigate", PATH)
nav = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nav)
UUID = "aa476008-cc54-48fe-8530-ea217db834e7"


def task(*annotations, tags=None):
    return {"uuid": UUID, "tags": ["piotr"] if tags is None else tags,
            "annotations": [{"description": text} for text in annotations]}


@pytest.mark.parametrize("url", [
    "http://github.com/a", "https://github.com.evil.test/a", "https://evil.test/a",
    "https://user@github.com/a", "https://github.com:443/a", "file:///tmp/a",
    "https://github.com\\@evil.test/a", "https://github.com/a\n",
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
    ("done-when: pr-reviewed loft-sh/architecture#26 since 2026-11-06", "https://github.com/loft-sh/architecture/pull/26"),
    ("done-when: pr-merged architecture#26", "https://github.com/loft-sh/architecture/pull/26"),
    ("done-when: linear DEVOPS-1825 released", "https://linear.app/loft/issue/DEVOPS-1825"),
])
def test_destination_forms(annotation, url):
    assert nav.destination(task(annotation)) == url


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


def test_agent_session_switches_only_to_existing_exact_tmux_session(monkeypatch):
    calls = []
    def fake_run(args, **kwargs):
        calls.append(args)
        return subprocess.CompletedProcess(args, 0 if args[1] == "has-session" else 0)
    monkeypatch.setattr(nav.subprocess, "run", fake_run)
    monkeypatch.setattr(nav, "run", fake_run)
    assert nav.switch_agent_session("slack-reply-anvesh")
    assert calls == [
        ["tmux", "has-session", "-t", "=slack-reply-anvesh"],
        ["tmux", "switch-client", "-t", "=slack-reply-anvesh"],
    ]


def test_agent_session_missing_session_is_not_switched(monkeypatch):
    calls = []
    monkeypatch.setattr(nav.subprocess, "run", lambda args, **kwargs:
                        calls.append(args) or subprocess.CompletedProcess(args, 1))
    monkeypatch.setattr(nav, "run", lambda *args, **kwargs: pytest.fail("switched missing session"))
    assert not nav.switch_agent_session("closed-agent")
    assert calls == [["tmux", "has-session", "-t", "=closed-agent"]]


@pytest.mark.parametrize(("urls", "layout"), [
    (["https://loft-labs-inc.slack.com/archives/C0123"], "8"),
    (["https://github.com/a"], "2"),
    (["https://loft-labs-inc.slack.com/archives/C0123", "https://github.com/a"], "10"),
    (["https://github.com/a", "https://linear.app/b"], "7"),
])
def test_layout_and_url_arguments(monkeypatch, urls, layout):
    calls = []
    monkeypatch.setenv("HANDOFF_BROWSER_COMMAND", "/browser")
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    monkeypatch.setattr(nav.time, "sleep", lambda _: None)
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append((args, kw)))
    monkeypatch.setattr(nav.subprocess, "Popen", lambda args, **kw: calls.append((args, kw)))
    nav.navigate_many(urls, "111")
    assert calls[-1][0][-1] == layout
    assert calls[-1][1]["env"]["LAYOUT_ALACRITTY_WINDOW"] == "111"
    for url in urls:
        expected = nav.slack_deep_link(url) if "slack.com" in url else url
        assert any(expected in args for args, _ in calls)


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
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal: calls.append((urls, terminal)))
    monkeypatch.setattr(nav, "switch_agent_session", lambda session: calls.append(("agent", session)))
    assert nav.main(["start", UUID]) == 0
    assert (([edited] if edited else []) + ["https://app.notion.com/p/runbook", "https://app.notion.com/p/access"], "111") in calls
    assert ("agent", "slack-reply-anvesh") in calls
    assert any("stop" in call and "rc.hooks=off" in call for call in calls)
    assert calls[-1][1:3] == ["pin", UUID]
    assert nav.main(["stop", UUID]) == 0
    assert calls[-2][1:3] == ["close", UUID]
    assert calls[-1][-1] == "1"


def test_empty_open_block_and_fallback(tmp_path):
    brief = tmp_path / "brief"
    brief.write_text("<!-- begin open -->\n\n<!-- end open -->\n")
    assert nav.open_block(brief) == []


def test_empty_block_uses_done_when_and_navigation_failure_still_pins(monkeypatch, tmp_path):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    monkeypatch.setenv("TMUX_PANE", "%18")
    row = dict(task("done-when: pr-merged architecture#26"), start="20261106T000000Z")
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
    def fail(urls, terminal):
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
    ("https://loft-labs-inc.slack.com/archives/C08EQAJQD24", "slack://channel?team=T0123&id=C08EQAJQD24"),
    ("https://loft-labs-inc.slack.com/archives/C0123/p1793917323756099", "slack://channel?team=T0123&id=C0123&message=1793917323.756099&thread_ts=1793917323.756099"),
    ("https://loft-labs-inc.slack.com/archives/C0123/p1793917323756099?thread_ts=1793917323.756099", "slack://channel?team=T0123&id=C0123&message=1793917323.756099&thread_ts=1793917323.756099"),
])
def test_slack_desktop_links_never_open_browser(monkeypatch, url, expected):
    calls = []
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args))
    monkeypatch.setattr(nav.subprocess, "Popen", lambda *a, **kw: pytest.fail("opened Chrome"))
    nav.navigate_many([url], "111")
    assert calls[0] == ["xdg-open", expected]


def test_missing_slack_team_does_not_open_browser(monkeypatch, tmp_path):
    monkeypatch.delenv("SLACK_TEAM_ID", raising=False)
    monkeypatch.setenv("SLACK_OPEN_TEAMS_CONFIG", str(tmp_path / "missing"))
    with pytest.raises(ValueError, match="team ID missing"):
        nav.slack_deep_link("https://loft-labs-inc.slack.com/archives/C0123")
