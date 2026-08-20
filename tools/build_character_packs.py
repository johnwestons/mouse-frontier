"""Build Mouse Frontier's fixed-size character sheets from 6x4 source atlases."""

from __future__ import annotations

import sys
import shutil
from collections import deque
from pathlib import Path

from PIL import Image


CHARACTERS = (
    "cowboy-mouse-no-skull",
    "red-hood-mouse",
    "raccoon-cape",
    "shield-mouse",
    "skateboard-mouse",
    "raccoon-heart",
)

ROOT = Path(__file__).resolve().parents[1]
ANIMATION_ROOT = ROOT / "assets" / "sprites" / "character-animations"

# Every exported cell is a 160x160 transparent frame. These tuples preserve the
# game's existing CharacterAnimation.actions contract and add real walk/death
# sheets instead of synthesizing either pose at draw time.
SHEETS = {
    "idle.png": ((0, 0), (1, 0)),
    "sit.png": ((2, 0), (3, 0)),
    "lay.png": ((4, 0), (5, 0)),
    "walk.png": ((0, 1), (1, 1), (2, 1)),
    "death.png": ((3, 1), (4, 1), (5, 1)),
    "melee.png": ((0, 2), (1, 2), (2, 2)),
    "ranged.png": ((3, 2), (4, 2), (5, 2)),
    "use.png": ((0, 3), (1, 3), (2, 3)),
    "hit.png": ((3, 3), (4, 3), (5, 3)),
}

BASE_TARGETS = {
    "cowboy-mouse-no-skull": ("MainCharacters", "NPCS"),
    "red-hood-mouse": ("Mobs",),
    "raccoon-cape": ("Mobs",),
    "shield-mouse": ("Mobs",),
    "skateboard-mouse": ("NPCS",),
    "raccoon-heart": ("MainCharacters", "NPCS"),
}


def crop_cell(atlas: Image.Image, column: int, row: int) -> Image.Image:
    cell_width = atlas.width // 6
    cell_height = atlas.height // 4
    cell = atlas.crop(
        (column * cell_width, row * cell_height,
         (column + 1) * cell_width, (row + 1) * cell_height)
    )
    # Generators occasionally let a few pixels from the neighboring pose cross
    # a mathematical cell edge. Clearing only the cell perimeter removes those
    # crumbs without touching the deliberately padded character silhouette.
    pixels = cell.load()
    inset = 6
    for y in range(cell.height):
        for x in range(cell.width):
            if x < inset or y < inset or x >= cell.width - inset or y >= cell.height - inset:
                pixels[x, y] = (0, 0, 0, 0)
    alpha = cell.getchannel("A")
    # Retain the largest connected opaque silhouette. This removes tiny pieces
    # of a neighboring action pose that can drift over a nominal grid edge.
    mask = alpha.point(lambda value: 255 if value > 18 else 0)
    width, height = mask.size
    source = mask.load()
    visited = bytearray(width * height)
    largest: list[tuple[int, int]] = []
    for sy in range(height):
        for sx in range(width):
            index = sy * width + sx
            if visited[index] or not source[sx, sy]:
                continue
            component: list[tuple[int, int]] = []
            queue = deque(((sx, sy),))
            visited[index] = 1
            while queue:
                x, y = queue.popleft()
                component.append((x, y))
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        ni = ny * width + nx
                        if not visited[ni] and source[nx, ny]:
                            visited[ni] = 1
                            queue.append((nx, ny))
            if len(component) > len(largest):
                largest = component
    keep = Image.new("L", cell.size)
    keep_pixels = keep.load()
    for x, y in largest:
        keep_pixels[x, y] = alpha.getpixel((x, y))
    cell.putalpha(keep)
    bounds = keep.getbbox()
    if not bounds:
        raise ValueError(f"empty source cell {column},{row}")
    subject = cell.crop(bounds)
    scale = min(144 / subject.width, 144 / subject.height)
    size = (max(1, round(subject.width * scale)), max(1, round(subject.height * scale)))
    subject = subject.resize(size, Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (160, 160))
    # Upright characters share a baseline; horizontal poses remain centered.
    x = (160 - subject.width) // 2
    y = 152 - subject.height if subject.height >= subject.width else (160 - subject.height) // 2
    frame.alpha_composite(subject, (x, max(4, y)))
    return frame


def build_character(name: str) -> None:
    directory = ANIMATION_ROOT / name
    source = directory / "complete-transparent-source.png"
    atlas = Image.open(source).convert("RGBA")
    if atlas.width % 6 or atlas.height % 4:
        raise ValueError(f"{source} is not a clean 6x4 atlas")

    cells = {(column, row): crop_cell(atlas, column, row)
             for row in range(4) for column in range(6)}
    for filename, coordinates in SHEETS.items():
        sheet = Image.new("RGBA", (160 * len(coordinates), 160))
        for index, coordinate in enumerate(coordinates):
            sheet.alpha_composite(cells[coordinate], (index * 160, 0))
        sheet.save(directory / filename, optimize=True)

    # The neutral first frame is also the base-world sprite.
    base = directory / "base.png"
    cells[(0, 0)].resize((1254, 1254), Image.Resampling.NEAREST).save(base, optimize=True)

    # Install the same rebuilt identity anywhere the runtime can select it.
    for group in BASE_TARGETS[name]:
        target_root = ROOT / "assets" / "sprites" / group
        target_root.mkdir(parents=True, exist_ok=True)
        shutil.copy2(base, target_root / f"{name}.png")

    if "Mobs" in BASE_TARGETS[name]:
        legacy = ROOT / "assets" / "sprites" / "Mobs" / "animations"
        legacy.mkdir(parents=True, exist_ok=True)
        legacy_frames = {
            "idle-2": (1, 0), "walk": (1, 1), "death": (5, 1),
            "attack": (1, 2), "ranged": (4, 2), "hit": (4, 3),
        }
        for suffix, coordinate in legacy_frames.items():
            cells[coordinate].save(legacy / f"{name}-{suffix}.png", optimize=True)
    else:
        for group in BASE_TARGETS[name]:
            legacy = ROOT / "assets" / "sprites" / group / "animations"
            legacy.mkdir(parents=True, exist_ok=True)
            cells[(1, 1)].save(legacy / f"{name}-walk.png", optimize=True)
            cells[(1, 3)].save(legacy / f"{name}-action.png", optimize=True)

    # Cowboy was temporarily a mob. Removing those runtime copies is part of
    # restoring him as a selectable hero/NPC; the canonical source remains here.
    if name == "cowboy-mouse-no-skull":
        old_base = ROOT / "assets" / "sprites" / "Mobs" / f"{name}.png"
        if old_base.exists():
            old_base.unlink()
        old_animations = ROOT / "assets" / "sprites" / "Mobs" / "animations"
        for old in old_animations.glob(f"{name}-*.png"):
            old.unlink()


def main() -> int:
    selected = tuple(sys.argv[1:]) or CHARACTERS
    unknown = set(selected) - set(CHARACTERS)
    if unknown:
        raise ValueError(f"unknown character(s): {', '.join(sorted(unknown))}")
    for name in selected:
        build_character(name)
        print(f"built {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
