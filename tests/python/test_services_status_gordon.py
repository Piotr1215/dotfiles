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
    assert '"outage"' in state and '"operational"' in state


def test_transition_appends_once_and_repeat_appends_nothing(board):
    board.notify_transitions({"GCP": "operational"})
    board.notify_transitions({"GCP": "degraded"})
    board.notify_transitions({"GCP": "degraded"})
    out = lines(board)
    assert len(out) == 1
    date, app, summary, body = out[0].split("\t")
    assert app == "argos"
    assert summary == "GCP outage: Multiple services are experiencing issues in the europe-west2 region."
    assert "London (europe-west2)" in body
    assert "AlloyDB for PostgreSQL" in body
    assert "Old resolved thing" not in body and "Iowa" not in body
    assert "https://status.cloud.google.com/" in body
    assert "degraded" in body


def test_severity_change_inside_outage_appends_nothing(board):
    board.notify_transitions({"GCP": "operational"})
    board.notify_transitions({"GCP": "degraded"})
    board.notify_transitions({"GCP": "major"})
    assert len(lines(board)) == 1


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
