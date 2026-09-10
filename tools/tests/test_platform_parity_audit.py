from __future__ import annotations

import tempfile
import unittest
import json
import zipfile
from pathlib import Path
from unittest.mock import patch

from tools import audit_platform_parity as parity


class PlatformParityAuditTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        package, apk_path = directory / "game.love", directory / "game.apk"
        package.write_bytes(b"current game content")
        self.write_apk(apk_path, package.read_bytes())
        build = {"sourceCommit": "test-head", "sourceDirty": False,
                 "applicationId": "com.mousefrontier.game", "versionName": "test", "versionCode": 5,
                 "package": str(package), "packageBytes": package.stat().st_size,
                 "packageSha256": parity.sha256(package)}
        apk = {key: build[key] for key in ("sourceCommit", "sourceDirty", "applicationId", "versionName", "versionCode")}
        apk.update(apk=str(apk_path), signed=True, identityVerified=True,
                   verifiedAbis=["arm64-v8a", "armeabi-v7a", "x86_64"],
                   sha256=parity.sha256(apk_path), embeddedGameBytes=package.stat().st_size,
                   embeddedGameSha256=parity.sha256(package),
                   connectedAndroidDevices=0, deviceLaunchVerified=False)
        build_report, apk_report = directory / "build.json", directory / "apk.json"
        build_report.write_text(json.dumps(build), encoding="utf-8")
        apk_report.write_text(json.dumps(apk), encoding="utf-8")
        paths = (self.report(("shared", "PASS")),
                 self.report(("shared", "PASS"), *((name, "PASS") for name in parity.EXPECTED_MOBILE_ONLY)),
                 self.report(("full_journey_to_stop_50", "PASS")), build_report, apk_report)
        return paths, package, apk_path, apk

    @staticmethod
    def write_apk(path, embedded):
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("assets/game.love", embedded)
            for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
                archive.writestr(f"lib/{abi}/liblove.so", b"test engine")

    def test_offline_artifact_audit_does_not_claim_device_verification(self) -> None:
        paths, _, _, _ = self.fixture()
        with patch.object(parity, "git_head", return_value="test-head"):
            result = parity.audit(*paths, require_device=False)
            self.assertFalse(result["deviceLaunchVerified"])
            with self.assertRaisesRegex(parity.AuditError, "No connected Android device"):
                parity.audit(*paths, require_device=True)

    def test_same_length_stale_embedded_package_is_rejected(self) -> None:
        paths, package, apk_path, apk = self.fixture()
        self.write_apk(apk_path, b"x" * package.stat().st_size)
        apk["sha256"] = parity.sha256(apk_path)
        paths[-1].write_text(json.dumps(apk), encoding="utf-8")
        with patch.object(parity, "git_head", return_value="test-head"):
            with self.assertRaisesRegex(parity.AuditError, "embedded game checksum"):
                parity.audit(*paths, require_device=False)

    def test_changed_package_is_rejected_even_when_length_is_unchanged(self) -> None:
        paths, package, _, _ = self.fixture()
        package.write_bytes(b"x" * package.stat().st_size)
        with patch.object(parity, "git_head", return_value="test-head"):
            with self.assertRaisesRegex(parity.AuditError, "Game package checksum"):
                parity.audit(*paths, require_device=False)

    def report(self, *checkpoints: tuple[str, str]) -> Path:
        temporary = tempfile.NamedTemporaryFile(
            mode="w", suffix=".rpt", encoding="utf-8", delete=False
        )
        with temporary:
            for name, result in checkpoints:
                temporary.write(f"CHECKPOINT {name} result={result} details={{}}\n")
        self.addCleanup(Path(temporary.name).unlink, missing_ok=True)
        return Path(temporary.name)

    def test_report_parser_rejects_failed_checkpoint(self) -> None:
        report = self.report(("shared", "FAIL"))
        with self.assertRaises(parity.AuditError):
            parity.read_checkpoints(report)

    def test_mobile_must_include_all_shared_and_touch_checks(self) -> None:
        desktop = {"shared": "PASS"}
        mobile = {"shared": "PASS"} | {
            name: "PASS" for name in parity.EXPECTED_MOBILE_ONLY
        }
        comparison = parity.compare_checkpoint_sets(desktop, mobile)
        self.assertEqual(comparison["desktopOnly"], [])
        self.assertEqual(set(comparison["mobileOnly"]), parity.EXPECTED_MOBILE_ONLY)

    def test_mobile_contract_rejects_missing_shared_checkpoint(self) -> None:
        with self.assertRaises(parity.AuditError):
            parity.compare_checkpoint_sets({"shared": "PASS"}, {})


if __name__ == "__main__":
    unittest.main()
