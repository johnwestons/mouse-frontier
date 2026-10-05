"""Exercise the validation orchestrator with fake regression and engine children."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
POWERSHELL = shutil.which('powershell.exe') or shutil.which('pwsh')

FAKE_REGRESSION = r'''
import json
import os
from pathlib import Path
import sys
import time
Path('regression-evidence.json').write_text(json.dumps({
    'cwd': str(Path.cwd()), 'love': os.environ.get('LOVE_EXE'),
    'appdata': os.environ.get('APPDATA'),
}), encoding='utf-8')
print('FAKE_REGRESSION_STDOUT')
print('FAKE_REGRESSION_STDERR', file=sys.stderr)
if os.environ['FAKE_REGRESSION_CASE'] == 'flood':
    while True:
        print('FAKE_FLOOD_PROGRESS')
if os.environ['FAKE_REGRESSION_CASE'] == 'hang':
    sys.stderr.write('FAKE_TEST_IN_PROGRESS...')
    time.sleep(30)
sys.exit(7 if os.environ['FAKE_REGRESSION_CASE'] == 'nonzero' else 0)
'''

FAKE_ENGINE_RUNNER = r'''
param([string]$LovePath,[string]$ReportPath,[int]$TimeoutSeconds,[int]$Seed,[switch]$Mobile,[switch]$Full)
[pscustomobject]@{ love=$env:LOVE_EXE; cwd=(Get-Location).Path } |
    ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Output ('FAKE_ENGINE_GATE=' + $ReportPath)
exit 0
'''

CALLER = r'''
param([string]$Runner,[string]$Python,[string]$Reports,[string]$Evidence,[int]$RegressionTimeout)
$ErrorActionPreference='Stop'
$beforeLocation=(Get-Location).Path
$beforeLove=$env:LOVE_EXE
$beforeAppData=$env:APPDATA
$beforeUnbuffered=$env:PYTHONUNBUFFERED
& $Runner -PythonPath $Python -LovePath $Python -ReportDirectory $Reports -RegressionTimeoutSeconds $RegressionTimeout
$result=$LASTEXITCODE
[pscustomobject]@{
    beforeLocation=$beforeLocation; afterLocation=(Get-Location).Path
    beforeLove=$beforeLove; afterLove=$env:LOVE_EXE
    beforeAppData=$beforeAppData; afterAppData=$env:APPDATA
    beforeUnbuffered=$beforeUnbuffered; afterUnbuffered=$env:PYTHONUNBUFFERED
} | ConvertTo-Json | Set-Content -LiteralPath $Evidence -Encoding UTF8
exit $result
'''


@unittest.skipUnless(os.name == 'nt' and POWERSHELL, 'Windows PowerShell is required for the validation runner')
class ValidationRunnerBehaviorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='mouse frontier validation ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        tools = self.root / 'tools'
        tools.mkdir()
        self.runner = tools / 'run_validation.ps1'
        shutil.copyfile(ROOT / 'tools/run_validation.ps1', self.runner)
        (tools / 'run_tests.py').write_text(FAKE_REGRESSION, encoding='utf-8')
        for name in ('run_smoke.ps1', 'run_last_stand_smoke.ps1', 'run_zoom_smoke.ps1', 'run_mobile_pickup_smoke.ps1'):
            (tools / name).write_text(FAKE_ENGINE_RUNNER, encoding='utf-8')
        self.caller = self.root / 'caller.ps1'
        self.caller.write_text(CALLER, encoding='utf-8')
        self.caller_directory = self.root / 'caller directory'
        self.caller_directory.mkdir()
        self.reports = self.root / 'reports with spaces'
        self.evidence = self.root / 'caller-evidence.json'

    def invoke(self, scenario, timeout=10, observe_progress=False):
        environment = os.environ.copy()
        environment.update(FAKE_REGRESSION_CASE=scenario, LOVE_EXE='prior-user-engine',
                           APPDATA=str(self.root / 'sentinel appdata'), PYTHONUNBUFFERED='prior-user-value')
        command = [POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(self.caller),
                   '-Runner', str(self.runner), '-Python', sys.executable, '-Reports', str(self.reports),
                   '-Evidence', str(self.evidence), '-RegressionTimeout', str(timeout)]
        started = time.monotonic()
        process = subprocess.Popen(command, cwd=self.caller_directory, env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        if observe_progress:
            log = self.reports / 'regression.process.log'
            deadline = time.monotonic() + 8
            progress = False
            while process.poll() is None and time.monotonic() < deadline:
                if log.exists() and 'FAKE_REGRESSION_STDOUT' in log.read_text(encoding='utf-8'):
                    progress = True
                    break
                time.sleep(0.05)
            self.assertTrue(progress, 'regression output must be logged while the child is still running')
        output, _ = process.communicate(timeout=20)
        return process.returncode, output, time.monotonic() - started

    def assert_completed_gates(self, expected_exit):
        summary = json.loads((self.reports / 'validation-summary.json').read_text(encoding='utf-8-sig'))
        self.assertEqual([gate['name'] for gate in summary['results']],
                         ['regression', 'desktop', 'mobile', 'full-route', 'last-stand', 'zoom', 'mobile-pickup'])
        self.assertEqual(summary['results'][0]['exitCode'], expected_exit)
        self.assertTrue(all(gate['exitCode'] == 0 for gate in summary['results'][1:]))
        self.assertEqual((summary['passed'], summary['failed']), (6 if expected_exit else 7, 1 if expected_exit else 0))
        self.assertEqual(summary['status'], 'failed' if expected_exit else 'passed')
        log = (self.reports / 'regression.process.log').read_text(encoding='utf-8')
        self.assertIn('FAKE_REGRESSION_STDOUT', log)
        self.assertIn('FAKE_REGRESSION_STDERR', log)
        evidence = json.loads(self.evidence.read_text(encoding='utf-8-sig'))
        for field in ('Location', 'Love', 'AppData', 'Unbuffered'):
            self.assertEqual(evidence['before' + field], evidence['after' + field], field)
        regression = json.loads((self.root / 'regression-evidence.json').read_text(encoding='utf-8'))
        self.assertEqual(Path(regression['cwd']), self.root)
        self.assertEqual(Path(regression['love']), Path(sys.executable))
        self.assertEqual(regression['appdata'], str(self.root / 'sentinel appdata'))
        return log

    def test_nonzero_regression_preserves_exit_output_and_runs_remaining_gates(self):
        code, output, _ = self.invoke('nonzero')
        self.assertEqual(code, 7, output)
        self.assert_completed_gates(7)

    def test_hung_regression_times_out_and_preserves_partial_progress(self):
        code, output, elapsed = self.invoke('hang', timeout=1, observe_progress=True)
        self.assertEqual(code, 124, output)
        self.assertLess(elapsed, 15, 'the 30-second fake hang must be terminated promptly')
        log = self.assert_completed_gates(124)
        self.assertIn('REGRESSION_TIMEOUT exit=124 seconds=1', log)
        self.assertIn('FAKE_TEST_IN_PROGRESS...', log)

    def test_successful_regression_returns_zero_with_all_gates_passed(self):
        code, output, _ = self.invoke('passed')
        self.assertEqual(code, 0, output)
        self.assert_completed_gates(0)

    def test_continuous_output_cannot_starve_regression_timeout(self):
        code, output, elapsed = self.invoke('flood', timeout=1, observe_progress=True)
        self.assertEqual(code, 124, output)
        self.assertLess(elapsed, 15, 'continuous stdout must not prevent timeout checks')
        log = self.assert_completed_gates(124)
        self.assertIn('FAKE_FLOOD_PROGRESS', log)
        self.assertIn('REGRESSION_TIMEOUT exit=124 seconds=1', log)

    def test_nonpositive_regression_timeout_is_rejected_before_launch(self):
        code, output, _ = self.invoke('passed', timeout=0)
        self.assertNotEqual(code, 0, output)
        self.assertIn('RegressionTimeoutSeconds', output)
        self.assertFalse((self.root / 'regression-evidence.json').exists())


if __name__ == '__main__':
    unittest.main()
