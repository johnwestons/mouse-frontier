from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools import audit_platform_parity as parity


class PlatformParityAuditTests(unittest.TestCase):
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
