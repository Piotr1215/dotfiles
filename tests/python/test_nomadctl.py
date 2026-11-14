import contextlib
import io
import os
from urllib.error import URLError
import subprocess
import unittest
from unittest.mock import patch

import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('nomadctl', Path(__file__).resolve().parents[2] / 'scripts/__nomadctl.py')
nomadctl = importlib.util.module_from_spec(spec)
sys.modules['nomadctl'] = nomadctl
spec.loader.exec_module(nomadctl)


class ControllerTest(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.failing_commands = set()
        self.uuid = nomadctl.EXPECTED_UUID
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        self.browser_calls = []
        self.remote = None
        self.http_calls = []
        self.remote_unload_error = False
        self.rescan_error = False
        self.container_output = 'child1\nchild2\n'

    def request_json(self, url, data=None):
        self.http_calls.append((url, data))
        if '/api/system/settings?' in url:
            return {'value': 'gpt-oss:20b'}
        if url.endswith('/api/ps'):
            return {'models': [{'name': 'gpt-oss:20b'}, {'name': 'gemma4:12b'}]}
        if url.endswith('/api/zim/rescan-library') and self.rescan_error:
            raise URLError('unreachable')
        if self.remote_unload_error:
            raise URLError('unreachable')
        return {'done': True}

    def start_browser(self, args, **kwargs):
        self.browser_calls.append((args, kwargs, list(self.commands())))

    def run_command(self, args, **kwargs):
        self.calls.append((args, kwargs))
        if tuple(args) in self.failing_commands:
            return subprocess.CompletedProcess(args, 1, '', 'failure')
        output = ''
        if args[0] == 'findmnt':
            output = self.uuid + '\n'
        elif args[:3] == ['docker', 'ps', '-aq']:
            output = self.container_output
        return subprocess.CompletedProcess(args, 0, output, '')

    def invoke(self, verb):
        with patch('nomadctl.subprocess.run', side_effect=self.run_command), patch('nomadctl.subprocess.Popen', side_effect=self.start_browser), patch('nomadctl.remote_profile', return_value=self.remote, create=True), patch('nomadctl.request_json', side_effect=self.request_json, create=True), patch('shutil.which', return_value='/usr/bin/google-chrome-stable'), patch.dict(os.environ, {'DISPLAY': ':99'}), contextlib.redirect_stdout(self.stdout), contextlib.redirect_stderr(self.stderr):
            return nomadctl.main([verb])

    def test_remote_on_starts_tunnel_and_skips_unused_local_ollama(self):
        self.remote = {'url': 'http://10.114.0.1:11436', 'model': 'gpt-oss:20b'}
        self.container_output = 'local1 nomad_ollama\nchild1 nomad_qdrant\n'
        self.assertEqual(self.invoke('on'), 0)
        commands = self.commands()
        tunnel = ['systemctl', '--user', 'enable', '--now', 'nomad-remote-ollama.service']
        self.assertIn(tunnel, commands)
        self.assertIn(['docker', 'start', 'child1'], commands)
        self.assertNotIn(['docker', 'start', 'local1'], commands)
        self.assertLess(commands.index(tunnel), commands.index(['docker', 'start', 'child1']))

    def test_fallback_service_starts_after_managed_containers_and_stops_before_them(self):
        self.remote = {'url': 'http://10.114.0.1:11436', 'model': 'gpt-oss:20b', 'fallback_unit': 'nomad-ollama-fallback.service'}
        self.assertEqual(self.invoke('on'), 0)
        commands = self.commands()
        start = ['systemctl', '--user', 'enable', '--now', 'nomad-ollama-fallback.service']
        self.assertLess(commands.index(nomadctl.MANAGED_STOPPED), commands.index(start))
        self.assertLess(commands.index(start), commands.index(['systemctl', '--user', 'enable', '--now', nomadctl.UNIT]))
        self.calls.clear()
        self.assertEqual(self.invoke('off'), 0)
        commands = self.commands()
        stop = ['systemctl', '--user', 'disable', '--now', 'nomad-ollama-fallback.service']
        self.assertLess(commands.index(stop), commands.index(nomadctl.MANAGED_ALL))

    def test_fallback_start_failure_fails_nomad_on(self):
        self.remote = {'url': 'http://10.114.0.1:11436', 'model': 'gpt-oss:20b', 'fallback_unit': 'nomad-ollama-fallback.service'}
        self.failing_commands.add(('systemctl', '--user', 'enable', '--now', 'nomad-ollama-fallback.service'))
        self.assertEqual(self.invoke('on'), 1)
        self.assertNotIn(['systemctl', '--user', 'enable', '--now', nomadctl.UNIT], self.commands())

    def test_remote_stop_unloads_only_selected_model_and_stops_tunnel(self):
        self.remote = {'url': 'http://10.114.0.1:11436', 'model': 'gpt-oss:20b'}
        self.assertEqual(self.invoke('stop'), 0)
        self.assertIn(('http://10.114.0.1:11436/api/generate', {'model': 'gpt-oss:20b', 'prompt': '', 'keep_alive': 0, 'stream': False}), self.http_calls)
        self.assertFalse(any(data and data.get('model') == 'gemma4:12b' for _, data in self.http_calls))
        self.assertEqual(self.commands()[-1], ['systemctl', '--user', 'disable', '--now', 'nomad-remote-ollama.service'])

    def test_remote_unload_failure_still_stops_local_services_and_tunnel(self):
        self.remote = {'url': 'http://10.114.0.1:11436', 'model': 'gpt-oss:20b'}
        self.remote_unload_error = True
        self.assertNotEqual(self.invoke('stop'), 0)
        self.assertIn(nomadctl.COMPOSE + ['stop'], self.commands())
        self.assertIn(['systemctl', '--user', 'disable', '--now', 'nomad-remote-ollama.service'], self.commands())

    def test_on_opens_port_1215_after_services_are_ready(self):
        self.assertEqual(self.invoke('on'), 0)
        self.assertEqual(len(self.browser_calls), 1)
        args, options, prior_commands = self.browser_calls[0]
        self.assertEqual(args, ['/usr/bin/google-chrome-stable', '--new-tab', 'http://localhost:1215/home'])
        self.assertEqual(prior_commands[-1], ['systemctl', '--user', 'enable', '--now', nomadctl.UNIT])
        self.assertTrue(options['start_new_session'])

    def test_on_rescans_library_so_offline_downloads_appear(self):
        self.assertEqual(self.invoke('on'), 0)
        self.assertIn(('http://127.0.0.1:1215/api/zim/rescan-library', {}), self.http_calls)

    def test_on_rescan_failure_warns_but_starts(self):
        self.rescan_error = True
        self.assertEqual(self.invoke('on'), 0)
        self.assertIn('rescan', self.stderr.getvalue())

    def test_startup_failure_never_opens_browser(self):
        self.failing_commands.add(tuple(nomadctl.COMPOSE + ['up', '-d', '--pull', 'never', '--wait', '--wait-timeout', '180']))
        self.assertNotEqual(self.invoke('on'), 0)
        self.assertEqual(self.browser_calls, [])

    def commands(self):
        return [args for args, _ in self.calls]

    def test_wrong_drive_refuses_all_writes(self):
        self.uuid = 'wrong'
        self.assertNotEqual(self.invoke('on'), 0)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.commands()[0][0], 'findmnt')
        self.assertIn('UUID', self.stderr.getvalue())

    def test_on_orders_core_then_stopped_children_then_downloader(self):
        self.assertEqual(self.invoke('on'), 0)
        commands = self.commands()
        self.assertEqual(commands[1], nomadctl.COMPOSE + ['up', '-d', '--pull', 'never', '--wait', '--wait-timeout', '180'])
        self.assertEqual(commands[2], nomadctl.MANAGED_STOPPED)
        self.assertEqual(commands[3], ['docker', 'start', 'child1', 'child2'])
        self.assertEqual(commands[4], ['systemctl', '--user', 'enable', '--now', 'nomad-downloads.service'])
        self.assertFalse(any('pause' in str(c).lower() or 'rpc' in str(c).lower() for c in commands))
        env = self.calls[4][1]['env']
        self.assertEqual(env['XDG_RUNTIME_DIR'], os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        self.assertEqual(env['DBUS_SESSION_BUS_ADDRESS'], os.environ.get('DBUS_SESSION_BUS_ADDRESS', f'unix:path=/run/user/{os.getuid()}/bus'))

    def test_off_continues_after_failures_and_returns_nonzero(self):
        disable = ['systemctl', '--user', 'disable', '--now', 'nomad-downloads.service']
        self.failing_commands.add(tuple(disable))
        self.failing_commands.add(tuple(['docker', 'stop', 'child1', 'child2']))
        self.assertNotEqual(self.invoke('off'), 0)
        self.assertEqual(self.commands(), [disable, nomadctl.MANAGED_ALL, ['docker', 'stop', 'child1', 'child2'], nomadctl.COMPOSE + ['stop']])
        self.assertIn('failure', self.stderr.getvalue())
        self.assertFalse(any('pause' in str(c).lower() or 'rpc' in str(c).lower() for c in self.commands()))

    def test_stop_alias_stops_downloads_all_owned_apps_and_core(self):
        self.assertEqual(self.invoke('stop'), 0)
        self.assertEqual(self.commands(), [
            ['systemctl', '--user', 'disable', '--now', nomadctl.UNIT],
            nomadctl.MANAGED_ALL,
            ['docker', 'stop', 'child1', 'child2'],
            nomadctl.COMPOSE + ['stop'],
        ])
        self.assertEqual(self.browser_calls, [])

    def test_owned_filters_require_both_labels(self):
        for command in (nomadctl.MANAGED_ALL, nomadctl.MANAGED_STOPPED):
            self.assertIn('label=io.project-nomad.managed=true', command)
            self.assertIn('label=com.docker.compose.project=project-nomad-managed', command)
        self.assertIn('status=exited', nomadctl.MANAGED_STOPPED)

    def test_core_failure_stops_startup(self):
        self.failing_commands.add(tuple(nomadctl.COMPOSE + ['up', '-d', '--pull', 'never', '--wait', '--wait-timeout', '180']))
        self.assertNotEqual(self.invoke('on'), 0)
        self.assertEqual(len(self.calls), 2)

    def test_status_scopes_docker_and_reports_unit_states(self):
        self.assertEqual(self.invoke('status'), 0)
        commands = self.commands()
        self.assertEqual(commands[0], nomadctl.BASE_STATUS)
        self.assertEqual(commands[1], nomadctl.MANAGED_STATUS)
        self.assertEqual(commands[2:], [['systemctl', '--user', 'is-active', 'nomad-downloads.service'], ['systemctl', '--user', 'is-enabled', 'nomad-downloads.service']])

    def test_missing_command_returns_nonzero_without_traceback(self):
        with patch('nomadctl.subprocess.run', side_effect=FileNotFoundError('missing')), contextlib.redirect_stderr(self.stderr):
            self.assertNotEqual(nomadctl.main(['on']), 0)
        self.assertIn('missing', self.stderr.getvalue())


if __name__ == '__main__':
    unittest.main()
