import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / ('__' + name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

pace = load('cron_pace')
audit = load('schedule_audit')

class PacingTest(unittest.TestCase):
    def test_plain_reminders_keep_time_but_exec_checks_are_paced(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            store = Path(d) / 'reminders.jsonl'
            store.write_text(json.dumps({'id': 'deadbeef', 'action': 'show'}) + '\n')
            with mock.patch.dict(os.environ, {'REMINDER_STORE': str(store)}):
                calls = []
                def launch(args, env):
                    calls.append(args)
                    return subprocess.CompletedProcess(args, 0)
                pace.pace(['/wrapper', 'remind-deadbeef', '--', '/fire'], Path(d) / 'plain',
                    sleep=lambda _: self.fail('plain reminder delayed'), launch=launch)
                self.assertEqual(calls, [['/wrapper', 'remind-deadbeef', '--', '/fire']])
                store.write_text(json.dumps({'id': 'deadbeef', 'action': 'exec'}) + '\n')
                calls.clear()
                pace.pace(['/wrapper', 'remind-deadbeef', '--', '/fire'], Path(d) / 'exec',
                    now=lambda: 1000, sleep=lambda _: None, launch=launch)
                self.assertIn('--slice=background-automation.slice', calls[0])

    def test_claim_spacing_and_argv_environment(self):
        with tempfile.TemporaryDirectory() as d:
            clock = [1000.0]
            calls = []
            def sleep(seconds): clock[0] += seconds
            def launch(args, env):
                calls.append((clock[0], args, env))
                return subprocess.CompletedProcess(args, 7)
            for job in ('a', 'b'):
                self.assertEqual(pace.pace(['/wrapper', job, '--', 'echo', 'a b'], d,
                                           now=lambda: clock[0], sleep=sleep, launch=launch), 7)
            self.assertGreaterEqual(calls[1][0] - calls[0][0], 5)
            self.assertEqual(calls[0][1][-5:], ['/wrapper', 'a', '--', 'echo', 'a b'])
            self.assertEqual(calls[0][2]['CRON_PACED_ACTIVE'], '1')
            self.assertEqual(calls[0][1][:11], ['systemd-run', '--user', '--scope', '--quiet',
                '--slice=background-automation.slice', '-p', 'CPUQuota=30%',
                '/usr/bin/nice', '-n', '10', '/wrapper'])

    def test_duplicate_skips_while_lock_held(self):
        import fcntl, hashlib
        with tempfile.TemporaryDirectory() as d:
            key = hashlib.sha256(b'a').hexdigest()
            with open(Path(d) / (key + '.lock'), 'w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertEqual(pace.pace(['/wrapper', 'a', '--', 'true'], d,
                    sleep=lambda _: self.fail('slept'), launch=lambda *a, **kw: self.fail('launched')), 0)

    def test_dispatcher_keeps_its_own_timing_inside_the_limited_scope(self):
        with tempfile.TemporaryDirectory() as d:
            sleeps = []
            calls = []
            def launch(args, env):
                calls.append(args)
                return subprocess.CompletedProcess(args, 0)
            self.assertEqual(pace.pace(['/wrapper', 'reminder-dispatch', '--', '/dispatch'], d,
                now=lambda: 1000, sleep=sleeps.append, launch=launch), 0)
            self.assertEqual(sleeps, [0])
            self.assertIn('--slice=background-automation.slice', calls[0])

    def test_real_wrapper_exit_and_state(self):
        wrapper = str(ROOT / 'scripts' / '__cron_run.sh')
        with tempfile.TemporaryDirectory() as d:
            old = os.environ.get('CRON_STATE_DIR')
            os.environ['CRON_STATE_DIR'] = d
            try:
                for code, expected, state in [(0, 0, 'no-hit'), (2, 0, 'hit'), (7, 7, 'error'), (143, 143, 'interrupted')]:
                    command = 'kill -TERM $$' if code == 143 else f'exit {code}'
                    def launch(args, env):
                        return subprocess.run(args[10:], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    result = pace.pace([wrapper, f'job{code}', '--', 'bash', '-c', command], Path(d) / 'locks',
                                       now=lambda: 1000, sleep=lambda _: None, launch=launch)
                    self.assertEqual(result, expected)
                    import json
                    self.assertEqual(json.loads((Path(d) / f'job{code}.json').read_text())['state'], state)
            finally:
                if old is None: os.environ.pop('CRON_STATE_DIR', None)
                else: os.environ['CRON_STATE_DIR'] = old

class ScheduleAuditTest(unittest.TestCase):
    def test_schedule_fixtures(self):
        for minute in ('*', '*/2', '0,4', '0-10/3', '1,58'):
            self.assertTrue(audit.audit([f'{minute} * * * * echo hi']))
        for minute in ('*/5', '0,5,10', '1', '0-59/10'):
            self.assertFalse(audit.audit([f'{minute} * * * * echo hi']))
        self.assertFalse(audit.audit(['# */1 * * * * ignored', 'CRON_PACED=1', '@reboot true']))
        self.assertTrue(audit.audit(['@minutely true']))

if __name__ == '__main__': unittest.main()
