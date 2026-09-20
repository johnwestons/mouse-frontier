"""Build a reviewed directional character source set into runtime strips.

The manifest keeps per-character source choices declarative while this shared
builder handles matte removal, content-aware splitting, scale locking, stable
core anchoring, reviewed frame replacement, baseline alignment, and
reproducibility hashes.
"""

from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
ALPHA_THRESHOLD = 16
HORIZONTAL_ANCHORS = frozenset({"bbox", "core"})
CHECKER_MIN_CHANNEL = 180
CHECKER_MAX_CHROMA = 18


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def project_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def magenta_matte_mask(rgba: np.ndarray) -> np.ndarray:
    red = rgba[:, :, 0].astype(np.int16)
    green = rgba[:, :, 1].astype(np.int16)
    blue = rgba[:, :, 2].astype(np.int16)
    return (
        (red >= 155)
        & (blue >= 105)
        & (green <= 130)
        & ((red + blue - 2 * green) >= 190)
        & (np.abs(red - blue) <= 125)
    )


def remove_magenta_matte(image: Image.Image) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    magenta = magenta_matte_mask(rgba)
    rgba[magenta, 3] = 0
    rgba[magenta, :3] = 0
    return Image.fromarray(rgba, "RGBA")


def remove_edge_connected_magenta_fringe_pixels(image: Image.Image) -> Image.Image:
    """Clear reviewed magenta matte/fringe only along a background connection.

    The tight dark-fringe match requires balanced red/blue, very little green,
    and clear chroma above black. Four-connected flooding starts at transparent
    neighbors or the outside image boundary and cannot cross a subject-colored
    outline. Enclosed colors present in this input are preserved. The builder
    applies this pass after its separately approved hard-magenta matte removal;
    this pass does not replace or broaden that existing rule. Sources are never
    mutated.
    """
    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    red, green, blue = (rgba[:, :, channel].astype(np.int16) for channel in range(3))
    dark_fringe = (
        (red >= 64) & (blue >= 64) & (green <= 96)
        & (np.minimum(red, blue) - green >= 48)
        & (np.abs(red - blue) <= 64)
    )
    visible = rgba[:, :, 3] >= ALPHA_THRESHOLD
    candidate = visible & (magenta_matte_mask(rgba) | dark_fringe)
    height, width = candidate.shape
    transparent = ~visible
    padded = np.pad(transparent, 1, constant_values=True)
    boundary = (
        padded[:-2, 1:-1] | padded[2:, 1:-1]
        | padded[1:-1, :-2] | padded[1:-1, 2:]
    )
    connected = candidate & boundary
    queue: deque[tuple[int, int]] = deque((int(y), int(x)) for y, x in np.argwhere(connected))
    while queue:
        y, x = queue.popleft()
        for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= next_y < height and 0 <= next_x < width and candidate[next_y, next_x] and not connected[next_y, next_x]:
                connected[next_y, next_x] = True
                queue.append((next_y, next_x))
    rgba[connected, :] = 0
    return Image.fromarray(rgba, "RGBA")


def remove_edge_connected_checker_matte(
    image: Image.Image,
    min_channel: int = CHECKER_MIN_CHANNEL,
    max_chroma: int = CHECKER_MAX_CHROMA,
) -> Image.Image:
    """Clear only bright neutral matte pixels connected to the image edge.

    Generated checker previews often contain slightly noisy white and light-gray
    squares rather than real transparency. Color alone is not safe because fur,
    eyes, paper, metal, and clothing can use the same values. This flood-fill
    therefore starts at the outer edge and cannot cross a non-matte outline;
    enclosed light colors and separately outlined equipment remain untouched.
    """

    if not 0 <= min_channel <= 255:
        raise ValueError("min_channel must be between 0 and 255")
    if not 0 <= max_chroma <= 255:
        raise ValueError("max_chroma must be between 0 and 255")

    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    rgb = rgba[:, :, :3].astype(np.int16)
    channel_min = rgb.min(axis=2)
    channel_max = rgb.max(axis=2)
    candidate = (
        (rgba[:, :, 3] >= ALPHA_THRESHOLD)
        & (channel_min >= min_channel)
        & ((channel_max - channel_min) <= max_chroma)
    )
    height, width = candidate.shape
    connected = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def seed(y: int, x: int) -> None:
        if candidate[y, x] and not connected[y, x]:
            connected[y, x] = True
            queue.append((y, x))

    for x in range(width):
        seed(0, x)
        seed(height - 1, x)
    for y in range(1, height - 1):
        seed(y, 0)
        seed(y, width - 1)

    while queue:
        y, x = queue.popleft()
        for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if (
                0 <= next_y < height
                and 0 <= next_x < width
                and candidate[next_y, next_x]
                and not connected[next_y, next_x]
            ):
                connected[next_y, next_x] = True
                queue.append((next_y, next_x))

    rgba[connected, :] = 0
    return Image.fromarray(rgba, "RGBA")


def content_aware_row_cells(image: Image.Image, columns: int) -> list[Image.Image]:
    """Split at real low-ink gutters instead of assuming exact source cells."""

    transparent = remove_magenta_matte(image)
    alpha = np.asarray(transparent.getchannel("A"))
    projection = np.count_nonzero(alpha >= ALPHA_THRESHOLD, axis=0)
    nominal_width = image.width / columns

    # Establish one weighted center per nominal cell, then let all foreground
    # columns settle into the nearest center. This prevents a wide outer margin
    # from being mistaken for the first inter-character gutter.
    x_values = np.arange(image.width, dtype=np.float64)
    centers: list[float] = []
    for index in range(columns):
        start = round(index * nominal_width)
        stop = round((index + 1) * nominal_width)
        weights = projection[start:stop].astype(np.float64)
        if weights.sum() > 0:
            centers.append(float(np.average(x_values[start:stop], weights=weights)))
        else:
            centers.append((index + 0.5) * nominal_width)
    for _ in range(12):
        assignments = np.argmin(np.abs(x_values[:, None] - np.asarray(centers)[None, :]), axis=1)
        updated = centers.copy()
        for index in range(columns):
            mask = assignments == index
            weights = projection[mask].astype(np.float64)
            if weights.sum() > 0:
                updated[index] = float(np.average(x_values[mask], weights=weights))
        if max(abs(left - right) for left, right in zip(centers, updated)) < 0.05:
            centers = updated
            break
        centers = updated

    boundaries = [0]
    for index in range(1, columns):
        left_center, right_center = centers[index - 1], centers[index]
        gap = max(4.0, right_center - left_center)
        expected = round((left_center + right_center) / 2)
        start = max(boundaries[-1] + 1, round(left_center + gap * 0.22))
        stop = min(image.width - 1, round(right_center - gap * 0.22))
        if stop <= start:
            boundaries.append(expected)
            continue
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


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.where(alpha >= ALPHA_THRESHOLD)
    if len(xs) == 0:
        raise ValueError("A source cell became empty after matte removal")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def keep_primary_vertical_band(image: Image.Image) -> Image.Image:
    """Discard isolated scanline debris separated vertically from the sprite."""

    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    alpha = rgba[:, :, 3]
    row_ink = np.count_nonzero(alpha >= ALPHA_THRESHOLD, axis=1)
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for row, occupied in enumerate(row_ink > 0):
        if occupied and start is None:
            start = row
        elif not occupied and start is not None:
            runs.append((start, row))
            start = None
    if start is not None:
        runs.append((start, len(row_ink)))
    if not runs:
        return image
    top, bottom = max(runs, key=lambda run: int(row_ink[run[0]:run[1]].sum()))
    rgba[:top, :, :] = 0
    rgba[bottom:, :, :] = 0
    return Image.fromarray(rgba, "RGBA")


def remove_secondary_horizontal_boundary_components(image: Image.Image) -> Image.Image:
    """Remove neighboring-panel fragments that touch a split cell's side edge.

    Content-aware splits occasionally land through an object from an adjacent
    generated panel. The intended sprite is the largest connected component;
    only smaller components that actually touch the left or right crop edge are
    removed, so detached in-frame props remain available to the strict audit.
    """

    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    mask = rgba[:, :, 3] >= ALPHA_THRESHOLD
    height, width = mask.shape
    visited = np.zeros((height, width), dtype=bool)
    components: list[tuple[list[tuple[int, int]], bool]] = []

    for start_y, start_x in np.argwhere(mask):
        y0, x0 = int(start_y), int(start_x)
        if visited[y0, x0]:
            continue
        visited[y0, x0] = True
        queue: deque[tuple[int, int]] = deque(((y0, x0),))
        pixels: list[tuple[int, int]] = []
        touches_side = False
        while queue:
            y, x = queue.popleft()
            pixels.append((y, x))
            touches_side = touches_side or x == 0 or x == width - 1
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))
        components.append((pixels, touches_side))

    if len(components) <= 1:
        return image
    primary_index = max(range(len(components)), key=lambda index: len(components[index][0]))
    for index, (pixels, touches_side) in enumerate(components):
        if index == primary_index or not touches_side:
            continue
        ys, xs = zip(*pixels)
        rgba[np.asarray(ys), np.asarray(xs), :] = 0
    return Image.fromarray(rgba, "RGBA")


def foreground_components(image: Image.Image) -> list[list[tuple[int, int]]]:
    """Return 8-connected foreground components without changing the source."""

    alpha = np.asarray(image.convert("RGBA").getchannel("A"), dtype=np.uint8)
    mask = alpha >= ALPHA_THRESHOLD
    height, width = mask.shape
    visited = np.zeros((height, width), dtype=bool)
    components: list[list[tuple[int, int]]] = []
    for start_y, start_x in np.argwhere(mask):
        y0, x0 = int(start_y), int(start_x)
        if visited[y0, x0]:
            continue
        visited[y0, x0] = True
        queue: deque[tuple[int, int]] = deque(((y0, x0),))
        pixels: list[tuple[int, int]] = []
        while queue:
            y, x = queue.popleft()
            pixels.append((y, x))
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))
        components.append(pixels)
    return components


def keep_primary_component(image: Image.Image) -> Image.Image:
    """Deprecated compatibility gate that refuses destructive component cleanup.

    A detached lantern, tool, tail tip, or other identity-bearing detail is
    indistinguishable from debris by component size alone.  Older manifests may
    still request ``keep_primary_component``; a multi-component frame now stops
    the build for review instead of silently deleting every smaller component.
    """

    components = foreground_components(image)
    if len(components) > 1:
        sizes = sorted((len(component) for component in components), reverse=True)
        size_summary = ", ".join(str(size) for size in sizes[:8])
        if len(sizes) > 8:
            size_summary += f", +{len(sizes) - 8} more"
        raise ValueError(
            "keep_primary_component is deprecated and cannot safely choose "
            f"between {len(components)} disconnected foreground components "
            f"(largest pixel counts: [{size_summary}]); re-author the source or use the "
            "boundary-spill cleanup for a reviewed crop-edge fragment"
        )
    return image


def core_horizontal_anchor_x(
    image: Image.Image,
    box: tuple[int, int, int, int] | None = None,
) -> float:
    """Find a stable upper-body x anchor while discounting thin extensions.

    The anchor is the weighted median of the dominant high-support column run
    in the middle of the upper body. Long tails, carried rods, and swinging
    limbs generally occupy far fewer rows than the torso, so they do not pull
    this anchor sideways as the full visible bounding box would.
    """

    left, top, right, bottom = box or visible_bbox(image)
    visible_height = bottom - top
    band_top = min(bottom - 1, top + round(visible_height * 0.22))
    band_bottom = max(band_top + 1, min(bottom, top + round(visible_height * 0.68)))
    alpha = np.asarray(image.convert("RGBA").getchannel("A"), dtype=np.uint8)
    support = np.count_nonzero(alpha[band_top:band_bottom, :] >= ALPHA_THRESHOLD, axis=0)
    peak = int(support.max(initial=0))
    if peak == 0:
        return (left + right) / 2

    minimum_support = max(1, int(np.ceil(peak * 0.35)))
    eligible = support >= minimum_support
    runs: list[tuple[int, int]] = []
    run_start: int | None = None
    for x, occupied in enumerate(eligible):
        if occupied and run_start is None:
            run_start = x
        elif not occupied and run_start is not None:
            runs.append((run_start, x))
            run_start = None
    if run_start is not None:
        runs.append((run_start, len(eligible)))
    if not runs:
        return (left + right) / 2

    core_left, core_right = max(
        runs,
        key=lambda run: (int(support[run[0]:run[1]].sum()), run[1] - run[0]),
    )
    weights = support[core_left:core_right]
    halfway = (int(weights.sum()) + 1) // 2
    offset = int(np.searchsorted(np.cumsum(weights), halfway, side="left"))
    return float(core_left + offset)


def horizontal_anchor_x(
    image: Image.Image,
    box: tuple[int, int, int, int],
    mode: str,
) -> float:
    if not isinstance(mode, str) or mode not in HORIZONTAL_ANCHORS:
        raise ValueError(
            f"Unknown horizontal_anchor {mode!r}; expected one of {sorted(HORIZONTAL_ANCHORS)}"
        )
    if mode == "core":
        return core_horizontal_anchor_x(image, box)
    left, _, right, _ = box
    return (left + right) / 2


def normalize_strip(
    cells: list[Image.Image],
    frame_size: int,
    target_height: int,
    max_width: int,
    center_x: int,
    baseline: int,
    frame_adjustments: dict[str, dict[str, float]] | None = None,
    drop_boundary_spill: bool = False,
    keep_only_primary_component: bool = False,
    horizontal_anchor: str = "bbox",
    remove_edge_connected_checker: bool = False,
    source_resolution_scales: list[float] | None = None,
    remove_edge_connected_magenta_fringe: bool = False,
    ground_clearance: list[int] | None = None,
) -> tuple[Image.Image, dict[str, object]]:
    if ground_clearance is not None:
        from tools.character_gait_contract import run_ground_clearance
        ground_clearance = run_ground_clearance(ground_clearance, frame_size)
        if len(cells) != 8:
            raise ValueError('Run framing requires eight frames')
    if not isinstance(horizontal_anchor, str) or horizontal_anchor not in HORIZONTAL_ANCHORS:
        raise ValueError(
            f"Unknown horizontal_anchor {horizontal_anchor!r}; "
            f"expected one of {sorted(HORIZONTAL_ANCHORS)}"
        )
    if not isinstance(remove_edge_connected_checker, bool):
        raise ValueError("remove_edge_connected_checker must be a boolean")
    if not isinstance(remove_edge_connected_magenta_fringe, bool):
        raise ValueError("remove_edge_connected_magenta_fringe must be a boolean")
    if source_resolution_scales is None:
        resolution_scales = [1.0] * len(cells)
    elif (
        not isinstance(source_resolution_scales, list)
        or len(source_resolution_scales) != len(cells)
        or any(
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(float(value))
            or float(value) <= 0
            for value in source_resolution_scales
        )
    ):
        raise ValueError(
            "source_resolution_scales must contain one positive finite number per frame"
        )
    else:
        resolution_scales = [float(value) for value in source_resolution_scales]
    magenta_removed_pixels: list[int] = []
    magenta_fringe_removed_pixels: list[int] = []
    if remove_edge_connected_magenta_fringe:
        transparent = []
        for cell in cells:
            original = np.asarray(cell.convert("RGBA"), dtype=np.uint8)
            cleaned = remove_edge_connected_magenta_fringe_pixels(remove_magenta_matte(cell))
            removed = (original[:, :, 3] >= ALPHA_THRESHOLD) & (np.asarray(cleaned.getchannel("A")) < ALPHA_THRESHOLD)
            magenta_removed_pixels.append(int(np.count_nonzero(removed)))
            magenta_fringe_removed_pixels.append(int(np.count_nonzero(removed & ~magenta_matte_mask(original))))
            transparent.append(cleaned)
    else:
        transparent = [remove_magenta_matte(cell) for cell in cells]
    checker_removed_pixels: list[int] = []
    if remove_edge_connected_checker:
        checker_cleaned: list[Image.Image] = []
        for frame in transparent:
            before_alpha = np.asarray(frame.getchannel("A"), dtype=np.uint8)
            cleaned = remove_edge_connected_checker_matte(frame)
            after_alpha = np.asarray(cleaned.getchannel("A"), dtype=np.uint8)
            checker_removed_pixels.append(int(np.count_nonzero(
                (before_alpha >= ALPHA_THRESHOLD) & (after_alpha < ALPHA_THRESHOLD)
            )))
            checker_cleaned.append(cleaned)
        transparent = checker_cleaned
    if drop_boundary_spill:
        transparent = [remove_secondary_horizontal_boundary_components(frame) for frame in transparent]
    if keep_only_primary_component:
        transparent = [keep_primary_component(frame) for frame in transparent]
    transparent = [keep_primary_vertical_band(frame) for frame in transparent]
    boxes = [visible_bbox(frame) for frame in transparent]
    source_anchors = [
        horizontal_anchor_x(frame, box, horizontal_anchor)
        for frame, box in zip(transparent, boxes)
    ]
    heights = sorted(
        (bottom - top) * resolution_scale
        for (_, top, _, bottom), resolution_scale in zip(boxes, resolution_scales)
    )
    median_height = heights[len(heights) // 2]
    widest = max(
        (right - left) * resolution_scale
        for (left, _, right, _), resolution_scale in zip(boxes, resolution_scales)
    )
    scale = min(target_height / median_height, max_width / widest)

    normalized: list[Image.Image] = []
    frame_data: list[dict[str, object]] = []
    adjustments = frame_adjustments or {}
    unknown_frames = set(adjustments) - {str(index) for index in range(1, len(cells) + 1)}
    if unknown_frames:
        raise ValueError(f"Frame adjustments contain out-of-range frames: {sorted(unknown_frames)}")

    for index, (frame, box, source_anchor, resolution_scale) in enumerate(
        zip(transparent, boxes, source_anchors, resolution_scales), 1
    ):
        crop = frame.crop(box)
        adjustment = adjustments.get(str(index), {})
        scale_x = float(adjustment.get("scale_x", 1.0))
        scale_y = float(adjustment.get("scale_y", 1.0))
        if scale_x <= 0 or scale_y <= 0:
            raise ValueError(f"Frame {index} scale adjustments must be positive")
        width = max(1, round(crop.width * scale * resolution_scale * scale_x))
        height = max(1, round(crop.height * scale * resolution_scale * scale_y))
        crop = crop.resize((width, height), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
        if horizontal_anchor == "core":
            # Nearest-neighbor resampling changes discrete support weights.
            # Measure the actual output pixels, not a scaled source estimate,
            # so the renderer and doctor's core anchor agree after rounding.
            anchor_in_crop = core_horizontal_anchor_x(crop, visible_bbox(crop))
            left = round(center_x - anchor_in_crop)
            output_anchor = left + anchor_in_crop
        else:
            left = round(center_x - width / 2)
            output_anchor = left + width / 2
        clearance = ground_clearance[index - 1] if ground_clearance else 0
        top = baseline - clearance - height
        if horizontal_anchor == "core" and (left < 0 or left + width > frame_size):
            raise ValueError(
                f"Frame {index} would clip after core anchoring "
                f"(left={left}, right={left + width}, frame_size={frame_size}); "
                "reduce max_width/target_height or review the source extension"
            )
        canvas.alpha_composite(crop, (left, top))
        normalized.append(canvas)
        frame_data.append({
            "width": width,
            "height": height,
            "left": left,
            "top": top,
            "ground_clearance": clearance,
            "scale_x": scale_x,
            "scale_y": scale_y,
            "source_resolution_scale": round(resolution_scale, 9),
            "source_anchor_x": round(source_anchor, 3),
            "output_anchor_x": round(output_anchor, 3),
        })

    strip = Image.new("RGBA", (frame_size * len(normalized), frame_size), (0, 0, 0, 0))
    for index, frame in enumerate(normalized):
        strip.alpha_composite(frame, (index * frame_size, 0))
    details: dict[str, object] = {
        "frames": len(normalized),
        "scale": round(scale, 6),
        "median_source_height": round(median_height, 3),
        "widest_source_frame": round(widest, 3),
        "horizontal_anchor": horizontal_anchor,
        "remove_edge_connected_checker": remove_edge_connected_checker,
        "remove_edge_connected_magenta_fringe": remove_edge_connected_magenta_fringe,
        "normalized_frames": frame_data,
    }
    if remove_edge_connected_magenta_fringe:
        details["magenta_matte_and_fringe_removed_pixels"] = magenta_removed_pixels
        details["edge_connected_magenta_fringe_removed_pixels"] = magenta_fringe_removed_pixels
    if remove_edge_connected_checker:
        details["edge_connected_checker_removed_pixels"] = checker_removed_pixels
    return strip, details


def split_idle_atlas(
    path: Path, columns: int, rows: int, fixed_grid: bool = False,
    row_boundaries: list[int] | None = None,
) -> list[Image.Image]:
    with Image.open(path) as image:
        rgba = image.convert("RGBA")
        if row_boundaries is not None:
            if (
                not isinstance(row_boundaries, list)
                or len(row_boundaries) != rows + 1
                or any(type(value) is not int for value in row_boundaries)
                or row_boundaries[0] != 0
                or row_boundaries[-1] != rgba.height
                or any(a >= b for a, b in zip(row_boundaries, row_boundaries[1:]))
            ):
                raise ValueError("Idle row_boundaries must be increasing integer pixel boundaries from 0 to image height, with rows + 1 entries")
            # Explicit cuts may only use real empty gutters. Inspect the approved
            # matte-cleaned alpha, but return unmodified source crops for cleanup.
            alpha = np.asarray(remove_magenta_matte(rgba).getchannel("A"))
            for cut in row_boundaries[1:-1]:
                if np.any(alpha[cut - 1:cut + 1] >= 16):
                    raise ValueError(f"Idle row_boundaries cut {cut} crosses visible source art; choose an empty gutter")
        cells: list[Image.Image] = []
        for row in range(rows):
            top = row_boundaries[row] if row_boundaries is not None else round(row * rgba.height / rows)
            bottom = row_boundaries[row + 1] if row_boundaries is not None else round((row + 1) * rgba.height / rows)
            row_image = rgba.crop((0, top, rgba.width, bottom))
            if fixed_grid:
                cells.extend([
                    row_image.crop((
                        round(column * row_image.width / columns), 0,
                        round((column + 1) * row_image.width / columns), row_image.height,
                    ))
                    for column in range(columns)
                ])
            else:
                cells.extend(content_aware_row_cells(row_image, columns))
    return cells


def split_grid_atlas(path: Path, columns: int, rows: int, fixed_grid: bool = False) -> list[Image.Image]:
    """Split a row-major source atlas while honoring each row's real gutters."""

    with Image.open(path) as image:
        rgba = image.convert("RGBA")
        cells: list[Image.Image] = []
        for row in range(rows):
            top = round(row * rgba.height / rows)
            bottom = round((row + 1) * rgba.height / rows)
            row_image = rgba.crop((0, top, rgba.width, bottom))
            if fixed_grid:
                cells.extend([
                    row_image.crop((
                        round(column * row_image.width / columns), 0,
                        round((column + 1) * row_image.width / columns), row_image.height,
                    ))
                    for column in range(columns)
                ])
            else:
                cells.extend(content_aware_row_cells(row_image, columns))
    return cells


def visible_height_for_resolution_normalization(
    image: Image.Image,
    *,
    drop_boundary_spill: bool = False,
    remove_edge_connected_checker: bool = False,
    remove_edge_connected_magenta_fringe: bool = False,
) -> int:
    """Measure visible height using the same safe cleanup as normalization."""

    prepared = remove_magenta_matte(image)
    if remove_edge_connected_magenta_fringe:
        prepared = remove_edge_connected_magenta_fringe_pixels(prepared)
    if remove_edge_connected_checker:
        prepared = remove_edge_connected_checker_matte(prepared)
    if drop_boundary_spill:
        prepared = remove_secondary_horizontal_boundary_components(prepared)
    prepared = keep_primary_vertical_band(prepared)
    _, top, _, bottom = visible_bbox(prepared)
    return bottom - top


def positive_finite_number(value: object, location: str) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(float(value))
        or float(value) <= 0
    ):
        raise ValueError(f"{location} must be a positive finite number")
    return float(value)


def reorder_walk_source_frames(
    cells: list[Image.Image], source_frame_indices: object
) -> list[Image.Image]:
    """Map selected atlas cells into the eight canonical gait phase slots.

    Indices address the row-selected cells, not the original atlas. Every cell
    must occur exactly once: resequencing may correct phase order but cannot
    manufacture movement by duplicating or omitting authored poses. Standalone
    frame overrides are applied afterwards in canonical output-slot order.
    """

    if (
        not isinstance(source_frame_indices, list)
        or len(source_frame_indices) != 8
        or any(type(index) is not int for index in source_frame_indices)
        or set(source_frame_indices) != set(range(8))
    ):
        raise ValueError("source_frame_indices must be an eight-item permutation of integers 0..7")
    if len(cells) != 8:
        raise ValueError("source_frame_indices requires exactly eight row-selected source cells")
    return [cells[index] for index in source_frame_indices]


def apply_frame_source_overrides(
    cells: list[Image.Image],
    frame_sources: object,
    source_root: Path,
    *,
    drop_boundary_spill: bool = False,
    remove_edge_connected_checker: bool = False,
    remove_edge_connected_magenta_fringe: bool = False,
) -> tuple[list[Image.Image], list[dict[str, object]]]:
    """Replace selected cells with reviewed one-frame source images.

    ``frame_sources`` is an eight-slot list aligned with gait phase order. A
    null entry keeps the atlas cell and a string retains the original unscaled
    standalone-image behavior. A structured entry adds explicit, uniform
    resolution normalization without changing anatomy:

    ``{"source": "phase.png", "resolution_normalization":
    "match_base_visible_height"}``

    Alternatively, ``resolution_normalization`` may contain reviewed
    ``source_visible_height`` and ``target_visible_height`` values. The
    returned records include every input and computed scale for reproducibility.
    """

    if not isinstance(frame_sources, list) or len(frame_sources) != len(cells):
        raise ValueError(
            f"frame_sources must be a {len(cells)}-item list containing nulls, "
            "source filenames, or structured source entries"
        )
    if not isinstance(drop_boundary_spill, bool):
        raise ValueError("drop_boundary_spill must be a boolean")
    if not isinstance(remove_edge_connected_checker, bool):
        raise ValueError("remove_edge_connected_checker must be a boolean")
    if not isinstance(remove_edge_connected_magenta_fringe, bool):
        raise ValueError("remove_edge_connected_magenta_fringe must be a boolean")
    overridden = list(cells)
    records: list[dict[str, object]] = []
    for index, source_entry in enumerate(frame_sources):
        if source_entry is None:
            continue
        if isinstance(source_entry, str):
            source_name = source_entry
            normalization_spec: object | None = None
        elif isinstance(source_entry, dict):
            unknown_keys = set(source_entry) - {"source", "resolution_normalization"}
            if unknown_keys:
                raise ValueError(
                    f"frame_sources[{index}] contains unknown fields: {sorted(unknown_keys)}"
                )
            source_name = source_entry.get("source")
            if "resolution_normalization" not in source_entry:
                raise ValueError(
                    f"frame_sources[{index}] structured entry must declare "
                    "resolution_normalization"
                )
            normalization_spec = source_entry["resolution_normalization"]
        else:
            raise ValueError(
                f"frame_sources[{index}] must be null, a source filename, "
                "or a structured source entry"
            )
        if not isinstance(source_name, str) or not source_name.strip():
            raise ValueError(f"frame_sources[{index}].source must be a non-empty filename")
        source_path = source_root / source_name
        if not source_path.is_file():
            raise ValueError(f"Frame override source does not exist: {source_path}")
        with Image.open(source_path) as image:
            if getattr(image, "n_frames", 1) != 1:
                raise ValueError(
                    f"Frame override source must contain exactly one image: {source_path}"
                )
            replacement = image.convert("RGBA").copy()

        if normalization_spec is None:
            normalization = {"mode": "legacy_none", "uniform_scale": 1.0}
        elif normalization_spec == "match_base_visible_height":
            source_height = visible_height_for_resolution_normalization(
                replacement,
                drop_boundary_spill=drop_boundary_spill,
                remove_edge_connected_checker=remove_edge_connected_checker,
                remove_edge_connected_magenta_fringe=remove_edge_connected_magenta_fringe,
            )
            target_height = visible_height_for_resolution_normalization(
                cells[index],
                drop_boundary_spill=drop_boundary_spill,
                remove_edge_connected_checker=remove_edge_connected_checker,
                remove_edge_connected_magenta_fringe=remove_edge_connected_magenta_fringe,
            )
            normalization = {
                "mode": "match_base_visible_height",
                "source_visible_height": source_height,
                "target_visible_height": target_height,
                "uniform_scale": target_height / source_height,
            }
        elif isinstance(normalization_spec, dict):
            unknown_keys = set(normalization_spec) - {
                "mode", "source_visible_height", "target_visible_height"
            }
            if unknown_keys:
                raise ValueError(
                    f"frame_sources[{index}].resolution_normalization contains "
                    f"unknown fields: {sorted(unknown_keys)}"
                )
            mode = normalization_spec.get("mode", "reviewed_visible_height")
            if mode != "reviewed_visible_height":
                raise ValueError(
                    f"frame_sources[{index}].resolution_normalization.mode must be "
                    "'reviewed_visible_height'"
                )
            source_height = positive_finite_number(
                normalization_spec.get("source_visible_height"),
                f"frame_sources[{index}].resolution_normalization.source_visible_height",
            )
            target_height = positive_finite_number(
                normalization_spec.get("target_visible_height"),
                f"frame_sources[{index}].resolution_normalization.target_visible_height",
            )
            normalization = {
                "mode": "reviewed_visible_height",
                "source_visible_height": source_height,
                "target_visible_height": target_height,
                "uniform_scale": target_height / source_height,
            }
        else:
            raise ValueError(
                f"frame_sources[{index}].resolution_normalization must be "
                "'match_base_visible_height' or an object containing reviewed heights"
            )

        overridden[index] = replacement
        records.append({
            "frame": index + 1,
            "source": source_name,
            "sha256": sha256(source_path),
            "resolution_normalization": normalization,
        })
    return overridden, records


def build(manifest_path: Path) -> dict[str, object]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("version") != 1:
        raise ValueError("Unsupported directional build manifest version")
    source_root = project_path(manifest["source_root"])
    runtime_root = project_path(manifest["runtime_root"])
    runtime_root.mkdir(parents=True, exist_ok=True)

    framing = manifest.get("framing", {})
    frame_size = int(framing.get("frame_size", 512))
    target_height = int(framing.get("target_height", 385))
    max_width = int(framing.get("max_width", 460))
    center_x = int(framing.get("center_x", frame_size // 2))
    baseline = int(framing.get("baseline", 458))
    default_horizontal_anchor = framing.get("horizontal_anchor", "bbox")
    default_remove_edge_connected_checker = framing.get(
        "remove_edge_connected_checker", False
    )
    default_remove_edge_connected_magenta_fringe = framing.get("remove_edge_connected_magenta_fringe", False)
    if (
        not isinstance(default_horizontal_anchor, str)
        or default_horizontal_anchor not in HORIZONTAL_ANCHORS
    ):
        raise ValueError(
            f"Unknown horizontal_anchor {default_horizontal_anchor!r}; "
            f"expected one of {sorted(HORIZONTAL_ANCHORS)}"
        )
    if not isinstance(default_remove_edge_connected_checker, bool):
        raise ValueError("remove_edge_connected_checker must be a boolean")
    if not isinstance(default_remove_edge_connected_magenta_fringe, bool):
        raise ValueError("remove_edge_connected_magenta_fringe must be a boolean")
    report: dict[str, object] = {
        "character": manifest["character"],
        "manifest": str(manifest_path),
        "frame_size": frame_size,
        "target_baseline": baseline,
        "default_horizontal_anchor": default_horizontal_anchor,
        "default_remove_edge_connected_checker": default_remove_edge_connected_checker,
        "default_remove_edge_connected_magenta_fringe": default_remove_edge_connected_magenta_fringe,
        "outputs": {},
        "sources": {},
    }

    idle_sets = manifest.get("idle_sets") or [manifest["idle"]]
    for idle in idle_sets:
        idle_path = source_root / idle["source"]
        idle_outputs = idle["outputs"]
        columns = int(idle.get("source_columns", len(idle_outputs)))
        selected_columns = idle.get("source_indices", list(range(len(idle_outputs))))
        if len(selected_columns) != len(idle_outputs):
            raise ValueError("Idle source_indices must match the number of outputs")
        if any(not isinstance(index, int) or index < 0 or index >= columns for index in selected_columns):
            raise ValueError("Idle source_indices contains an out-of-range column")
        rows = int(idle.get("rows", 2))
        row_indices = idle.get("row_indices", [0, 1])
        if (
            not isinstance(row_indices, list)
            or len(row_indices) != 2
            or any(not isinstance(index, int) or index < 0 or index >= rows for index in row_indices)
            or row_indices[0] == row_indices[1]
        ):
            raise ValueError("Idle row_indices must name two distinct in-range source rows")
        idle_cells = split_idle_atlas(
            idle_path, columns, rows, bool(idle.get("fixed_grid", False)),
            row_boundaries=idle.get("row_boundaries"),
        )
        output_adjustments = idle.get("output_adjustments", {})
        if not isinstance(output_adjustments, dict):
            raise ValueError("Idle output_adjustments must be an object")
        unknown_outputs = set(output_adjustments) - set(idle_outputs)
        if unknown_outputs:
            raise ValueError(f"Idle output_adjustments contains unknown outputs: {sorted(unknown_outputs)}")
        output_cleanup = idle.get("output_cleanup", {})
        if not isinstance(output_cleanup, dict):
            raise ValueError("Idle output_cleanup must be an object")
        unknown_cleanup_outputs = set(output_cleanup) - set(idle_outputs)
        if unknown_cleanup_outputs:
            raise ValueError(f"Idle output_cleanup contains unknown outputs: {sorted(unknown_cleanup_outputs)}")
        for column, output_name in zip(selected_columns, idle_outputs):
            if output_name in report["outputs"]:
                raise ValueError(f"Duplicate idle output in build manifest: {output_name}")
            strip, details = normalize_strip(
                [
                    idle_cells[row_indices[0] * columns + column],
                    idle_cells[row_indices[1] * columns + column],
                ],
                frame_size, target_height, max_width, center_x, baseline,
                output_adjustments.get(output_name, idle.get("frame_adjustments")),
                bool(idle.get("drop_boundary_spill", False)),
                bool(output_cleanup.get(output_name, {}).get("keep_primary_component", False)),
                idle.get("horizontal_anchor", default_horizontal_anchor),
                idle.get(
                    "remove_edge_connected_checker",
                    default_remove_edge_connected_checker,
                ),
                remove_edge_connected_magenta_fringe=idle.get("remove_edge_connected_magenta_fringe", default_remove_edge_connected_magenta_fringe),
            )
            if idle.get("row_boundaries") is not None:
                details["source_row_boundaries"] = idle["row_boundaries"]
                details["source_row_indices"] = row_indices
                details["source_column_index"] = column
            strip.save(runtime_root / output_name)
            report["outputs"][output_name] = details
        report["sources"][idle_path.name] = sha256(idle_path)

    from tools.character_gait_contract import locomotion_sources, run_ground_clearance
    for output_name, source_spec in locomotion_sources(manifest).items():
        if output_name in manifest.get('runs', {}):
            if not isinstance(source_spec, dict):
                raise ValueError('Run sources require an explicit ground_clearance contract')
            run_ground_clearance(source_spec.get('ground_clearance'), frame_size)
        if isinstance(source_spec, str):
            source_name = source_spec
            frame_adjustments = None
            drop_boundary_spill = False
            frame_sources = None
            horizontal_anchor = default_horizontal_anchor
            remove_checker = default_remove_edge_connected_checker
            remove_magenta_fringe = default_remove_edge_connected_magenta_fringe
        else:
            source_name = source_spec["source"]
            frame_adjustments = source_spec.get("frame_adjustments")
            drop_boundary_spill = bool(source_spec.get("drop_boundary_spill", False))
            frame_sources = source_spec.get("frame_sources")
            horizontal_anchor = source_spec.get("horizontal_anchor", default_horizontal_anchor)
            remove_checker = source_spec.get(
                "remove_edge_connected_checker",
                default_remove_edge_connected_checker,
            )
            remove_magenta_fringe = source_spec.get("remove_edge_connected_magenta_fringe", default_remove_edge_connected_magenta_fringe)
        source_columns = int(source_spec.get("source_columns", 8)) if isinstance(source_spec, dict) else 8
        source_rows = int(source_spec.get("rows", 1)) if isinstance(source_spec, dict) else 1
        row_indices = source_spec.get("row_indices", list(range(source_rows))) if isinstance(source_spec, dict) else [0]
        if (
            not isinstance(row_indices, list)
            or not row_indices
            or any(not isinstance(index, int) or index < 0 or index >= source_rows for index in row_indices)
            or len(set(row_indices)) != len(row_indices)
        ):
            raise ValueError(f"Walk atlas {source_name} has invalid row_indices")
        if source_columns * len(row_indices) != 8:
            raise ValueError(f"Walk atlas {source_name} selection must contain exactly eight source cells")
        source_path = source_root / source_name
        all_cells = split_grid_atlas(
            source_path, source_columns, source_rows,
            bool(source_spec.get("fixed_grid", False)) if isinstance(source_spec, dict) else False,
        )
        cells = [
            all_cells[row * source_columns + column]
            for row in row_indices
            for column in range(source_columns)
        ]
        source_frame_indices = (
            source_spec.get("source_frame_indices", list(range(8)))
            if isinstance(source_spec, dict)
            else list(range(8))
        )
        cells = reorder_walk_source_frames(cells, source_frame_indices)
        override_records: list[dict[str, object]] = []
        resolution_scales = [1.0] * len(cells)
        if frame_sources is not None:
            cells, override_records = apply_frame_source_overrides(
                cells,
                frame_sources,
                source_root,
                drop_boundary_spill=drop_boundary_spill,
                remove_edge_connected_checker=remove_checker,
                remove_edge_connected_magenta_fringe=remove_magenta_fringe,
            )
            for record in override_records:
                report["sources"][record["source"]] = record["sha256"]
                resolution_scales[int(record["frame"]) - 1] = float(
                    record["resolution_normalization"]["uniform_scale"]
                )
        strip, details = normalize_strip(
            cells, frame_size, target_height, max_width, center_x, baseline,
            frame_adjustments,
            drop_boundary_spill,
            bool(source_spec.get("keep_primary_component", False)) if isinstance(source_spec, dict) else False,
            horizontal_anchor,
            remove_checker,
            source_resolution_scales=resolution_scales if override_records else None,
            remove_edge_connected_magenta_fringe=remove_magenta_fringe,
            ground_clearance=(source_spec.get("ground_clearance")
                              if output_name in manifest.get("runs", {}) else None),
        )
        details["source_frame_indices"] = source_frame_indices
        if override_records:
            details["frame_source_overrides"] = override_records
        strip.save(runtime_root / output_name)
        report["outputs"][output_name] = details
        report["sources"][source_name] = sha256(source_path)

    report_path = runtime_root / "build-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path, help="Character directional build manifest")
    args = parser.parse_args()
    report = build(args.manifest.resolve())
    print(f"Built {len(report['outputs'])} directional strips for {report['character']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
