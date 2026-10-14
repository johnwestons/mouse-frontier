"""Exercise actual fixture selection/exclusivity without a native game engine."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[2]
POWERSHELL=shutil.which('pwsh') or shutil.which('powershell.exe')

FAKE_STARTUP='''
import hashlib,json,os,sys,time
from pathlib import Path
role=os.environ.get('MOUSE_FRONTIER_LAN_SMOKE_ROLE')
if role:
    harness=Path(sys.argv[0])
    (harness/('fake-'+role+'.started.json')).write_text(json.dumps({'role':role,'argv':sys.argv}))
    evidence={'role':role,'mobile':os.environ.get('MOUSE_FRONTIER_MOBILE'),
              'appdata':os.environ.get('APPDATA'),
              'mainHash':hashlib.sha256((harness/'main.lua').read_bytes()).hexdigest(),
              'confHash':hashlib.sha256((harness/'conf.lua').read_bytes()).hexdigest(),
              'hasAssets':(harness/'assets').is_dir(),'hasSounds':(harness/'sounds').is_dir(),
              'hasGame':(harness/'game').is_dir()}
    (harness/('fake-'+role+'.json')).write_text(json.dumps(evidence))
    if role=='host':
        print('LAN_SMOKE_LISTENING',flush=True)
        # Use the coordinator's bounded lifetime. A shorter independent fake
        # timeout used to let this host exit before the runner launched a peer.
        deadline=time.monotonic()+float(os.environ['FAKE_LAN_COORDINATOR_TIMEOUT'])
        connected=False
        while not connected and time.monotonic()<deadline:
            try:
                guest=json.loads((harness/'fake-guest.json').read_text())
                connected=guest.get('role')=='guest'
            except (FileNotFoundError,json.JSONDecodeError):pass
            if not connected:time.sleep(.01)
        if not connected:
            print('FAKE_HOST_NO_GUEST_HANDSHAKE',file=sys.stderr,flush=True)
            os._exit(7)
        (harness/'fake-host.peer-confirmed.json').write_text(json.dumps({'guest':guest['role']}))
    print('LAN_SMOKE_OK role='+role+' fakeRunnerEvidence=true',flush=True)
    os._exit(0)
'''


@unittest.skipUnless(os.name=='nt' and POWERSHELL,'Windows PowerShell required')
class DeviceControlsRunnerTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory(prefix='mouse frontier LAN controls ')
        self.addCleanup(temp.cleanup);self.root=Path(temp.name)
        tools=self.root/'tools';tools.mkdir()
        self.runner=tools/'run_lan_smoke.ps1';shutil.copyfile(ROOT/'tools/run_lan_smoke.ps1',self.runner)
        shutil.copytree(ROOT/'tools/guest-device-controls-smoke',tools/'guest-device-controls-smoke')
        shutil.copytree(ROOT/'tools/guest-travel-smoke',tools/'guest-travel-smoke')
        fixtures=tools/'tests/lua';fixtures.mkdir(parents=True)
        shutil.copyfile(ROOT/'tools/tests/lua/coop_fixtures.lua',fixtures/'coop_fixtures.lua')
        for directory in ('game','assets','sounds'):(self.root/directory).mkdir()
        self.fake=self.root/'fake-python';self.fake.mkdir()
        (self.fake/'sitecustomize.py').write_text(FAKE_STARTUP,encoding='utf-8')

    def run_fixture(self,*extra,fixture_switch='-DeviceControls'):
        report=self.root/'reports';env=os.environ.copy();env['PYTHONPATH']=str(self.fake)
        env['FAKE_LAN_COORDINATOR_TIMEOUT']='15'
        result=subprocess.run([POWERSHELL,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(self.runner),
            fixture_switch,'-LovePath',sys.executable,'-ReportDirectory',str(report),
            '-GameRoot',str(self.root),'-TimeoutSeconds','15',*extra],env=env,cwd=self.root,
            capture_output=True,text=True,timeout=30)
        if result.returncode and extra in ((),('-Mobile',)):
            # TempDirectory teardown must not erase the child stderr that
            # distinguishes a startup crash from a host handshake timeout.
            failure=ROOT/'.stabilization/lan-device-controls-runner-failures'/uuid.uuid4().hex
            failure.mkdir(parents=True)
            (failure/'caller.txt').write_text(result.stdout+result.stderr,encoding='utf-8')
            for path in report.rglob('*'):
                if path.is_file() and path.suffix in ('.log','.err','.rpt','.json'):
                    relative=path.relative_to(report);target=failure/relative;target.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copyfile(path,target)
            result.stdout+='\nRetained fake-engine diagnostics: '+str(failure)
        return result,report

    def test_selects_exact_fixture_with_application_assets_and_reports_touch_mode(self):
        process,reports=self.run_fixture('-Mobile')
        self.assertEqual(process.returncode,0,process.stdout+process.stderr)
        summary=(reports/'summary.rpt').read_text(encoding='utf-8-sig')
        self.assertIn('application=True',summary);self.assertIn('deviceControlsFixture=True',summary)
        self.assertIn('touchSimulation=True',summary)
        runs=list(reports.glob('run-*'));self.assertEqual(len(runs),1)
        self.assertEqual(json.loads((runs[0]/'fake-host.peer-confirmed.json').read_text()),{'guest':'guest'})
        for role in ('host','guest'):
            evidence=json.loads((runs[0]/f'fake-{role}.json').read_text())
            self.assertEqual(evidence['role'],role);self.assertEqual(evidence['mobile'],'1')
            self.assertIn(f'{role}-appdata',evidence['appdata'])
            self.assertTrue(evidence['hasAssets'] and evidence['hasSounds'] and evidence['hasGame'])
            for name in ('main','conf'):
                expected=hashlib.sha256((ROOT/f'tools/guest-device-controls-smoke/{name}.lua').read_bytes()).hexdigest()
                self.assertEqual(evidence[f'{name}Hash'],expected)

    def test_mixed_fixture_or_restart_rejected_before_engine_launch(self):
        for switch in ('-Adventure','-BossPressure','-BossHostRestart','-Battles','-Discovery','-LastStandHostRestart'):
            with self.subTest(switch=switch):
                process,reports=self.run_fixture(switch)
                self.assertNotEqual(process.returncode,0)
                self.assertIn('Choose one application fixture per run.',process.stdout)
                self.assertFalse(list(reports.glob('run-*')))
                summary=(reports/'summary.rpt').read_text(encoding='utf-8-sig')
                self.assertIn('exit=1',summary);self.assertIn('deviceControlsFixture=True',summary)

    def test_travel_selects_exact_fixture_with_application_assets_and_mobile_summary(self):
        process,reports=self.run_fixture('-Mobile',fixture_switch='-Travel')
        self.assertEqual(process.returncode,0,process.stdout+process.stderr)
        summary=(reports/'summary.rpt').read_text(encoding='utf-8-sig')
        for field in ('application=True','travelFixture=True','touchSimulation=True','deviceControlsFixture=False'):
            self.assertIn(field,summary)
        run=next(reports.glob('run-*'))
        for role in ('host','guest'):
            evidence=json.loads((run/f'fake-{role}.json').read_text())
            self.assertTrue(evidence['hasAssets'] and evidence['hasSounds'] and evidence['hasGame'])
            self.assertEqual(evidence['mobile'],'1')
            for name in ('main','conf'):
                expected=hashlib.sha256((ROOT/f'tools/guest-travel-smoke/{name}.lua').read_bytes()).hexdigest()
                self.assertEqual(evidence[f'{name}Hash'],expected)

    def test_travel_mixed_fixture_is_rejected_before_engine_launch(self):
        for switch in ('-DeviceControls','-Discovery','-BossHostRestart','-Train'):
            with self.subTest(switch=switch):
                process,reports=self.run_fixture(switch,fixture_switch='-Travel')
                self.assertNotEqual(process.returncode,0)
                self.assertIn('Choose one application fixture per run.',process.stdout)
                self.assertFalse(list(reports.glob('run-*')))

    def test_fake_host_cannot_report_success_without_peer_handshake(self):
        harness=self.root/'fake-handshake';harness.mkdir()
        for name in ('main.lua','conf.lua'):
            shutil.copyfile(ROOT/'tools/guest-device-controls-smoke'/name,harness/name)
        env=os.environ.copy();env.update(PYTHONPATH=str(self.fake),MOUSE_FRONTIER_LAN_SMOKE_ROLE='host',
            FAKE_LAN_COORDINATOR_TIMEOUT='.1')
        process=subprocess.run([sys.executable,str(harness)],env=env,cwd=self.root,
            capture_output=True,text=True,timeout=5)
        self.assertEqual(process.returncode,7,process.stdout+process.stderr)
        self.assertIn('LAN_SMOKE_LISTENING',process.stdout)
        self.assertIn('FAKE_HOST_NO_GUEST_HANDSHAKE',process.stderr)
        self.assertNotIn('LAN_SMOKE_OK',process.stdout)


if __name__=='__main__':unittest.main()
