"""Build Ferret Scout's reviewed directional animation sources for runtime.

The generated source atlases intentionally use a saturated magenta matte.
This builder removes that matte, splits the authored cells, and normalizes each
direction with one shared scale and one shared foot baseline.  Source art is
never modified in place.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CHARACTER_ROOT = ROOT / "output" / "character-motion" / "ferret-scout"
SOURCE_ROOT = CHARACTER_ROOT / "source"
RUNTIME_ROOT = CHARACTER_ROOT / "runtime"

FRAME_SIZE = 512
TARGET_HEIGHT = 385
MAX_WIDTH = 460
TARGET_CENTER_X = FRAME_SIZE // 2
TARGET_BASELINE = 458
ALPHA_THRESHOLD = 16


WALK_SOURCES = {
    "walk.png": "walk-east-v1-magenta.png",
    "walk_northeast.png": "walk-northeast-v3-magenta.png",
    "walk_north.png": "walk-north-v1-magenta.png",
    "walk_southeast.png": "walk-southeast-v1-magenta.png",
    "walk_south.png": "walk-south-v2-magenta.png",
}

IDLE_OUTPUTS = (
    "idle.png",
    "idle_northeast.png",
    "idle_north.png",
    "idle_southeast.png",
    "idle_south.png",
)

IDLE_SOURCE_OVERRIDES = {
    "idle_southeast.png": "idle-southeast-v2-magenta.png",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def proportional_cells(image: Image.Image, columns: int, rows: int = 1) -> list[Image.Image]:
    cells: list[Image.Image] = []
    for row in range(rows):
        top = round(row * image.height / rows)
        bottom = round((row + 1) * image.height / rows)
        for column in range(columns):
            left = round(column * image.width / columns)
            right = round((column + 1) * image.width / columns)
            cells.append(image.crop((left, top, right, bottom)))
    return cells


def content_aware_row_cells(image: Image.Image, columns: int) -> list[Image.Image]:
    """Split a row at real blank gutters, tolerating imperfect atlas spacing."""

    transparent = remove_magenta_matte(image)
    alpha = np.asarray(transparent.getchannel("A"))
    projection = np.count_nonzero(alpha >= ALPHA_THRESHOLD, axis=0)
    nominal_width = image.width / columns
    boundaries = [0]
    for index in range(1, columns):
        expected = round(index * nominal_width)
        radius = round(nominal_width * 0.32)
        start = max(boundaries[-1] + 1, expected - radius)
        stop = min(image.width - 1, expected + radius)
        low_ink = projection[start:stop] <= 4

        runs: list[tuple[int, int]] = []
        run_start: int | None = None
        for offset, is_low in enumerate(low_ink):
            if is_low and run_start is None:
                run_start = offset
            elif not is_low and run_start is not None:
                if offset - run_start >= 2:
                    runs.append((start + run_start, start + offset))
                run_start = None
        if run_start is not None and len(low_ink) - run_start >= 2:
            runs.append((start + run_start, stop))

        if runs:
            left, right = min(
                runs,
                key=lambda run: (abs(((run[0] + run[1]) / 2) - expected), -(run[1] - run[0])),
            )
            boundary = round((left + right) / 2)
        else:
            local = projection[start:stop]
            boundary = start + int(np.argmin(local))
        boundaries.append(boundary)
    boundaries.append(image.width)
    return [
        image.crop((boundaries[index], 0, boundaries[index + 1], image.height))
        for index in range(columns)
    ]


def remove_magenta_matte(image: Image.Image) -> Image.Image:
    """Remove the saturated matte while retaining non-background artwork.

    The generated matte varies a few RGB values because of image encoding, so
    matching a single key color would leave a halo.  The predicate is narrow
    to saturated pinks and does not match the character's red compass needle.
    """

    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    red = rgba[:, :, 0].astype(np.int16)
    green = rgba[:, :, 1].astype(np.int16)
    blue = rgba[:, :, 2].astype(np.int16)
    magenta = (
        (red >= 175)
        & (blue >= 145)
        & (green <= 105)
        & ((red + blue - 2 * green) >= 245)
        & (np.abs(red - blue) <= 105)
    )
    rgba[magenta, 3] = 0
    rgba[magenta, :3] = 0
    return Image.fromarray(rgba, "RGBA")


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.where(alpha >= ALPHA_THRESHOLD)
    if len(xs) == 0:
        raise ValueError("A source cell became empty after matte removal")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def normalize_strip(cells: list[Image.Image]) -> tuple[Image.Image, dict[str, object]]:
    transparent = [remove_magenta_matte(cell) for cell in cells]
    boxes = [visible_bbox(frame) for frame in transparent]
    heights = sorted(bottom - top for _, top, _, bottom in boxes)
    median_height = heights[len(heights) // 2]
    widest = max(right - left for left, _, right, _ in boxes)
    scale = min(TARGET_HEIGHT / median_height, MAX_WIDTH / widest)

    normalized: list[Image.Image] = []
    frame_data: list[dict[str, int]] = []
    for frame, box in zip(transparent, boxes):
        crop = frame.crop(box)
        width = max(1, round(crop.width * scale))
        height = max(1, round(crop.height * scale))
        crop = crop.resize((width, height), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        left = round(TARGET_CENTER_X - width / 2)
        top = TARGET_BASELINE - height
        canvas.alpha_composite(crop, (left, top))
        normalized.append(canvas)
        frame_data.append({"width": width, "height": height, "left": left, "top": top})

    strip = Image.new("RGBA", (FRAME_SIZE * len(normalized), FRAME_SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(normalized):
        strip.alpha_composite(frame, (index * FRAME_SIZE, 0))
    return strip, {
        "frames": len(normalized),
        "scale": round(scale, 6),
        "median_source_height": median_height,
        "widest_source_frame": widest,
        "normalized_frames": frame_data,
    }


def build(output_root: Path) -> dict[str, object]:
    output_root.mkdir(parents=True, exist_ok=True)
    report: dict[str, object] = {
        "character": "ferret-scout",
        "frame_size": FRAME_SIZE,
        "target_baseline": TARGET_BASELINE,
        "outputs": {},
        "sources": {},
    }

    idle_source = SOURCE_ROOT / "directional-idle-atlas-v1-magenta.png"
    with Image.open(idle_source) as image:
        rgba = image.convert("RGBA")
        idle_cells = []
        for row in range(2):
            top = round(row * rgba.height / 2)
            bottom = round((row + 1) * rgba.height / 2)
            idle_cells.extend(content_aware_row_cells(rgba.crop((0, top, rgba.width, bottom)), columns=5))
    # proportional_cells is row-major; pair neutral and settle poses by column.
    for column, output_name in enumerate(IDLE_OUTPUTS):
        override_name = IDLE_SOURCE_OVERRIDES.get(output_name)
        if override_name:
            override_path = SOURCE_ROOT / override_name
            with Image.open(override_path) as image:
                selected_cells = content_aware_row_cells(image.convert("RGBA"), columns=2)
            report["sources"][override_name] = sha256(override_path)
        else:
            selected_cells = [idle_cells[column], idle_cells[5 + column]]
        strip, details = normalize_strip(selected_cells)
        output_path = output_root / output_name
        strip.save(output_path)
        report["outputs"][output_name] = details
    report["sources"][idle_source.name] = sha256(idle_source)

    for output_name, source_name in WALK_SOURCES.items():
        source_path = SOURCE_ROOT / source_name
        with Image.open(source_path) as image:
            cells = content_aware_row_cells(image.convert("RGBA"), columns=8)
        strip, details = normalize_strip(cells)
        output_path = output_root / output_name
        strip.save(output_path)
        report["outputs"][output_name] = details
        report["sources"][source_name] = sha256(source_path)

    report_path = output_root / "build-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=RUNTIME_ROOT,
        help="Directory for normalized runtime strips",
    )
    args = parser.parse_args()
    report = build(args.output_root.resolve())
    print(
        f"Built {len(report['outputs'])} directional strips for Ferret Scout "
        f"in {args.output_root.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
