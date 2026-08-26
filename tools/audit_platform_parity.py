"""Verify that the desktop and Android release candidates share one tested game."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DESKTOP_REPORT = ROOT / ".stabilization" / "final-parity-desktop.rpt"
DEFAULT_MOBILE_REPORT = ROOT / ".stabilization" / "mobile-package-smoke.rpt"
DEFAULT_ROUTE_REPORT = ROOT / ".stabilization" / "final-parity-route.rpt"
DEFAULT_BUILD_REPORT = ROOT / "output" / "mobile" / "build-report.json"
DEFAULT_APK_REPORT = ROOT / "output" / "mobile" / "apk-report.json"
DEFAULT_AUDIT_REPORT = ROOT / ".stabilization" / "final-parity-audit.json"

CHECKPOINT_PATTERN = re.compile(r"\bCHECKPOINT\s+(\S+)\s+result=(PASS|FAIL)\b")
EXPECTED_MOBILE_ONLY = {
    "mobile_action_press_release",
    "mobile_exit_home_touch",
    "mobile_joystick_move_and_run",
    "mobile_menu_touch",
    "mobile_pinch_zoom",
    "mobile_settlement_help_touch",
}


class AuditError(RuntimeError):
    """A parity or release invariant failed."""


def read_checkpoints(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise AuditError(f"Missing smoke report: {path}")
    checkpoints: dict[str, str] = {}
    for name, result in CHECKPOINT_PATTERN.findall(path.read_text(encoding="utf-8")):
        if name in checkpoints:
            raise AuditError(f"Duplicate checkpoint {name!r} in {path}")
        checkpoints[name] = result
    if not checkpoints:
        raise AuditError(f"No checkpoints found in {path}")
    failures = sorted(name for name, result in checkpoints.items() if result != "PASS")
    if failures:
        raise AuditError(f"Failed checkpoints in {path}: {', '.join(failures)}")
    return checkpoints


def compare_checkpoint_sets(
    desktop: dict[str, str], mobile: dict[str, str]
) -> dict[str, list[str]]:
    desktop_names = set(desktop)
    mobile_names = set(mobile)
    desktop_only = sorted(desktop_names - mobile_names)
    mobile_only = sorted(mobile_names - desktop_names)
    if desktop_only:
        raise AuditError(
            "Packaged mobile smoke is missing desktop checkpoints: "
            + ", ".join(desktop_only)
        )
    unexpected = sorted(set(mobile_only) - EXPECTED_MOBILE_ONLY)
    missing = sorted(EXPECTED_MOBILE_ONLY - set(mobile_only))
    if unexpected or missing:
        details = []
        if missing:
            details.append("missing mobile checks: " + ", ".join(missing))
        if unexpected:
            details.append("unreviewed mobile-only checks: " + ", ".join(unexpected))
        raise AuditError("Mobile parity contract changed; " + "; ".join(details))
    return {
        "shared": sorted(desktop_names),
        "desktopOnly": desktop_only,
        "mobileOnly": mobile_only,
    }


def read_json(path: Path) -> dict:
    if not path.is_file():
        raise AuditError(f"Missing build report: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def git_head() -> str:
    return subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit(
    desktop_path: Path,
    mobile_path: Path,
    route_path: Path,
    build_path: Path,
    apk_path: Path,
    require_device: bool,
) -> dict:
    desktop = read_checkpoints(desktop_path)
    mobile = read_checkpoints(mobile_path)
    route = read_checkpoints(route_path)
    parity = compare_checkpoint_sets(desktop, mobile)
    if "full_journey_to_stop_50" not in route:
        raise AuditError("Full-route report did not verify stop 50")

    build = read_json(build_path)
    apk = read_json(apk_path)
    head = git_head()
    if build.get("sourceCommit") != head:
        raise AuditError(
            f"Mobile package commit {build.get('sourceCommit')} does not match HEAD {head}"
        )
    if build.get("sourceDirty") is not False:
        raise AuditError("Mobile package was built from a dirty source tree")

    package = Path(build.get("package", ""))
    installed_apk = Path(apk.get("apk", ""))
    if not package.is_file():
        raise AuditError(f"Packaged .love file is missing: {package}")
    if not installed_apk.is_file():
        raise AuditError(f"Android APK is missing: {installed_apk}")
    if apk.get("signed") is not True:
        raise AuditError("Android APK signature was not verified")
    if apk.get("embeddedGameBytes") != build.get("packageBytes"):
        raise AuditError("APK does not contain the audited shared game package")
    actual_apk_sha = sha256(installed_apk)
    if apk.get("sha256") != actual_apk_sha:
        raise AuditError("APK checksum does not match its build report")
    if apk.get("connectedAndroidDevices", 0) < 1:
        raise AuditError("No connected Android device was recorded")
    if require_device and apk.get("deviceLaunchVerified") is not True:
        raise AuditError("Installed game did not pass the on-device startup check")

    return {
        "status": "passed",
        "sourceCommit": head,
        "sourceDirty": False,
        "desktopCheckpoints": len(desktop),
        "mobileCheckpoints": len(mobile),
        "sharedCheckpoints": len(parity["shared"]),
        "mobileOnlyCheckpoints": parity["mobileOnly"],
        "routeCheckpoints": len(route),
        "reachedStop50": True,
        "apk": str(installed_apk),
        "apkSha256": actual_apk_sha,
        "signed": True,
        "connectedAndroidDevices": apk.get("connectedAndroidDevices"),
        "deviceLaunchVerified": apk.get("deviceLaunchVerified") is True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop", type=Path, default=DEFAULT_DESKTOP_REPORT)
    parser.add_argument("--mobile", type=Path, default=DEFAULT_MOBILE_REPORT)
    parser.add_argument("--route", type=Path, default=DEFAULT_ROUTE_REPORT)
    parser.add_argument("--build-report", type=Path, default=DEFAULT_BUILD_REPORT)
    parser.add_argument("--apk-report", type=Path, default=DEFAULT_APK_REPORT)
    parser.add_argument("--output", type=Path, default=DEFAULT_AUDIT_REPORT)
    parser.add_argument("--require-device", action="store_true")
    args = parser.parse_args()
    try:
        result = audit(
            args.desktop,
            args.mobile,
            args.route,
            args.build_report,
            args.apk_report,
            args.require_device,
        )
    except (AuditError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f"PARITY_AUDIT_FAILED: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(
        "PARITY_AUDIT_OK: "
        f"desktop={result['desktopCheckpoints']} "
        f"mobile={result['mobileCheckpoints']} "
        f"route={result['routeCheckpoints']} "
        f"device={result['deviceLaunchVerified']}"
    )
    print(f"PARITY_AUDIT_REPORT={args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
