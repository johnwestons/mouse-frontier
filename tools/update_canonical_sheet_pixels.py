"""Compare, or explicitly update, reviewed canonical animation pixel fingerprints.

The immutable inputs are the canonical PNG paths in the calibrated character
motion specs. Installed expectations are derived from those references using
the reviewed cleanup policy; installed images are never inputs to this tool.
The default is read-only; --write-reviewed-references records that derivation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
MANIFEST = ROOT / "character-motion" / "canonical_sheet_pixels.json"
ACTION_FIELDS = ("walk_animation", "idle_animation", "run_animation")
DIRECTIONS = {"east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"}
NORMALIZATION_TOOL = "tools/build_directional_character_assets.py"
REVIEWED_POLICY_SHA256 = "5c8b1e4c4779985e0fdee7fec7575f8b8b2202299a087e300b9f12f8129a07d0"
SOURCE_COMMIT = "e13ad7f655cc1f48394e5a0e22118aab125d576a"
REVIEW_EVIDENCE = "docs/audits/2026-10-05-canonical-sprite-cleanup.md"
SOURCE_FIELDS = {"source_path", "source_filename", "width", "height", "rgba_sha256"}


def normalization_record() -> dict:
    # Bind the complete module, including both color rules and ALPHA_THRESHOLD.
    # Normalize CRLF so Windows and LF checkouts share the same policy identity.
    policy = (ROOT / NORMALIZATION_TOOL).read_bytes().replace(b"\r\n", b"\n")
    digest = hashlib.sha256(policy).hexdigest()
    if digest != REVIEWED_POLICY_SHA256:
        raise ValueError("Cleanup policy changed; review it before changing the pinned policy fingerprint")
    return {
        "id": "edge-connected-magenta-fringe-v1",
        "function": "remove_edge_connected_magenta_fringe_pixels",
        "tool": NORMALIZATION_TOOL,
        "policy_sha256": digest,
        "source_commit": SOURCE_COMMIT,
        "review_evidence": REVIEW_EVIDENCE,
    }


def canonical_source_path(value: str) -> Path:
    source = PurePosixPath(value)
    if source.is_absolute() or PureWindowsPath(value).drive or ".." in source.parts or "\\" in value:
        raise ValueError("Canonical source must stay inside the repository")
    path = (ROOT / source).resolve()
    if not path.is_relative_to(ROOT.resolve()):
        raise ValueError("Canonical source must stay inside the repository")
    installed_root = (ROOT / "assets/sprites/character-animations").resolve()
    if path.is_relative_to(installed_root):
        raise ValueError("Canonical source must be a reviewed reference PNG, never an installed image")
    return path


def calibrated_characters() -> list[str]:
    lua_path = os.environ.get("LUA_RUNTIME_PYTHONPATH")
    if not lua_path and (ROOT / ".stabilization" / "python-deps").is_dir():
        lua_path = str(ROOT / ".stabilization" / "python-deps")
    if lua_path:
        sys.path.insert(0, lua_path)
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + lua.globals().package.path
    lua.execute("Motion = require('game.character_motion')")
    return sorted(Path(filename).stem for filename, profile in lua.globals().Motion.profiles.items()
                  if profile["runPixelsPerFrame"] is not None)


def build_manifest(previous: dict | None = None) -> dict:
    if previous is None:
        if not MANIFEST.is_file():
            raise ValueError("Existing original source fingerprints are required; refusing to create an unbound baseline")
        previous = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if previous.get("version") not in {1, 2} or previous.get("pixel_mode") != "RGBA" or previous.get("hash_algorithm") != "sha256":
        raise ValueError("Existing canonical source contract has an unsupported format")
    normalization = normalization_record()
    if previous["version"] == 2 and previous.get("normalization") != normalization:
        raise ValueError("Existing cleanup policy/provenance changed; refusing to replace the reviewed normalization contract")
    calibrated = calibrated_characters()
    old_characters = previous.get("characters", {})
    if set(old_characters) != set(calibrated):
        raise ValueError("Existing original source fingerprints must cover exactly the calibrated characters")
    # Import only after checking the bound module on disk.
    from tools.build_directional_character_assets import remove_edge_connected_magenta_fringe_pixels

    characters = {}
    for character in calibrated:
        spec = json.loads((ROOT / "character-motion" / (character + ".json")).read_text(encoding="utf-8"))
        if spec["character"] != character:
            raise ValueError(f"{character}: spec character does not match filename")
        if set(spec["directions"]) != DIRECTIONS or any(direction["mirror_x"] for direction in spec["directions"].values()):
            raise ValueError(f"{character}: calibrated canonical references require eight authored directions")
        for direction, mapping in spec["directions"].items():
            for mode, field in zip(("walk", "idle", "run"), ACTION_FIELDS):
                if mapping[field] != f"{mode}_{direction}":
                    raise ValueError(f"{character}/{direction}: {field} must map to {mode}_{direction}")
        actions = {direction[field] for direction in spec["directions"].values() for field in ACTION_FIELDS}
        if len(actions) != 24 or actions != set(spec["animations"]):
            raise ValueError(f"{character}: spec animation keys do not match directional locomotion coverage")
        if set(old_characters[character]) != actions:
            raise ValueError(f"{character}: original source fingerprint action coverage changed")
        build = json.loads((ROOT / "character-motion" / (character + "-build.json")).read_text(encoding="utf-8"))
        if build.get("character") != character or build.get("framing", {}).get("remove_edge_connected_magenta_fringe") is not True:
            raise ValueError(f"{character}: build framing must explicitly opt into the reviewed magenta cleanup")
        overrides = (list(build.get("idle_sets", [])) + list(build.get("walks", {}).values())
                     + list(build.get("runs", {}).values()))
        if any(isinstance(item, dict) and item.get("remove_edge_connected_magenta_fringe", True) is not True for item in overrides):
            raise ValueError(f"{character}: per-action framing disables the reviewed magenta cleanup")
        sheets = {}
        for action in sorted(actions):
            animation = spec["animations"][action]
            source = PurePosixPath(animation["path"])
            with Image.open(canonical_source_path(animation["path"])) as image:
                rgba = image.convert("RGBA")
                expected_size = (animation["frame_width"] * animation["frame_count"], animation["frame_height"])
                if rgba.size != expected_size:
                    raise ValueError(f"{character}/{action}: reference size {rgba.size} != spec size {expected_size}")
                original = {
                    "source_path": source.as_posix(),
                    "source_filename": source.name,
                    "width": rgba.width,
                    "height": rgba.height,
                    "rgba_sha256": hashlib.sha256(rgba.tobytes()).hexdigest(),
                }
                old_source = {key: old_characters[character][action].get(key) for key in SOURCE_FIELDS}
                if old_source != original:
                    raise ValueError(f"{character}/{action}: canonical source/path/dimensions changed; original fingerprints are immutable")
                cleaned = remove_edge_connected_magenta_fringe_pixels(rgba)
                before = np.asarray(rgba, dtype=np.uint8)
                after = np.asarray(cleaned, dtype=np.uint8)
                if cleaned.size != rgba.size:
                    raise ValueError(f"{character}/{action}: cleanup changed source dimensions")
                removed = (before[:, :, 3] != 0) & (after[:, :, 3] == 0)
                sheets[action] = {
                    **original,
                    "installed_rgba_sha256": hashlib.sha256(cleaned.tobytes()).hexdigest(),
                    "removed_pixels": int(np.count_nonzero(removed)),
                }
        characters[character] = sheets
    return {"version": 2, "pixel_mode": "RGBA", "hash_algorithm": "sha256", "normalization": normalization, "characters": characters}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-reviewed-references", action="store_true",
                        help="explicitly record the reviewed cleanup derivation while preserving original source fingerprints")
    args = parser.parse_args(argv)
    try:
        previous = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.is_file() else None
        candidate = build_manifest(previous)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Canonical fingerprint update refused: {error}")
        return 2
    count = sum(len(sheets) for sheets in candidate["characters"].values())
    if previous == candidate:
        print(f"Canonical fingerprints match: {count} sheets across {len(candidate['characters'])} characters.")
        return 0
    old_characters = previous.get("characters", {}) if previous else {}
    for character in sorted(set(old_characters) | set(candidate["characters"])) if previous else []:
        old_sheets = old_characters.get(character, {})
        new_sheets = candidate["characters"].get(character, {})
        for action in sorted(set(old_sheets) | set(new_sheets)):
            if old_sheets.get(action) != new_sheets.get(action):
                print(f"Reference fingerprint changed: {character}/{action}")
    if not args.write_reviewed_references:
        print("Tracked manifest differs. Review reference changes before using --write-reviewed-references.")
        return 1
    if not (ROOT / REVIEW_EVIDENCE).is_file():
        print(f"Canonical fingerprint update refused: missing cleanup review evidence {REVIEW_EVIDENCE}")
        return 2
    MANIFEST.write_text(json.dumps(candidate, indent=2) + "\n", encoding="utf-8")
    print(f"Recorded {count} canonical sheet fingerprints ({MANIFEST.stat().st_size} bytes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
