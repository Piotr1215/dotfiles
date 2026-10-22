"""Tests for the Gordon notifications in the argos service status board."""
import importlib.util
import pathlib

import pytest

BOARD = pathlib.Path(__file__).resolve().parents[2] / ".config" / "argos" / "services-status.5m.py"

GCP_FEED = [
    {
        "external_desc": "Multiple services are experiencing issues in the europe-west2 region.",
        "begin": "2026-10-20T06:08:00+00:00",
        "most_recent_update": {"affected_locations": [{"title": "London (europe-west2)", "id": "europe-west2"}]},
        "affected_products": [{"title": "AlloyDB for PostgreSQL"}, {"title": "Apigee"}],
    },
    {
        "external_desc": "Old resolved thing",
        "begin": "2026-02-27T12:37:00+00:00",
        "end": "2026-02-27T14:00:00+00:00",
        "most_recent_update": {"affected_locations": [{"title": "Iowa (us-central1)"}]},
        "affected_products": [{"title": "Cloud Run"}],
    },
]


@pytest.fixture
def board(tmp_path, monkeypatch):
    monkeypatch.setenv("ARGOS_NOTIFY_LOG", str(tmp_path / "notifications.log"))
    monkeypatch.setenv("ARGOS_STATE_DIR", str(tmp_path / "state"))
    spec = importlib.util.spec_from_file_location("services_status_board", BOARD)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.FEED_ERRORS.clear()
    # Never hit the network or the real describe path.
    monkeypatch.setattr(mod, "fetch_status", lambda url, timeout=5: GCP_FEED if "google" in url else None)
    mod.log = tmp_path / "notifications.log"
    return mod


def lines(board):
    return board.log.read_text().splitlines() if board.log.exists() else []


def test_first_run_records_state_and_appends_nothing(board):
    board.notify_transitions({"GCP": "degraded", "GitHub": "operational"})
    assert lines(board) == []
    state = (board.log.parent / "state" / board.GORDON_STATE_NAME).read_text()
    assert '"degraded"' in state and '"operational"' in state


def test_transition_appends_once_and_repeat_appends_nothing(board):
    board.notify_transitions({"GCP": "operational"})
    board.notify_transitions({"GCP": "degraded"})
    board.notify_transitions({"GCP": "degraded"})
    out = lines(board)
    assert len(out) == 1
    date, app, summary, body = out[0].split("\t")
    assert app == "argos"
    assert summary == "GCP degraded: Multiple services are experiencing issues in the europe-west2 region."
    assert "London (europe-west2)" in body
    assert "AlloyDB for PostgreSQL" in body
    assert "Old resolved thing" not in body and "Iowa" not in body
    assert "https://status.cloud.google.com/" in body
    assert "degraded" in body


def test_severity_change_inside_outage_appends_one_line_each_way(board):
    board.notify_transitions({"GCP": "operational"})
    board.notify_transitions({"GCP": "degraded"})
    board.notify_transitions({"GCP": "major"})
    board.notify_transitions({"GCP": "major"})
    board.notify_transitions({"GCP": "degraded"})
    out = lines(board)
    assert [r.split("\t")[2].split(":")[0] for r in out] == ["GCP degraded", "GCP now outage", "GCP now degraded"]


def statuspage(board, monkeypatch, pages):
    """Serves pages[url suffix] for every statuspage fetch; a missing suffix
    is a failed fetch."""
    def fetch(url, timeout=5):
        for suffix, data in pages.items():
            if url.endswith(suffix):
                return data
        return None
    monkeypatch.setattr(board, "fetch_status", fetch)


def comps(**states):
    return {"components": [{"name": n.replace("_", " "), "status": s, "group": False} for n, s in states.items()]
            + [{"name": "GitHub", "status": "degraded_performance", "group": True}]}


def test_component_changes_while_degraded_append_an_update(board, monkeypatch):
    incidents = {"incidents": []}
    pages = {"incidents/unresolved.json": incidents, "components.json": comps(GitHub_Pull_Requests="degraded_performance")}
    statuspage(board, monkeypatch, pages)
    board.notify_transitions({"Spacelift": "operational"})
    board.notify_transitions({"Spacelift": "degraded"})
    board.notify_transitions({"Spacelift": "degraded"})
    pages["components.json"] = comps(GitHub_Pull_Requests="partial_outage", Worker_Pools="degraded_performance")
    incidents["incidents"] = [{"name": "Delayed runs"}]
    board.notify_transitions({"Spacelift": "degraded"})
    board.notify_transitions({"Spacelift": "degraded"})
    out = lines(board)
    assert len(out) == 2
    _, _, summary, body = out[0].split("\t")
    assert summary == "Spacelift degraded: status page reports an outage"
    assert "Components: GitHub Pull Requests (degraded)." in body
    _, _, summary, body = out[1].split("\t")
    assert summary == "Spacelift update: Delayed runs"
    assert "new incident: Delayed runs" in body
    assert "GitHub Pull Requests degraded -> partial outage" in body
    assert "+Worker Pools (degraded)" in body
    # A group component is not an affected component of its own.
    assert "(degraded), GitHub (" not in body


def test_a_failed_details_fetch_is_not_a_change(board, monkeypatch):
    pages = {"incidents/unresolved.json": {"incidents": []}, "components.json": comps(Runs="degraded_performance")}
    statuspage(board, monkeypatch, pages)
    board.notify_transitions({"Spacelift": "operational"})
    board.notify_transitions({"Spacelift": "degraded"})
    del pages["components.json"]
    board.notify_transitions({"Spacelift": "degraded"})
    assert len(lines(board)) == 1


def test_cloudflare_components_are_never_read(board, monkeypatch):
    seen = []
    def fetch(url, timeout=5):
        seen.append(url)
        return {"incidents": [{"name": "Network issues", "impact": "minor"}]} if url.endswith("unresolved.json") else None
    monkeypatch.setattr(board, "fetch_status", fetch)
    board.notify_transitions({"Cloudflare": "operational"})
    board.notify_transitions({"Cloudflare": "degraded"})
    assert not any(u.endswith("components.json") for u in seen)
    assert lines(board)[0].split("\t")[2] == "Cloudflare degraded: Network issues"


def test_an_outage_recorded_by_the_two_state_notifier_is_adopted_silently(board):
    state = board.log.parent / "state"
    state.mkdir()
    (state / board.GORDON_STATE_NAME).write_text('{"GCP": {"state": "outage", "title": "old"}}')
    board.notify_transitions({"GCP": "degraded"})
    board.notify_transitions({"GCP": "degraded"})
    assert lines(board) == []
    board.notify_transitions({"GCP": "operational"})
    assert lines(board)[0].split("\t")[2] == "GCP recovered"


def test_recovery_appends_once(board):
    board.notify_transitions({"GCP": "operational"})
    board.notify_transitions({"GCP": "degraded"})
    board.notify_transitions({"GCP": "operational"})
    board.notify_transitions({"GCP": "operational"})
    out = lines(board)
    assert len(out) == 2
    _, app, summary, body = out[1].split("\t")
    assert (app, summary) == ("argos", "GCP recovered")
    assert "operational" in body and "https://status.cloud.google.com/" in body


def test_feed_error_appends_nothing_and_keeps_state(board, monkeypatch):
    board.notify_transitions({"GCP": "degraded"})  # first run: outage recorded
    # Feed breaks: GCP getter reports operational but flags the error.
    monkeypatch.setattr(board, "fetch_status", lambda url, timeout=5: None)
    statuses = {"GCP": board.get_gcp_status(), "GitHub": board.get_github_status()}
    assert statuses == {"GCP": "operational", "GitHub": "unknown"}
    assert "GCP" in board.FEED_ERRORS
    board.notify_transitions(statuses)
    assert lines(board) == []
    # Feed returns still-active outage: no duplicate line either.
    board.FEED_ERRORS.clear()
    board.notify_transitions({"GCP": "degraded"})
    assert lines(board) == []


def test_failed_append_is_retried_next_run(board, monkeypatch):
    board.notify_transitions({"GCP": "operational"})
    monkeypatch.setenv("ARGOS_NOTIFY_LOG", str(board.log.parent / "missing-dir" / "n.log"))
    board.notify_transitions({"GCP": "degraded"})
    monkeypatch.setenv("ARGOS_NOTIFY_LOG", str(board.log))
    board.notify_transitions({"GCP": "degraded"})
    assert len(lines(board)) == 1


def test_gcp_parsing_active_versus_ended(board, monkeypatch):
    assert len(board.gcp_active_incidents(GCP_FEED)) == 1
    assert board.gcp_active_incidents(GCP_FEED[1:]) == []
    assert board.gcp_active_incidents(None) == []
    title, impacted = board.describe_gcp(GCP_FEED)
    assert title.startswith("Multiple services")
    assert "london" in impacted.lower() and "europe-west2" in impacted
    assert board.describe_gcp(GCP_FEED[1:]) == (None, "")
    monkeypatch.setattr(board, "fetch_status", lambda url, timeout=5: GCP_FEED)
    assert board.get_gcp_status() == "degraded"
    monkeypatch.setattr(board, "fetch_status", lambda url, timeout=5: GCP_FEED[1:])
    assert board.get_gcp_status() == "operational"
    assert "GCP" not in board.FEED_ERRORS


def test_line_is_single_record_with_four_fields(board):
    assert board.append_gordon_line("a\tb\nc", "x\ty\nz")
    (row,) = lines(board)
    assert len(row.split("\t")) == 4
