"""Crop generated 2x2 title snapshot sheets into four-frame strips."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def crop_sheet(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    width, height = image.size
    if width < 2 or height < 2:
        raise ValueError(f"snapshot source is too small: {image.size}")
    cell_width, cell_height = width // 2, height // 2
    frames = [
        image.crop((0, 0, cell_width, cell_height)),
        image.crop((cell_width, 0, width, cell_height)),
        image.crop((0, cell_height, cell_width, height)),
        image.crop((cell_width, cell_height, width, height)),
    ]
    strip = Image.new("RGBA", (cell_width * 4, cell_height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (index * cell_width, 0))
    destination.parent.mkdir(parents=True, exist_ok=True)
    strip.save(destination)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    crop_sheet(args.source, args.destination)
    print(f"TITLE_SNAPSHOT_SPRITE={args.destination}")


if __name__ == "__main__":
    main()
