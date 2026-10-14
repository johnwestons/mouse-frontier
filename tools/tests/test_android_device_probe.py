"""Run builder probe/report logic and wrapper against inert fake tools, never ADB."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')


@unittest.skipUnless(POWERSHELL, 'PowerShell unavailable')
class AndroidDeviceProbeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.marker = self.directory / 'fake-adb-calls.txt'
        self.fake_adb = self.directory / 'fake-adb.ps1'
        self.fake_adb.write_text('''param([string]$Command)
if($Command -ne 'devices'){throw 'Unexpected fake ADB command'}
Add-Content -LiteralPath $env:MOUSE_FRONTIER_FAKE_ADB_LOG -Value $Command
if($env:MOUSE_FRONTIER_FAKE_ADB_RESULT -eq 'error'){exit 7}
Write-Output 'List of devices attached'
if($env:MOUSE_FRONTIER_FAKE_ADB_RESULT -eq 'one'){
    Write-Output "fixture-serial`tdevice"
    Write-Output "not-authorized`tunauthorized"
}
exit 0
''', encoding='utf-8')

    def run_script(self, code, *arguments, result='one'):
        script = self.directory / 'test.ps1'
        script.write_text(code, encoding='utf-8')
        environment = dict(os.environ, MOUSE_FRONTIER_FAKE_ADB_LOG=str(self.marker),
                           MOUSE_FRONTIER_FAKE_ADB_RESULT=result)
        return subprocess.run([POWERSHELL, '-NoProfile', '-NonInteractive', '-File', str(script),
                               *map(str, arguments)], env=environment, capture_output=True,
                              text=True, timeout=20)

    def probe(self, skip=False, result='one'):
        completed = self.run_script('''param($Builder,$FakeAdb,$OutputRoot,[switch]$Skip)
$ErrorActionPreference='Stop'
$ast=[Management.Automation.Language.Parser]::ParseFile($Builder,[ref]$null,[ref]$null)
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-AndroidDeviceProbe'},$true)
Invoke-Expression $function.Extent.Text
$deviceProbe=Get-AndroidDeviceProbe -AdbPath $FakeAdb -SkipDeviceProbe:$Skip
# Evaluate the production report assignment using deliberately synthetic artifacts.
$report=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$apkReport'},$true)
$config=@{applicationId='fixture';versionName='fixture';versionCode=1};$packageManifest=@{}
$apkPath=Join-Path $OutputRoot 'fake.apk';[IO.File]::WriteAllText($apkPath,'synthetic')
$verifiedAbis=@();$packageBytes=0;$embeddedGameSha='fixture';$apkCoopAudit=@{}
$permissionDumpPath='fixture';$apkCoopAuditPath='fixture';$deviceLaunchVerified=$false
Invoke-Expression $report.Extent.Text
$apkReport | ConvertTo-Json -Depth 12 -Compress
''', ROOT / 'tools/build_android_apk.ps1', self.fake_adb, self.directory,
                                    *(['-Skip'] if skip else []), result=result)
        return completed

    def test_skipped_probe_invokes_no_adb_and_reports_unknown_count(self):
        completed = self.probe(skip=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertFalse(self.marker.exists(), 'skipped packaging touched fake ADB')
        self.assertIsNone(report['connectedAndroidDevices'])
        self.assertEqual(report['deviceProbeStatus'], 'not_probed')
        self.assertFalse(report['deviceLaunchVerified'])
        self.assertFalse(report['physicalNetworkVerified'])

    def test_default_probe_reports_only_ready_devices_and_known_zero(self):
        for state, count in [('one', 1), ('none', 0)]:
            with self.subTest(state=state):
                self.marker.unlink(missing_ok=True)
                completed = self.probe(result=state)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                report = json.loads(completed.stdout)
                self.assertEqual(report['connectedAndroidDevices'], count)
                self.assertEqual(report['deviceProbeStatus'], 'probed')
                self.assertEqual(self.marker.read_text().strip(), 'devices')
                self.assertFalse(report['deviceLaunchVerified'])

    def test_failed_probe_cannot_be_reported_as_zero_connected_devices(self):
        completed = self.probe(result='error')
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('connected device count is unknown', completed.stderr)
        self.assertEqual(self.marker.read_text().strip(), 'devices')

    def test_install_conflict_is_rejected_before_any_script_side_effect(self):
        for path in [ROOT / 'BUILD_ANDROID.ps1', ROOT / 'tools/build_android_apk.ps1']:
            with self.subTest(path=path.name):
                # Execute the actual parameter block and first guard. An inert
                # sentinel replaces all remaining build/download/install code.
                completed = self.run_script('''param($Source,$Marker)
$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$null,[ref]$null)
$guard=$ast.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.IfStatementAst]} | Select-Object -First 1
$code=$ast.ParamBlock.Extent.Text+"`n"+$ast.EndBlock.Statements[0].Extent.Text+"`n"+$guard.Extent.Text+"`n[IO.File]::WriteAllText('$($Marker.Replace("'","''"))','build-started')"
$script=[ScriptBlock]::Create($code)
if($Source.EndsWith('build_android_apk.ps1')){& $script -PackagePath 'not-a-package' -Install -SkipDeviceProbe}
else{& $script -Install -SkipDeviceProbe}
''', path, self.marker)
                self.assertNotEqual(completed.returncode, 0)
                self.assertIn('-Install cannot be combined with -SkipDeviceProbe', completed.stderr)
                self.assertFalse(self.marker.exists(), 'conflict reached build/install side effects')

    def test_actual_wrapper_forwards_skip_option_to_inert_apk_builder(self):
        tools = self.directory / 'tools'
        tools.mkdir()
        wrapper = self.directory / 'BUILD_ANDROID.ps1'
        shutil.copyfile(ROOT / 'BUILD_ANDROID.ps1', wrapper)
        (tools / 'build_mobile_package.py').write_text('''from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
directory=root/'output/mobile';directory.mkdir(parents=True)
(directory/'build-report.json').write_text(json.dumps({'package':'synthetic-package'}))
''', encoding='utf-8')
        for name in ['run_smoke.ps1', 'run_last_stand_smoke.ps1']:
            (tools / name).write_text('exit 0\n', encoding='utf-8')
        (tools / 'build_android_apk.ps1').write_text('''param($PackagePath,[switch]$Install,[switch]$SkipDeviceProbe)
@{package=$PackagePath;install=[bool]$Install;skip=[bool]$SkipDeviceProbe}|ConvertTo-Json -Compress
''', encoding='utf-8')
        completed = subprocess.run([POWERSHELL, '-NoProfile', '-NonInteractive', '-File', str(wrapper),
                                    '-SkipDeviceProbe'], capture_output=True, text=True, timeout=20)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(completed.stdout), {'package': 'synthetic-package', 'install': False, 'skip': True})
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main()
