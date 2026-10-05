"""Compare, or explicitly update, reviewed canonical animation pixel fingerprints.

The inputs are the canonical PNG paths in the calibrated character motion specs.
The default is read-only; --write-reviewed-references records a reviewed change.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "character-motion" / "canonical_sheet_pixels.json"
ACTION_FIELDS = ("walk_animation", "idle_animation", "run_animation")
DIRECTIONS = {"east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"}


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


def build_manifest() -> dict:
    characters = {}
    for character in calibrated_characters():
        spec = json.loads((ROOT / "character-motion" / (character + ".json")).read_text(encoding="utf-8"))
        if spec["character"] != character:
            raise ValueError(f"{character}: spec character does not match filename")
        if set(spec["directions"]) != DIRECTIONS or any(direction["mirror_x"] for direction in spec["directions"].values()):
            raise ValueError(f"{character}: calibrated canonical references require eight authored directions")
        actions = {direction[field] for direction in spec["directions"].values() for field in ACTION_FIELDS}
        if len(actions) != 24 or actions != set(spec["animations"]):
            raise ValueError(f"{character}: spec animation keys do not match directional locomotion coverage")
        sheets = {}
        for action in sorted(actions):
            animation = spec["animations"][action]
            source = PurePosixPath(animation["path"])
            if source.is_absolute() or ".." in source.parts:
                raise ValueError(f"{character}/{action}: canonical source must stay inside the repository")
            if source.parts[:3] == ("assets", "sprites", "character-animations"):
                raise ValueError(f"{character}/{action}: canonical source must be a reviewed reference PNG")
            with Image.open(ROOT / source) as image:
                rgba = image.convert("RGBA")
                expected_size = (animation["frame_width"] * animation["frame_count"], animation["frame_height"])
                if rgba.size != expected_size:
                    raise ValueError(f"{character}/{action}: reference size {rgba.size} != spec size {expected_size}")
                sheets[action] = {
                    "source_path": source.as_posix(),
                    "source_filename": source.name,
                    "width": rgba.width,
                    "height": rgba.height,
                    "rgba_sha256": hashlib.sha256(rgba.tobytes()).hexdigest(),
                }
        characters[character] = sheets
    return {"version": 1, "pixel_mode": "RGBA", "hash_algorithm": "sha256", "characters": characters}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-reviewed-references", action="store_true",
                        help="explicitly update the tracked fingerprints after reviewing canonical reference changes")
    args = parser.parse_args()
    candidate = build_manifest()
    previous = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else None
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
    MANIFEST.write_text(json.dumps(candidate, indent=2) + "\n", encoding="utf-8")
    print(f"Recorded {count} canonical sheet fingerprints ({MANIFEST.stat().st_size} bytes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
