import fcntl
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import subprocess


PATH = Path(__file__).resolve().parents[2] / "scripts/__reminder_dispatch.py"
SPEC = importlib.util.spec_from_file_location("reminder_dispatch", PATH)
dispatch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dispatch)


def test_slots_are_stable_spread_and_collision_free():
    ids = [f"{i:08x}" for i in range(8)]
    first = dispatch.slots(ids)
    assert first == dispatch.slots(list(reversed(ids)))
    offsets = [offset for _, offset in first]
    assert offsets[-1] < 300
    assert all(b - a >= 10 for a, b in zip(offsets, offsets[1:]))


def test_durable_rate_limit_serial_spacing_and_latest_record(tmp_path):
    store = tmp_path / "records"
    ids = [f"{i:08x}" for i in range(8)]
    records = [{"id": key, "status": "active", "action": "exec", "repeat": "* * * * *"} for key in ids]
    records += [{"id": "ffffffff", "status": "active", "action": "exec", "repeat": "every 1m"},
                {"id": "ffffffff", "status": "done", "action": "exec", "repeat": "every 1m"}]
    store.write_text("".join(json.dumps(record) + "\n" for record in records))
    now = [600.0]
    starts = []

    def run(args, check, env):
        starts.append((args[-1], now[0]))
        assert args[:-1] == ["runner", "remind-" + args[-1], "--", "reminder", "fire"]
        assert env["REMINDER_STORE"] == str(store)
        now[0] += 2

    def sleep(seconds):
        now[0] += seconds

    def invoke():
        dispatch.dispatch(store, tmp_path / "state", "runner", "reminder",
                          clock=lambda: now[0], sleep=sleep, run=run)

    invoke()
    assert len(starts) == 8
    assert all(b[1] - a[1] >= 10 for a, b in zip(starts, starts[1:]))
    invoke()
    assert len(starts) == 8
    now[0] = 900
    invoke()
    assert len(starts) == 16
    previous = dict(starts[:8])
    assert all(when - previous[key] >= 300 for key, when in starts[8:])


def test_nonblocking_lock_prevents_overlapping_dispatch(tmp_path):
    store = tmp_path / "records"
    store.write_text('{"id":"deadbeef","status":"active","action":"exec","repeat":"every 1m"}\n')
    state = tmp_path / "state"
    state.mkdir()
    with (state / "dispatch.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        calls = []
        dispatch.dispatch(store, state, "runner", "reminder", run=lambda *a, **k: calls.append(a))
        assert calls == []


def test_other_repeat_kinds_do_not_enter_dispatch():
    def check(repeat, action="exec"):
        return dispatch.eligible({"status": "active", "action": action, "repeat": repeat})
    assert check("every 4m")
    assert check("every 01m")
    assert not check("every 5m")
    assert not check("0 9 * * *")
    assert not check("* * * * *", "show")


class DispatchTests(unittest.TestCase):
    def test_slots(self):
        test_slots_are_stable_spread_and_collision_free()

    def test_rate_and_serial_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            test_durable_rate_limit_serial_spacing_and_latest_record(Path(temp))

    def test_lock(self):
        with tempfile.TemporaryDirectory() as temp:
            test_nonblocking_lock_prevents_overlapping_dispatch(Path(temp))

    def test_scope(self):
        test_other_repeat_kinds_do_not_enter_dispatch()

    def test_two_real_invocations_share_attempt_stamp(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            store = root / "records"
            store.write_text('{"id":"deadbeef","status":"active","action":"exec","repeat":"every 1m"}\n')
            runner = root / "runner"
            log = root / "calls"
            runner.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >>"{log}"\n')
            runner.chmod(0o755)
            args = [str(PATH), "--store", str(store), "--state-dir", str(root / "state"),
                    "--runner", str(runner), "--reminder", "reminder"]
            subprocess.run(args, check=True)
            subprocess.run(args, check=True)
            self.assertEqual(log.read_text().splitlines(), ["remind-deadbeef -- reminder fire deadbeef"])


if __name__ == "__main__":
    unittest.main()
