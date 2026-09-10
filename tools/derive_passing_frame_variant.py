"""Derive an opposite passing-frame depth treatment without redrawing art.

This tool deliberately does not move, add, or remove pixels.  It swaps the
near/far lighting grade only inside two explicit, disjoint selectors, leaving
the alpha channel and every pixel outside those selectors byte-identical.

Selectors may be supplied as same-size binary mask PNGs, explicit rectangles
or polygons, or a mask restricted by regions.  Coordinates are source-image
pixels. Rectangles use half-open bounds: ``left,top,right,bottom``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
from PIL import Image, ImageDraw


DEFAULT_DEPTH_RATIO = 0.92
DEFAULT_PROTECTED_RGB = ((255, 0, 255),)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _array_sha256(array: np.ndarray) -> str:
    return hashlib.sha256(np.ascontiguousarray(array).tobytes()).hexdigest()


def parse_rgb(value: str) -> tuple[int, int, int]:
    normalized = value.strip().removeprefix("#")
    if len(normalized) != 6:
        raise argparse.ArgumentTypeError("RGB colors must contain exactly six hex digits")
    try:
        return tuple(int(normalized[offset : offset + 2], 16) for offset in (0, 2, 4))
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"Invalid RGB color {value!r}") from error


def parse_rectangle(value: str) -> tuple[int, int, int, int]:
    try:
        parts = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "Regions must be left,top,right,bottom integer coordinates"
        ) from error
    if len(parts) != 4:
        raise argparse.ArgumentTypeError(
            "Regions must be left,top,right,bottom integer coordinates"
        )
    return parts


def parse_polygon(value: str) -> tuple[tuple[int, int], ...]:
    points: list[tuple[int, int]] = []
    try:
        for point in value.split(";"):
            x_text, y_text = point.split(",")
            points.append((int(x_text.strip()), int(y_text.strip())))
    except (ValueError, TypeError) as error:
        raise argparse.ArgumentTypeError(
            "Polygons must use x,y;x,y;x,y integer coordinates"
        ) from error
    if len(points) < 3:
        raise argparse.ArgumentTypeError("A polygon requires at least three points")
    return tuple(points)


def _validate_rectangle(
    rectangle: tuple[int, int, int, int], width: int, height: int
) -> None:
    left, top, right, bottom = rectangle
    if not (0 <= left < right <= width and 0 <= top < bottom <= height):
        raise ValueError(
            f"Region {rectangle!r} must be a non-empty half-open rectangle inside "
            f"the {width}x{height} source image"
        )


def _validate_polygon(
    polygon: Sequence[tuple[int, int]], width: int, height: int
) -> None:
    if len(polygon) < 3:
        raise ValueError("A polygon requires at least three points")
    if any(not (0 <= x < width and 0 <= y < height) for x, y in polygon):
        raise ValueError(f"Polygon points must stay inside the {width}x{height} source image")


def region_mask(
    size: tuple[int, int],
    rectangles: Iterable[tuple[int, int, int, int]] = (),
    polygons: Iterable[Sequence[tuple[int, int]]] = (),
) -> np.ndarray:
    """Rasterize explicit source-pixel regions into a boolean selector."""

    width, height = size
    rectangles = tuple(rectangles)
    polygons = tuple(polygons)
    if not rectangles and not polygons:
        raise ValueError("At least one rectangle or polygon is required")

    mask = Image.new("1", size, 0)
    draw = ImageDraw.Draw(mask)
    for rectangle in rectangles:
        _validate_rectangle(rectangle, width, height)
        left, top, right, bottom = rectangle
        draw.rectangle((left, top, right - 1, bottom - 1), fill=1)
    for polygon in polygons:
        _validate_polygon(polygon, width, height)
        draw.polygon(tuple(polygon), fill=1)
    return np.asarray(mask, dtype=bool)


def load_binary_mask(
    path: Path,
    size: tuple[int, int],
    threshold: int = 128,
    channel: str = "auto",
) -> np.ndarray:
    """Load a same-size mask using alpha or grayscale luminance."""

    if not 0 <= threshold <= 255:
        raise ValueError("Mask threshold must be between 0 and 255")
    if channel not in {"auto", "alpha", "luminance"}:
        raise ValueError("Mask channel must be 'auto', 'alpha', or 'luminance'")

    with Image.open(path) as source:
        if source.size != size:
            raise ValueError(
                f"Mask {path} is {source.width}x{source.height}; expected {size[0]}x{size[1]}"
            )
        rgba = np.asarray(source.convert("RGBA"), dtype=np.uint8)

    alpha = rgba[:, :, 3]
    resolved_channel = channel
    if channel == "auto":
        resolved_channel = "alpha" if np.any(alpha != 255) else "luminance"
    if resolved_channel == "alpha":
        plane = alpha
    else:
        rgb = rgba[:, :, :3].astype(np.uint32)
        plane = ((299 * rgb[:, :, 0] + 587 * rgb[:, :, 1] + 114 * rgb[:, :, 2] + 500) // 1000)
    return plane >= threshold


def build_selector(
    size: tuple[int, int],
    mask_path: Path | None = None,
    rectangles: Iterable[tuple[int, int, int, int]] = (),
    polygons: Iterable[Sequence[tuple[int, int]]] = (),
    threshold: int = 128,
    mask_channel: str = "auto",
) -> np.ndarray:
    """Build a selector, intersecting a mask with regions when both exist."""

    rectangles = tuple(rectangles)
    polygons = tuple(polygons)
    file_mask = (
        load_binary_mask(mask_path, size, threshold, mask_channel)
        if mask_path is not None
        else None
    )
    spatial_mask = (
        region_mask(size, rectangles, polygons)
        if rectangles or polygons
        else None
    )
    if file_mask is None and spatial_mask is None:
        raise ValueError("Each leg requires a mask PNG, a region, or a polygon")
    if file_mask is not None and spatial_mask is not None:
        return file_mask & spatial_mask
    return file_mask if file_mask is not None else spatial_mask  # type: ignore[return-value]


def _selector_bounds(mask: np.ndarray) -> list[int] | None:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]


def _protected_mask(
    rgba: np.ndarray,
    protected_rgb: Sequence[tuple[int, int, int]],
    tolerance: int,
) -> np.ndarray:
    if not 0 <= tolerance <= 255:
        raise ValueError("Protected-color tolerance must be between 0 and 255")
    protected = np.zeros(rgba.shape[:2], dtype=bool)
    rgb = rgba[:, :, :3].astype(np.int16)
    for color in protected_rgb:
        if len(color) != 3 or any(not 0 <= channel <= 255 for channel in color):
            raise ValueError(f"Invalid protected RGB color {color!r}")
        reference = np.asarray(color, dtype=np.int16)
        protected |= np.max(np.abs(rgb - reference), axis=2) <= tolerance
    return protected


def _apply_factor(rgb: np.ndarray, selection: np.ndarray, factor: float) -> tuple[int, int]:
    original = rgb[selection].copy()
    scaled = original.astype(np.float64) * factor
    clipped_channels = int(np.count_nonzero((scaled < 0.0) | (scaled > 255.0)))
    replacement = np.clip(np.floor(scaled + 0.5), 0, 255).astype(np.uint8)
    rgb[selection] = replacement
    changed_pixels = int(np.count_nonzero(np.any(original != replacement, axis=1)))
    return changed_pixels, clipped_channels


def derive_passing_frame_variant(
    image: Image.Image,
    near_mask: np.ndarray,
    far_mask: np.ndarray,
    depth_ratio: float = DEFAULT_DEPTH_RATIO,
    protected_rgb: Sequence[tuple[int, int, int]] = DEFAULT_PROTECTED_RGB,
    protected_tolerance: int = 0,
) -> tuple[Image.Image, dict[str, object]]:
    """Swap near/far RGB grades while keeping geometry and alpha immutable.

    ``near_mask`` identifies the currently foreground leg and is multiplied by
    ``depth_ratio``. ``far_mask`` identifies the currently rear leg and is
    multiplied by its reciprocal. This produces the complementary depth read
    without inventing anatomy or touching any unselected identity pixels.
    """

    if (
        isinstance(depth_ratio, bool)
        or not isinstance(depth_ratio, (int, float))
        or not math.isfinite(float(depth_ratio))
        or not 0.75 <= float(depth_ratio) < 1.0
    ):
        raise ValueError("depth_ratio must be finite and in the conservative range [0.75, 1.0)")

    source = np.asarray(image.convert("RGBA"), dtype=np.uint8)
    expected_shape = source.shape[:2]
    near = np.asarray(near_mask, dtype=bool)
    far = np.asarray(far_mask, dtype=bool)
    if near.shape != expected_shape or far.shape != expected_shape:
        raise ValueError(
            f"Leg selectors must have shape {expected_shape}; got {near.shape} and {far.shape}"
        )
    overlap = near & far
    if np.any(overlap):
        raise ValueError(f"Near/far selectors overlap at {int(np.count_nonzero(overlap))} pixels")
    if not np.any(near) or not np.any(far):
        raise ValueError("Near and far selectors must both contain at least one pixel")

    protected = _protected_mask(source, protected_rgb, protected_tolerance)
    visible = source[:, :, 3] > 0
    active_near = near & visible & ~protected
    active_far = far & visible & ~protected
    if not np.any(active_near) or not np.any(active_far):
        raise ValueError(
            "Near and far selectors must both contain visible, non-protected source pixels"
        )

    output = source.copy()
    near_changed, near_clipped = _apply_factor(
        output[:, :, :3], active_near, float(depth_ratio)
    )
    far_changed, far_clipped = _apply_factor(
        output[:, :, :3], active_far, 1.0 / float(depth_ratio)
    )
    if near_changed == 0 or far_changed == 0:
        raise ValueError("Both leg selectors must change at least one RGB pixel")

    union = near | far
    alpha_preserved = bool(np.array_equal(source[:, :, 3], output[:, :, 3]))
    outside_preserved = bool(np.array_equal(source[~union], output[~union]))
    silhouette_preserved = bool(
        np.array_equal(source[:, :, 3] > 0, output[:, :, 3] > 0)
    )
    if not alpha_preserved or not silhouette_preserved or not outside_preserved:
        raise AssertionError("Passing-frame derivation violated an immutable pixel invariant")

    report: dict[str, object] = {
        "schema_version": 1,
        "operation": "swap_near_far_leg_depth",
        "image_size": [image.width, image.height],
        "depth_ratio": float(depth_ratio),
        "alpha_preserved": alpha_preserved,
        "silhouette_preserved": silhouette_preserved,
        "outside_selectors_preserved": outside_preserved,
        "source_alpha_sha256": _array_sha256(source[:, :, 3]),
        "output_alpha_sha256": _array_sha256(output[:, :, 3]),
        "source_rgba_sha256": _array_sha256(source),
        "output_rgba_sha256": _array_sha256(output),
        "protected_rgb": ["#" + "".join(f"{channel:02X}" for channel in color) for color in protected_rgb],
        "protected_tolerance": protected_tolerance,
        "near_to_far": {
            "factor": float(depth_ratio),
            "selector_pixels": int(np.count_nonzero(near)),
            "active_pixels": int(np.count_nonzero(active_near)),
            "changed_pixels": near_changed,
            "clipped_channels": near_clipped,
            "bounds": _selector_bounds(near),
        },
        "far_to_near": {
            "factor": 1.0 / float(depth_ratio),
            "selector_pixels": int(np.count_nonzero(far)),
            "active_pixels": int(np.count_nonzero(active_far)),
            "changed_pixels": far_changed,
            "clipped_channels": far_clipped,
            "bounds": _selector_bounds(far),
        },
    }
    return Image.fromarray(output, "RGBA"), report


def _write_json_atomic(path: Path, data: dict[str, object]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def _save_png_atomic(path: Path, image: Image.Image) -> None:
    temporary = path.with_name(path.name + ".tmp")
    image.save(temporary, format="PNG")
    os.replace(temporary, path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Reviewed single-frame PNG")
    parser.add_argument("output", type=Path, help="New complementary-frame PNG")
    parser.add_argument("--near-mask", type=Path, help="Binary mask for the currently near leg")
    parser.add_argument("--far-mask", type=Path, help="Binary mask for the currently far leg")
    parser.add_argument("--near-region", action="append", default=[], type=parse_rectangle)
    parser.add_argument("--far-region", action="append", default=[], type=parse_rectangle)
    parser.add_argument("--near-polygon", action="append", default=[], type=parse_polygon)
    parser.add_argument("--far-polygon", action="append", default=[], type=parse_polygon)
    parser.add_argument("--mask-threshold", type=int, default=128)
    parser.add_argument(
        "--mask-channel", choices=("auto", "alpha", "luminance"), default="auto"
    )
    parser.add_argument("--depth-ratio", type=float, default=DEFAULT_DEPTH_RATIO)
    parser.add_argument(
        "--protect-rgb",
        action="append",
        type=parse_rgb,
        default=list(DEFAULT_PROTECTED_RGB),
        help="RGB value left untouched even inside a selector (repeatable; default #FF00FF)",
    )
    parser.add_argument("--protect-tolerance", type=int, default=0)
    parser.add_argument("--report", type=Path, help="Audit JSON path (default OUTPUT.audit.json)")
    parser.add_argument("--overwrite", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    input_path = args.input.resolve()
    output_path = args.output.resolve()
    report_path = (
        args.report.resolve()
        if args.report is not None
        else output_path.with_suffix(".audit.json")
    )
    if input_path == output_path:
        parser.error("Output must be a new path; source art is immutable")
    if not input_path.is_file():
        parser.error(f"Input does not exist: {input_path}")
    for path, label in ((args.near_mask, "near mask"), (args.far_mask, "far mask")):
        if path is not None and not path.is_file():
            parser.error(f"{label.capitalize()} does not exist: {path}")
    protected_paths = {input_path}
    protected_paths.update(
        path.resolve() for path in (args.near_mask, args.far_mask) if path is not None
    )
    if output_path in protected_paths:
        parser.error("Output must not overwrite the input or either selector mask")
    if report_path == output_path or report_path in protected_paths:
        parser.error("Audit report must use a path separate from all PNG inputs and output")
    existing = [path for path in (output_path, report_path) if path.exists()]
    if existing and not args.overwrite:
        parser.error("Refusing to overwrite existing output: " + ", ".join(map(str, existing)))

    with Image.open(input_path) as image_source:
        image = image_source.convert("RGBA")
    near_mask = build_selector(
        image.size,
        args.near_mask.resolve() if args.near_mask is not None else None,
        args.near_region,
        args.near_polygon,
        args.mask_threshold,
        args.mask_channel,
    )
    far_mask = build_selector(
        image.size,
        args.far_mask.resolve() if args.far_mask is not None else None,
        args.far_region,
        args.far_polygon,
        args.mask_threshold,
        args.mask_channel,
    )
    result, report = derive_passing_frame_variant(
        image,
        near_mask,
        far_mask,
        args.depth_ratio,
        args.protect_rgb,
        args.protect_tolerance,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    _save_png_atomic(output_path, result)
    with Image.open(output_path) as reopened:
        saved = np.asarray(reopened.convert("RGBA"), dtype=np.uint8)
    expected = np.asarray(result, dtype=np.uint8)
    if not np.array_equal(saved, expected):
        output_path.unlink(missing_ok=True)
        raise RuntimeError("PNG round-trip changed derived frame pixels")

    report.update(
        {
            "input": str(input_path),
            "output": str(output_path),
            "input_file_sha256": sha256(input_path),
            "output_file_sha256": sha256(output_path),
            "near_mask": str(args.near_mask.resolve()) if args.near_mask else None,
            "far_mask": str(args.far_mask.resolve()) if args.far_mask else None,
            "near_mask_sha256": sha256(args.near_mask.resolve()) if args.near_mask else None,
            "far_mask_sha256": sha256(args.far_mask.resolve()) if args.far_mask else None,
            "near_regions": [list(region) for region in args.near_region],
            "far_regions": [list(region) for region in args.far_region],
            "near_polygons": [[list(point) for point in polygon] for polygon in args.near_polygon],
            "far_polygons": [[list(point) for point in polygon] for polygon in args.far_polygon],
        }
    )
    _write_json_atomic(report_path, report)
    print(f"Derived complementary passing frame: {output_path}")
    print(f"Audit report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
