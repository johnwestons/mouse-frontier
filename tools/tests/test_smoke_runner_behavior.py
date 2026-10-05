"""Run the real watchdog against a fake engine to prove failed evidence fails."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
POWERSHELL = shutil.which("pwsh") or shutil.which("powershell")

FAKE_ENGINE = r'''
import json
import os
from pathlib import Path
import sys
import time

scenario = os.environ["FAKE_SMOKE_CASE"]
evidence = {
    "appdata": os.environ.get("APPDATA"),
    "seed": os.environ.get("MOUSE_FRONTIER_SMOKE_SEED"),
    "repair": os.environ.get("MOUSE_FRONTIER_SMOKE_REPAIR_ONLY"),
    "trainCapture": os.environ.get("MOUSE_FRONTIER_SMOKE_CAPTURE_TRAIN"),
    "aidCapture": os.environ.get("MOUSE_FRONTIER_SMOKE_CAPTURE_FIRST_AID"),
}
Path(os.environ["FAKE_SMOKE_EVIDENCE"]).write_text(json.dumps(evidence), encoding="utf-8")
if scenario == "timeout":
    time.sleep(30)
    sys.exit(0)
if scenario == "crash":
    print("FAKE_CRASH", file=sys.stderr)
    sys.exit(7)
if scenario == "missing":
    sys.exit(0)
report_path = Path(os.environ["MOUSE_FRONTIER_SMOKE_REPORT"])
if scenario == "empty":
    report_path.write_text("", encoding="utf-8")
    sys.exit(0)
run_id = os.environ["MOUSE_FRONTIER_SMOKE_RUN_ID"]
if scenario == "wrong_run":
    run_id = "old-run-id"
mode = "full-journey" if os.environ.get("MOUSE_FRONTIER_SMOKE_FULL") == "1" else "autoplay"
mobile = "true" if os.environ.get("MOUSE_FRONTIER_MOBILE") == "1" else "false"
if scenario == "wrong_mode":
    mode = "full-journey" if mode == "autoplay" else "autoplay"
if scenario == "wrong_mobile":
    mobile = "false" if mobile == "true" else "true"
scope = "repair-only" if scenario == "wrong_scope" else "complete"
seed = "38" if scenario == "wrong_seed" else os.environ["MOUSE_FRONTIER_SMOKE_SEED"]
step = "0.2" if scenario == "wrong_step" else os.environ["MOUSE_FRONTIER_SMOKE_STEP"]
character = os.environ.get("MOUSE_FRONTIER_SMOKE_CHARACTER") or "mail-mouse.png"
if not character.endswith(".png"):
    character += ".png"
if scenario == "wrong_character":
    character = "botanist-frog.png"
stamp = "[2026-10-04T12:00:00Z] "
lines = [f"run_id={run_id} started=2026-10-04T12:00:00Z",
         f'META mode="{mode}"', f"META mobile={mobile}", f'META scope="{scope}"',
         f"META seed={seed}", f"META updateStep={step}", f'META character="{character}"']
if scenario == "missing_run":
    lines.pop(0)
manifest = json.loads(Path(os.environ["FAKE_SMOKE_MANIFEST"]).read_text(encoding="utf-8"))
names = list(manifest["common"])
if os.environ.get("MOUSE_FRONTIER_MOBILE") == "1":
    names.extend(manifest["mobile"])
if os.environ.get("MOUSE_FRONTIER_SMOKE_FULL") == "1":
    names.extend(manifest["full"])
names = list(dict.fromkeys(names))
if scenario == "reduced_complete":
    names.remove(manifest["common"][0])
if scenario == "reduced_mobile":
    names.remove(manifest["mobile"][0])
if scenario == "reduced_full":
    names.remove(manifest["full"][0])
planned = 0 if scenario == "zero" else len(names)
lines.append(f"META plannedCheckpoints={planned}")
if planned:
    planned_names = list(names)
    if scenario == "duplicate_plan":
        planned_names[-1] = planned_names[0]
    for index, name in enumerate(planned_names, 1):
        if scenario == "partial_plan" and index == planned:
            continue
        if scenario == "gap_index" and index == planned:
            index += 1
        lines.append(f'META planned_step_{index}="{name}"')
    for name in names:
        lines.append(f"STEP {name} status=passed")
    checkpoint_names = list(names)
    if scenario == "duplicate_checkpoint":
        checkpoint_names[-1] = checkpoint_names[0]
    for index, name in enumerate(checkpoint_names, 1):
        if scenario == "partial_checkpoints" and index == planned:
            continue
        result = "FAIL" if scenario == "failed_checkpoint" and index == planned else "PASS"
        lines.append(f"CHECKPOINT {name} result={result}")
status = "captured" if scenario == "capture" else "failed" if scenario == "failed_summary" else "passed"
errors = 1 if scenario == "errors" else 0
lines.append(f"SUMMARY status={status} steps={planned} checkpoints={planned} values=0 warnings=0 errors={errors} duration=0.01")
if scenario == "duplicate_summary":
    lines.append(lines[-1])
report_path.write_text("\n".join(stamp + line for line in lines) + "\n", encoding="utf-8")
'''


@unittest.skipUnless(os.name == "nt" and POWERSHELL, "Windows PowerShell is required for the process watchdog")
class SmokeRunnerBehaviorTests(unittest.TestCase):
    def invoke(self, scenario: str, *, full=False, mobile=False, timeout=10, character=None):
        temporary = tempfile.TemporaryDirectory(prefix="mouse-frontier-runner-unit-")
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        fake = directory / "fake_engine.py"
        fake.write_text(FAKE_ENGINE, encoding="utf-8")
        report = directory / "smoke.rpt"
        evidence = directory / "evidence.json"
        original_appdata = directory / "original-appdata"
        original_appdata.mkdir()
        marker = original_appdata / "untouched.txt"
        marker.write_text("test sentinel", encoding="utf-8")
        environment = os.environ.copy()
        environment.update(APPDATA=str(original_appdata), FAKE_SMOKE_CASE=scenario,
                           FAKE_SMOKE_EVIDENCE=str(evidence), FAKE_SMOKE_MANIFEST=str(ROOT / "tools/smoke_required_checkpoints.json"),
                           MOUSE_FRONTIER_SMOKE_REPAIR_ONLY="1",
                           MOUSE_FRONTIER_SMOKE_CAPTURE_TRAIN="1", MOUSE_FRONTIER_SMOKE_CAPTURE_FIRST_AID="1")
        command = [str(POWERSHELL), "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                   "-File", str(ROOT / "tools/run_smoke.ps1"), "-LovePath", sys.executable,
                   "-PackagePath", str(fake), "-ReportPath", str(report), "-TimeoutSeconds", str(timeout),
                   "-ReportFlushSeconds", "0", "-Seed", "37"]
        if full:
            command.append("-Full")
        if mobile:
            command.append("-Mobile")
        if character:
            command.extend(("-Character", character))
        result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=timeout + 20)
        self.assertTrue(marker.is_file(), "runner deleted files in original APPDATA")
        self.assertEqual(marker.read_text(encoding="utf-8"), "test sentinel")
        evidence_data = json.loads(evidence.read_text(encoding="utf-8")) if evidence.is_file() else None
        status_file = report.with_name(report.name + ".status.txt")
        raw_status = status_file.read_bytes() if status_file.exists() else b""
        status = raw_status.decode("utf-16" if raw_status.startswith(b"\xff\xfe") else "utf-8-sig")
        return result, status, evidence_data, original_appdata, directory

    def assert_rejected(self, scenario, code=2, **options):
        result, status, _, _, _ = self.invoke(scenario, timeout=1 if scenario == "timeout" else 10, **options)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertIn("TIMEOUT" if code == 124 else "FAILED" if code == 7 else "INCOMPLETE", status)

    def test_complete_plan_passes_for_desktop_mobile_and_full_modes(self):
        for full, mobile in ((False, False), (False, True), (True, False), (True, True)):
            with self.subTest(full=full, mobile=mobile):
                result, status, _, _, _ = self.invoke("passed", full=full, mobile=mobile)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                manifest = json.loads((ROOT / "tools/smoke_required_checkpoints.json").read_text(encoding="utf-8"))
                names = manifest["common"] + (manifest["mobile"] if mobile else []) + (manifest["full"] if full else [])
                self.assertIn(f"COMPLETE exit=0 checkpoints={len(set(names))} seed=37", status)

    def test_matching_reduced_plans_cannot_omit_required_gameplay_coverage(self):
        self.assert_rejected("reduced_complete")
        self.assert_rejected("reduced_mobile", mobile=True)
        self.assert_rejected("reduced_full", full=True)

    def test_report_must_match_requested_seed_and_update_step(self):
        self.assert_rejected("wrong_seed")
        self.assert_rejected("wrong_step")

    def test_character_selection_is_normalized_and_validated(self):
        for character in ("mail-mouse", "mail-mouse.png"):
            with self.subTest(character=character):
                result, _, _, _, _ = self.invoke("passed", character=character)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_rejected("wrong_character", character="mail-mouse")

    def test_inherited_repair_capture_flags_are_cleared_and_appdata_is_isolated(self):
        result, _, evidence, original, directory = self.invoke("passed")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(evidence["seed"], "37")
        # Windows process environment APIs may represent a removed value as
        # either absent or empty; both must disable the inherited mode.
        self.assertFalse(evidence["repair"])
        self.assertFalse(evidence["trainCapture"])
        self.assertFalse(evidence["aidCapture"])
        isolated = Path(evidence["appdata"])
        self.assertNotEqual(isolated, original)
        self.assertEqual(isolated.parent.parent, directory)
        self.assertEqual(isolated.name, "appdata")
        self.assertTrue(isolated.parent.name.startswith("smoke-run-"))

    def test_missing_or_empty_report_is_rejected(self):
        for scenario in ("missing", "empty"):
            with self.subTest(scenario=scenario):
                self.assert_rejected(scenario)

    def test_partial_checkpoint_or_plan_and_index_gap_are_rejected(self):
        for scenario in ("partial_checkpoints", "partial_plan", "gap_index"):
            with self.subTest(scenario=scenario):
                self.assert_rejected(scenario)

    def test_duplicate_checkpoint_or_plan_names_are_rejected(self):
        for scenario in ("duplicate_checkpoint", "duplicate_plan"):
            with self.subTest(scenario=scenario):
                self.assert_rejected(scenario)

    def test_zero_checkpoint_plan_is_rejected(self):
        self.assert_rejected("zero")

    def test_failed_capture_and_duplicate_summaries_are_rejected(self):
        for scenario in ("failed_summary", "capture", "duplicate_summary", "errors", "failed_checkpoint"):
            with self.subTest(scenario=scenario):
                self.assert_rejected(scenario)

    def test_wrong_or_missing_run_id_is_rejected(self):
        for scenario in ("wrong_run", "missing_run"):
            with self.subTest(scenario=scenario):
                self.assert_rejected(scenario)

    def test_wrong_requested_mode_mobile_and_scope_are_rejected(self):
        for scenario in ("wrong_mode", "wrong_mobile", "wrong_scope"):
            with self.subTest(scenario=scenario):
                self.assert_rejected(scenario)

    def test_nonzero_engine_crash_is_preserved(self):
        self.assert_rejected("crash", code=7)

    def test_hung_engine_is_killed_and_returns_timeout(self):
        self.assert_rejected("timeout", code=124)


if __name__ == "__main__":
    unittest.main()
