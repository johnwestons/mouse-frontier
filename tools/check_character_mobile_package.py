"""Verify one directional character set inside the current mobile .love package."""

from __future__ import annotations

import argparse
import io
import json
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DIRECTIONS = ("north", "northeast", "northwest", "south", "southeast", "southwest", "west")
ACTIONS = ("idle", *(f"idle_{direction}" for direction in DIRECTIONS),
           "walk", *(f"walk_{direction}" for direction in DIRECTIONS))


def verify(character: str) -> list[str]:
    config = json.loads((ROOT / "mobile" / "config.json").read_text(encoding="utf-8"))
    frame_size = int(config["characterAnimationFrameSize"])
    package = ROOT / "output" / "mobile" / f"mouse-frontier-{config['versionName']}.love"
    failures: list[str] = []
    with zipfile.ZipFile(package) as archive:
        entries = set(archive.namelist())
        for action in ACTIONS:
            relative = f"assets/sprites/character-animations/{character}/{action}.png"
            if relative not in entries:
                failures.append(f"missing {relative}")
                continue
            with Image.open(io.BytesIO(archive.read(relative))) as image:
                frames = 2 if action.startswith("idle") else 8
                expected = (frames * frame_size, frame_size)
                if image.size != expected:
                    failures.append(f"{relative}: expected {expected}, found {image.size}")
    print(f"Verified {len(ACTIONS)} packaged locomotion strips for {character} at {frame_size}px cells")
    print(f"Package: {package}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("character")
    args = parser.parse_args()
    failures = verify(args.character)
    for failure in failures:
        print(f"FAIL {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
