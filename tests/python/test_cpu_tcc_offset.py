"""Exercise the service command against temporary sysfs fixtures."""

import fnmatch
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
UNIT = ROOT / '.config/systemd/system/cpu-tcc-offset.service'
RULE = ROOT / '.config/udev/rules.d/99-cpu-power-source.rules'


class CpuTccOffsetTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cpu-tcc-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.unit = UNIT.read_text()
        match = re.search(r"(?ms)^ExecStart=/bin/sh -c '([^']*)'", self.unit)
        self.assertIsNotNone(match, 'could not extract ExecStart')
        self.script = match.group(1).replace('$$', '$')
        self.env = {key: os.environ[key] for key in ('HOME', 'PATH', 'USER', 'LANG')}
        for key, value in re.findall(r'^Environment=([A-Z0-9_]+)=([^\s]+)$', self.unit, re.M):
            self.env[key] = value

        self.thermal = self.root / 'thermal/0000:00:04.0/tcc_offset_degree_celsius'
        self.thermal.parent.mkdir(parents=True)
        self.thermal.write_text('0\n')
        self.powercap = self.root / 'powercap'
        self.zones = [self.powercap / 'intel-rapl:0', self.powercap / 'intel-rapl-mmio:0']
        for zone in self.zones:
            zone.mkdir(parents=True)
            (zone / 'name').write_text('package-0\n')
            (zone / 'constraint_0_name').write_text('long_term\n')
            (zone / 'constraint_0_power_limit_uw').write_text('0\n')
        self.supplies = self.root / 'power_supply'
        self.supply('AC', 'Mains', '1')
        self.supply('BAT0', 'Battery')
        self.supply('ucsi-source-psy-USBC000:001', 'USB', '0')
        self.supply('ucsi-source-psy-USBC000:002', 'USB', '0')

    def supply(self, name, kind, online=None):
        path = self.supplies / name
        path.mkdir(parents=True, exist_ok=True)
        (path / 'type').write_text(kind + '\n')
        if online is not None:
            (path / 'online').write_text(online + '\n')
        return path

    def run_service(self):
        script = self.script
        for old, new in (
            ('/sys/bus/pci/drivers/proc_thermal_pci', self.root / 'thermal'),
            ('/sys/class/powercap', self.powercap),
            ('/sys/class/power_supply', self.supplies),
        ):
            self.assertIn(old, script)
            script = script.replace(old, str(new))
        self.assertNotIn('/sys/', script, 'fixture script still references real sysfs')
        return subprocess.run(['/bin/sh', '-c', script], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def assert_applied(self, result, source, watts):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'power source {source}; pl1 {watts} uW', result.stdout)
        self.assertEqual(self.thermal.read_text().strip(), '13')
        for zone in self.zones:
            self.assertEqual((zone / 'constraint_0_power_limit_uw').read_text().strip(), watts)

    def test_barrel_charger_uses_full_power(self):
        self.assert_applied(self.run_service(), 'barrel', '160000000')

    def test_battery_uses_firmware_limit(self):
        (self.supplies / 'AC/online').write_text('0\n')
        self.assert_applied(self.run_service(), 'battery', '44000000')

    def test_usb_online_overrides_ac_online(self):
        (self.supplies / 'ucsi-source-psy-USBC000:002/online').write_text('1\n')
        self.assert_applied(self.run_service(), 'usb', '44000000')

    def test_any_usb_supply_overrides_ac_online(self):
        self.supply('other-usb-supply', 'USB', '1')
        self.assert_applied(self.run_service(), 'usb', '44000000')

    def test_missing_ac_uses_firmware_limit(self):
        (self.supplies / 'AC/online').unlink()
        (self.supplies / 'AC/type').unlink()
        (self.supplies / 'AC').rmdir()
        self.assert_applied(self.run_service(), 'unknown', '44000000')

    def test_unknown_usb_state_uses_firmware_limit(self):
        (self.supplies / 'ucsi-source-psy-USBC000:001/online').unlink()
        self.assert_applied(self.run_service(), 'unknown', '44000000')

    def test_failed_type_read_uses_firmware_limit(self):
        fake_bin = self.root / 'bin'
        fake_bin.mkdir()
        cat = fake_bin / 'cat'
        failing_type = self.supplies / 'ucsi-source-psy-USBC000:001/type'
        cat.write_text('#!/bin/sh\n'
                       f'[ "$1" = {shlex.quote(str(failing_type))} ] && exit 1\n'
                       'exec /usr/bin/cat "$@"\n')
        cat.chmod(0o755)
        self.env['PATH'] = f"{fake_bin}:{self.env['PATH']}"
        self.assert_applied(self.run_service(), 'unknown', '44000000')

    def test_source_changes_are_rechecked_on_each_run(self):
        self.assert_applied(self.run_service(), 'barrel', '160000000')
        usb_online = self.supplies / 'ucsi-source-psy-USBC000:001/online'
        usb_online.write_text('1\n')
        self.assert_applied(self.run_service(), 'usb', '44000000')
        usb_online.write_text('0\n')
        self.assert_applied(self.run_service(), 'barrel', '160000000')
        (self.supplies / 'AC/online').write_text('0\n')
        self.assert_applied(self.run_service(), 'battery', '44000000')

    def test_missing_thermal_driver_retries_and_fails_after_setting_pl1(self):
        self.thermal.unlink()
        fake_bin = self.root / 'bin'
        fake_bin.mkdir()
        sleeps = self.root / 'sleeps'
        sleep = fake_bin / 'sleep'
        sleep.write_text(f'#!/bin/sh\nprintf "x\\n" >> {shlex.quote(str(sleeps))}\n')
        sleep.chmod(0o755)
        self.env['PATH'] = f"{fake_bin}:{self.env['PATH']}"
        result = self.run_service()
        self.assertEqual(result.returncode, 1)
        self.assertIn('no writable tcc_offset_degree_celsius', result.stderr)
        self.assertEqual(len(sleeps.read_text().splitlines()), 30)
        for zone in self.zones:
            self.assertEqual((zone / 'constraint_0_power_limit_uw').read_text().strip(), '160000000')

    def test_invalid_constraint_fails_without_writing_that_zone(self):
        (self.zones[1] / 'constraint_0_name').write_text('short_term\n')
        result = self.run_service()
        self.assertEqual(result.returncode, 1)
        self.assertIn('missing or unexpected constraint 0', result.stderr)
        self.assertEqual((self.zones[0] / 'constraint_0_power_limit_uw').read_text().strip(), '160000000')
        self.assertEqual((self.zones[1] / 'constraint_0_power_limit_uw').read_text().strip(), '0')
        self.assertEqual(self.thermal.read_text().strip(), '13')

    def test_no_package_zone_fails_without_writing_other_zones(self):
        for zone in self.zones:
            (zone / 'name').write_text('package-1\n')
        result = self.run_service()
        self.assertEqual(result.returncode, 1)
        self.assertIn('no package-0 RAPL zone', result.stderr)
        for zone in self.zones:
            self.assertEqual((zone / 'constraint_0_power_limit_uw').read_text().strip(), '0')

    def test_write_failure_sets_failure_status(self):
        target = self.zones[1] / 'constraint_0_power_limit_uw'
        target.unlink()
        target.mkdir()
        result = self.run_service()
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.zones[0] / 'constraint_0_power_limit_uw').read_text().strip(), '160000000')
        self.assertEqual(self.thermal.read_text().strip(), '13')

    def test_unit_retains_sleep_targets_and_repeatable_start(self):
        after = re.search(r'^After=(.*)$', self.unit, re.M).group(1).split()
        wanted_by = re.search(r'^WantedBy=(.*)$', self.unit, re.M).group(1).split()
        self.assertIn('RemainAfterExit=no', self.unit)
        for target in ('suspend.target', 'hibernate.target', 'hybrid-sleep.target',
                       'suspend-then-hibernate.target'):
            self.assertIn(target, after)
            self.assertIn(target, wanted_by)

    def test_shell_syntax_and_shellcheck(self):
        script = self.root / 'execstart.sh'
        script.write_text(self.script + '\n')
        for command in (['/bin/sh', '-n', str(script)], ['shellcheck', '-s', 'sh', str(script)]):
            result = subprocess.run(command, env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_udev_triggers_only_requested_power_supplies(self):
        lines = [line for line in RULE.read_text().splitlines() if line and not line.startswith('#')]
        self.assertEqual(len(lines), 1)
        rule = lines[0]
        self.assertIn('SUBSYSTEM=="power_supply"', rule)
        self.assertIn('ACTION=="change"', rule)
        self.assertIn('RUN+="/usr/bin/systemctl --no-block start cpu-tcc-offset.service"', rule)
        match = re.search(r'KERNEL=="([^"]+)"', rule)
        self.assertIsNotNone(match)
        patterns = match.group(1).split('|')
        matches = lambda name: any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns)
        self.assertTrue(matches('AC'))
        self.assertTrue(matches('ucsi-source-psy-USBC000:001'))
        self.assertTrue(matches('ucsi-source-psy-USBC000:002'))
        self.assertFalse(matches('BAT0'))


if __name__ == '__main__':
    unittest.main()
