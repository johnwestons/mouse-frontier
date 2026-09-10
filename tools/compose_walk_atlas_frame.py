"""Replace one generated walk-atlas cell with a separately reviewed pose.

This is a deterministic source-composition step. It removes the approved
magenta matte, keeps the replacement at the matched phase's source scale,
and writes a fresh non-destructive 4x2 atlas for the normal runtime builder.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

from build_directional_character_assets import (
    keep_primary_vertical_band,
    remove_magenta_matte,
    remove_secondary_horizontal_boundary_components,
    split_grid_atlas,
    visible_bbox,
)


def clean_crop(image: Image.Image) -> Image.Image:
    cleaned = remove_magenta_matte(image)
    cleaned = remove_secondary_horizontal_boundary_components(cleaned)
    cleaned = keep_primary_vertical_band(cleaned)
    return cleaned.crop(visible_bbox(cleaned))


def resize_to_height(image: Image.Image, height: int) -> Image.Image:
    width = max(1, round(image.width * height / image.height))
    return image.resize((width, height), Image.Resampling.NEAREST)


def compose(
    base_path: Path,
    replacement_path: Path,
    output_path: Path,
    replace_index: int,
    match_index: int,
    columns: int,
    rows: int,
    cell_size: int,
    replacement_columns: int,
    replacement_rows: int,
    replacement_index: int,
) -> None:
    cells = split_grid_atlas(base_path, columns, rows)
    if len(cells) != columns * rows:
        raise ValueError("Base atlas did not resolve to the requested cell count")
    if not 1 <= replace_index <= len(cells) or not 1 <= match_index <= len(cells):
        raise ValueError("Cell indices are 1-based and must resolve inside the atlas")

    crops = [clean_crop(cell) for cell in cells]
    replacement_cells = split_grid_atlas(
        replacement_path, replacement_columns, replacement_rows
    )
    if not 1 <= replacement_index <= len(replacement_cells):
        raise ValueError("Replacement index is 1-based and must resolve inside its atlas")
    replacement_crop = clean_crop(replacement_cells[replacement_index - 1])
    replacement_crop = resize_to_height(
        replacement_crop, crops[match_index - 1].height
    )
    crops[replace_index - 1] = replacement_crop

    safe_extent = cell_size - 32
    widest = max(crop.width for crop in crops)
    tallest = max(crop.height for crop in crops)
    common_scale = min(1.0, safe_extent / widest, safe_extent / tallest)
    if common_scale < 1.0:
        crops = [
            crop.resize(
                (
                    max(1, round(crop.width * common_scale)),
                    max(1, round(crop.height * common_scale)),
                ),
                Image.Resampling.NEAREST,
            )
            for crop in crops
        ]

    atlas = Image.new(
        "RGBA",
        (columns * cell_size, rows * cell_size),
        (255, 0, 168, 255),
    )
    baseline = cell_size - 24
    for index, crop in enumerate(crops):
        column = index % columns
        row = index // columns
        left = column * cell_size + round((cell_size - crop.width) / 2)
        top = row * cell_size + baseline - crop.height
        atlas.alpha_composite(crop, (left, top))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output_path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", type=Path)
    parser.add_argument("replacement", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--replace-index", type=int, default=8)
    parser.add_argument("--match-index", type=int, default=4)
    parser.add_argument("--columns", type=int, default=4)
    parser.add_argument("--rows", type=int, default=2)
    parser.add_argument("--cell-size", type=int, default=512)
    parser.add_argument("--replacement-columns", type=int, default=1)
    parser.add_argument("--replacement-rows", type=int, default=1)
    parser.add_argument("--replacement-index", type=int, default=1)
    args = parser.parse_args()
    compose(
        args.base.resolve(),
        args.replacement.resolve(),
        args.output.resolve(),
        args.replace_index,
        args.match_index,
        args.columns,
        args.rows,
        args.cell_size,
        args.replacement_columns,
        args.replacement_rows,
        args.replacement_index,
    )
    print(f"Composed reviewed atlas: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
