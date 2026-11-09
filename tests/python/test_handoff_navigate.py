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
    monkeypatch.setattr(nav, "open_block", lambda _: [])
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal: None)
    monkeypatch.setattr(nav, "switch_agent_session", lambda session: False)
    assert nav.main(["start", UUID]) == 0
    assert not any("stop" in args for args in calls)
    assert calls[-1][1:3] == ["pin", UUID]


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
    calls = []
    monkeypatch.setenv("HANDOFF_BROWSER_COMMAND", "/browser")
    monkeypatch.setenv("SLACK_TEAM_ID", "T0123")
    monkeypatch.setattr(nav, "window_id", lambda _: "222")
    monkeypatch.setattr(nav.time, "sleep", lambda _: None)
    monkeypatch.setattr(nav, "run", lambda args, **kw: calls.append(args))
    monkeypatch.setattr(nav.subprocess, "Popen", lambda args, **kw: calls.append(args))
    nav.navigate_many([ENTERPRISE, "https://github.com/a"], "111")
    assert calls[0] == ["xdg-open", nav.slack_deep_link(ENTERPRISE)]
    assert ["/browser", "https://github.com/a"] in calls
    assert calls[-1][-1] == "10"


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
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal: calls.append((urls, terminal)))
    monkeypatch.setattr(nav, "switch_agent_session", lambda session: False)
    assert nav.main(["start", UUID]) == 0
    assert ([ENTERPRISE, "https://linear.app/loft/issue/DEVOPS-1798"], "111") in calls
    assert calls[-1][1:3] == ["pin", UUID]


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
  display-message) echo '$4' ;;
  new-window) echo '%99' ;;
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


def test_command_kind_opens_a_named_window_with_the_command_unsubmitted(fake_tmux):
    hostile = "git push; echo $(touch /tmp/pwned) `id` 'q' \"d\" \\ $HOME"
    row = dict(task(f"cmd: {hostile}"), kind="command")
    assert nav.act_on_kind(row) == "command"
    calls = fake_tmux()
    assert calls[0] == ["display-message", "-p", "-t", "%18", "#{session_id}"]
    new = calls[1]
    assert new[:3] == ["new-window", "-P", "-F"] and new[new.index("-t") + 1] == "$4:"
    assert new[new.index("-n") + 1] == UUID[:8]
    # The command is one argv element in the window's environment, verbatim.
    assert new[new.index("-e") + 1] == "HANDOFF_CMD=" + hostile
    assert new[-3:] == ["--", "zsh", "-i"]
    # Only the fixed prefill line is typed; no task text reaches the keyboard.
    assert calls[2:] == [["send-keys", "-t", "%99", "-l", nav.PREFILL], ["send-keys", "-t", "%99", "Enter"]]
    assert all(hostile not in arg for call in calls[2:] for arg in call)
    assert "HANDOFF_CMD" in nav.PREFILL and "print -rz" in nav.PREFILL


@pytest.mark.parametrize(("notes", "error"), [
    ((), "no cmd: note"),
    (("cmd: git push\nrm -rf ~",), "one line"),
    (("cmd: git push\tx",), "one line"),
])
def test_command_kind_without_a_usable_command_reports_and_opens_nothing(fake_tmux, capsys, notes, error):
    assert nav.act_on_kind(dict(task(*notes), kind="command")) == "command"
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


@pytest.mark.parametrize("kind", ["pr", "ack", "other"])
def test_pr_ack_and_other_kinds_take_no_extra_action(fake_tmux, fake_clipboard, kind):
    row = dict(task(f"cmd: {PUSH}", "draft: hello", "done-when: pr-merged architecture#26"), kind=kind)
    assert nav.act_on_kind(row) == kind
    assert fake_tmux() == []
    assert not fake_clipboard.exists()


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
        if "prepare" in args or "pin" in args:
            order.append(args[1])
            return subprocess.CompletedProcess(args, 0, str(brief))
        return real_run(args, **kwargs)
    monkeypatch.setattr(nav, "run", run)
    monkeypatch.setattr(nav, "window_id", lambda _: "111")
    monkeypatch.setattr(nav, "navigate_many", lambda urls, terminal: order.append(("open", urls)))
    monkeypatch.setattr(nav, "switch_agent_session", lambda session: order.append(("agent", session)))
    assert nav.main(["start", row["uuid"]]) == 0
    return order


def test_start_on_a_command_row_opens_the_terminal_and_stays_in_this_session(monkeypatch, tmp_path, fake_tmux):
    row = dict(task(f"cmd: {PUSH}", "agent: some-worker"), kind="command")
    order = start_row(monkeypatch, tmp_path, row)
    calls = fake_tmux()
    assert [c[0] for c in calls] == ["display-message", "new-window", "send-keys", "send-keys"]
    assert "HANDOFF_CMD=" + PUSH in calls[1]
    assert order == ["prepare", ("open", []), "pin"]


def test_start_on_a_slack_row_copies_the_draft_then_opens_the_thread(monkeypatch, tmp_path, fake_clipboard):
    target = f"target: slack:C0CE21P1C3H/1793963101.837439 {ENTERPRISE}"
    row = dict(task(target, "draft: Hi Jan, merged."), tags=["piotr", "draft"], kind="slack")
    order = start_row(monkeypatch, tmp_path, row)
    assert fake_clipboard.read_text() == "Hi Jan, merged."
    assert order == ["prepare", ("open", [ENTERPRISE]), ("agent", ""), "pin"]


def test_start_on_a_pr_row_opens_the_pr_as_before(monkeypatch, tmp_path, fake_tmux, fake_clipboard):
    row = dict(task("done-when: pr-merged architecture#26"), kind="pr")
    order = start_row(monkeypatch, tmp_path, row)
    assert order[1] == ("open", ["https://github.com/loft-sh/architecture/pull/26"])
    assert fake_tmux() == [] and not fake_clipboard.exists()
