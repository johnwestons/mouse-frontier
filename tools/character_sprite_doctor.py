"""Audit, repair, and import Mouse Frontier character animation sprites.

The tool is intentionally conservative about authored content.  It can repair
geometry (crop, canvas, scale, centering, and baseline) automatically, and it
can recreate a missing sheet when a same-character source strip or 6x4 master
atlas is available.  It reports semantic artwork that cannot be recovered
instead of silently substituting an unrelated pose.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import shutil
import tempfile
from collections import Counter, deque
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Iterable, Mapping, Sequence

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ANIMATION_ROOT = ROOT / "assets" / "sprites" / "character-animations"
DEFAULT_OUTPUT_ROOT = ROOT / "output" / "sprite-doctor"
DEFAULT_WEAPON_ANCHOR_OVERRIDES = ROOT / "tools" / "weapon_attachment_overrides.json"

FRAME_SIZE = 512
TARGET_EXTENT = 385
TARGET_BASELINE = 458
TARGET_CENTER_X = FRAME_SIZE / 2
ALPHA_THRESHOLD = 16
HALO_PADDING = 2


@dataclass(frozen=True)
class ActionSpec:
    frames: int
    requirement: str = "required"  # required, recommended, or optional


# Walk is six frames for modern sets (identified by unconscious.png) and three
# for legacy sets.  expected_frame_count() applies that runtime distinction.
ACTION_SPECS: dict[str, ActionSpec] = {
    "idle": ActionSpec(2),
    "walk": ActionSpec(6),
    "sit": ActionSpec(2),
    "lay": ActionSpec(2),
    "melee": ActionSpec(3),
    "ranged": ActionSpec(3),
    "use": ActionSpec(3),
    "hit": ActionSpec(3),
    "unconscious": ActionSpec(2, "recommended"),
    "death": ActionSpec(3, "recommended"),
}

# Established 6x4 complete-atlas layout.  A three-frame walk is expanded to
# the modern six-frame loop only when the character also has unconscious art.
COMPLETE_ATLAS_LAYOUT: dict[str, tuple[tuple[int, int], ...]] = {
    "idle": ((0, 0), (1, 0)),
    "sit": ((2, 0), (3, 0)),
    "lay": ((4, 0), (5, 0)),
    "walk": ((0, 1), (1, 1), (2, 1)),
    "death": ((3, 1), (4, 1), (5, 1)),
    "melee": ((0, 2), (1, 2), (2, 2)),
    "ranged": ((3, 2), (4, 2), (5, 2)),
    "use": ((0, 3), (1, 3), (2, 3)),
    "hit": ((3, 3), (4, 3), (5, 3)),
}

GEOMETRY_CODES = {
    "image_mode",
    "sheet_size",
    "frame_count_mismatch",
    "unreadable_sheet",
    "unsplittable_sheet",
    "empty_frame",
    "clipped_frame",
    "scale_mismatch",
    "center_mismatch",
    "baseline_mismatch",
    "alpha_halo",
}

REFERENCE_GROUPS = ("MainCharacters", "NPCS", "Mobs", "characters")


@dataclass
class FrameMetrics:
    frame: int
    width: int
    height: int
    empty: bool
    bbox: tuple[int, int, int, int] | None = None
    raw_bbox: tuple[int, int, int, int] | None = None
    extent: int | None = None
    center_x: float | None = None
    bottom: int | None = None
    edge_contact: bool = False
    halo_spread: int = 0
    detached_fragment_pixels: int = 0
    detached_fragment_boxes: list[tuple[int, int, int, int]] = field(default_factory=list)


@dataclass(frozen=True)
class HandAnchor:
    frame: int
    x: float
    y: float
    side: int
    confidence: float

    def to_dict(self) -> dict[str, object]:
        return {
            "frame": self.frame,
            "x": round(self.x, 4),
            "y": round(self.y, 4),
            "side": self.side,
            "confidence": round(self.confidence, 3),
        }


@dataclass
class Issue:
    severity: str
    code: str
    character: str
    action: str | None
    message: str
    frame: int | None = None
    repairable: bool = False
    confidence: str | None = None
    details: dict[str, object] = field(default_factory=dict)

    def to_dict(self) -> dict[str, object]:
        value = asdict(self)
        return {key: item for key, item in value.items() if item not in (None, {}, [])}


@dataclass
class SheetInspection:
    character: str
    action: str
    expected_count: int
    actual_count: int | None
    image: Image.Image | None
    frames: list[Image.Image]
    metrics: list[FrameMetrics]
    issues: list[Issue]
    path: Path


@dataclass
class AuditResult:
    characters: list[str]
    issues: list[Issue]
    inspections: dict[tuple[str, str], SheetInspection]

    @property
    def counts(self) -> Counter[str]:
        return Counter(issue.severity for issue in self.issues)

    def to_dict(self) -> dict[str, object]:
        counts = self.counts
        return {
            "characters": self.characters,
            "summary": {
                "errors": counts["error"],
                "warnings": counts["warning"],
                "info": counts["info"],
            },
            "issues": [issue.to_dict() for issue in self.issues],
        }


@dataclass
class Repair:
    character: str
    action: str
    image: Image.Image
    reason: str
    confidence: str
    source: str

    def to_dict(self) -> dict[str, object]:
        return {
            "character": self.character,
            "action": self.action,
            "reason": self.reason,
            "confidence": self.confidence,
            "source": self.source,
        }


@dataclass
class RepairPlan:
    repairs: list[Repair]
    unresolved: list[Issue]

    def overrides(self) -> dict[tuple[str, str], Image.Image]:
        return {(item.character, item.action): item.image for item in self.repairs}


def timestamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S-%f")


def threshold_bbox(frame: Image.Image, threshold: int = ALPHA_THRESHOLD) -> tuple[int, int, int, int] | None:
    alpha = frame.convert("RGBA").getchannel("A")
    return alpha.point(lambda value: 255 if value > threshold else 0).getbbox()


def _component_summary(mask: np.ndarray) -> list[tuple[int, tuple[int, int, int, int]]]:
    """Return 8-connected component areas and boxes for a boolean mask."""
    height, width = mask.shape
    visited = np.zeros((height, width), dtype=bool)
    components: list[tuple[int, tuple[int, int, int, int]]] = []
    for start_y, start_x in np.argwhere(mask):
        y0, x0 = int(start_y), int(start_x)
        if visited[y0, x0]:
            continue
        visited[y0, x0] = True
        queue: deque[tuple[int, int]] = deque(((y0, x0),))
        area = 0
        min_x = max_x = x0
        min_y = max_y = y0
        while queue:
            y, x = queue.popleft()
            area += 1
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))
        components.append((area, (min_x, min_y, max_x + 1, max_y + 1)))
    components.sort(reverse=True, key=lambda item: item[0])
    return components


def _box_gap(left: tuple[int, int, int, int], right: tuple[int, int, int, int]) -> int:
    horizontal = max(left[0] - right[2], right[0] - left[2], 0)
    vertical = max(left[1] - right[3], right[1] - left[3], 0)
    return max(horizontal, vertical)


def measure_frame(frame: Image.Image, index: int) -> FrameMetrics:
    rgba = frame.convert("RGBA")
    alpha_array = np.asarray(rgba.getchannel("A"))
    significant = alpha_array > ALPHA_THRESHOLD
    bbox = threshold_bbox(rgba)
    raw_bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        return FrameMetrics(index, rgba.width, rgba.height, True, raw_bbox=raw_bbox)
    x0, y0, x1, y1 = bbox
    extent = max(x1 - x0, y1 - y0)
    edge_contact = x0 <= 2 or y0 <= 2 or x1 >= rgba.width - 2 or y1 >= rgba.height - 2
    spread = 0
    if raw_bbox:
        spread = max(
            abs(raw_bbox[0] - x0),
            abs(raw_bbox[1] - y0),
            abs(raw_bbox[2] - x1),
            abs(raw_bbox[3] - y1),
        )
    detached_pixels = 0
    detached_boxes: list[tuple[int, int, int, int]] = []
    fill = int(significant.sum()) / max(1, (x1 - x0) * (y1 - y0))
    suspicious = (
        edge_contact
        or spread > 8
        or abs(extent - TARGET_EXTENT) > max(8, round(TARGET_EXTENT * 0.03))
        or abs((x0 + x1) / 2 - rgba.width / 2) > 3
        or (rgba.height == FRAME_SIZE and abs(y1 - TARGET_BASELINE) > 2)
        or fill < 0.20
    )
    if suspicious:
        components = _component_summary(significant)
        if components:
            total = sum(area for area, _ in components)
            main_box = components[0][1]
            fragment_limit = max(24, round(total * 0.006))
            for area, component_box in components[1:]:
                if area <= fragment_limit and _box_gap(main_box, component_box) >= 5:
                    detached_pixels += area
                    detached_boxes.append(component_box)
    return FrameMetrics(
        frame=index,
        width=rgba.width,
        height=rgba.height,
        empty=False,
        bbox=bbox,
        raw_bbox=raw_bbox,
        extent=extent,
        center_x=(x0 + x1) / 2,
        bottom=y1,
        edge_contact=edge_contact,
        halo_spread=spread,
        detached_fragment_pixels=detached_pixels,
        detached_fragment_boxes=detached_boxes,
    )


def detect_hand_anchor(frame: Image.Image, index: int) -> HandAnchor:
    """Estimate the weapon hand from the outer arm in an attack pose.

    Coordinates are normalized to the action cell so the exported list remains
    valid if runtime sheets are rescaled without changing their composition.
    """
    alpha = np.asarray(frame.convert("RGBA").getchannel("A")) > ALPHA_THRESHOLD
    points = np.argwhere(alpha)
    if not len(points):
        return HandAnchor(index, 0.28, 0.46, -1, 0.0)
    min_y, min_x = points.min(axis=0)
    max_y, max_x = points.max(axis=0)
    visible_w = max(1, int(max_x - min_x + 1))
    visible_h = max(1, int(max_y - min_y + 1))
    band_top = max(0, round(min_y + visible_h * 0.30))
    band_bottom = min(frame.height, round(min_y + visible_h * 0.61))
    torso_top = max(0, round(min_y + visible_h * 0.58))
    torso_bottom = min(frame.height, round(min_y + visible_h * 0.88))
    band_points = np.argwhere(alpha[band_top:band_bottom])
    torso_points = np.argwhere(alpha[torso_top:torso_bottom])
    if not len(band_points):
        return HandAnchor(
            index, (min_x + visible_w * 0.18) / frame.width,
            (min_y + visible_h * 0.46) / frame.height, -1, 0.2,
        )

    band_x = band_points[:, 1]
    # Percentile edges ignore tiny detached flecks and decorative wisps. Those
    # otherwise look like a fully extended arm and place a weapon in empty air.
    band_min = float(np.percentile(band_x, 1))
    band_max = float(np.percentile(band_x, 99))
    if len(torso_points):
        torso_x = torso_points[:, 1]
        torso_center = (float(np.percentile(torso_x, 5)) + float(np.percentile(torso_x, 95))) / 2
    else:
        torso_center = (float(min_x) + float(max_x)) / 2
    left_extension = torso_center - band_min
    right_extension = band_max - torso_center
    side = -1 if left_extension >= right_extension else 1
    edge = band_min if side < 0 else band_max
    reach = max(9, round(visible_w * 0.16))
    absolute_y = band_points[:, 0] + band_top
    near_edge = (
        (band_x >= band_min) & (band_x <= edge + reach)
        if side < 0 else
        (band_x <= band_max) & (band_x >= edge - reach)
    )
    candidates_x = band_x[near_edge]
    candidates_y = absolute_y[near_edge]
    if not len(candidates_x):
        hand_x = edge - side * reach * 0.45
        hand_y = (band_top + band_bottom) / 2
        confidence = 0.25
    else:
        # Weight the outer pixels more heavily so a thick sleeve does not pull
        # the marker back toward the torso and leave the grip floating.
        distance = np.abs(candidates_x.astype(np.float64) - torso_center)
        weights = np.square(distance + 1)
        hand_x = float(np.average(candidates_x, weights=weights))
        hand_y = float(np.average(candidates_y, weights=weights))
        asymmetry = abs(left_extension - right_extension) / max(1.0, visible_w)
        confidence = min(0.96, 0.55 + asymmetry * 1.8 + min(0.16, len(candidates_x) / 2000))
    return HandAnchor(
        index,
        max(0.0, min(1.0, hand_x / frame.width)),
        max(0.0, min(1.0, hand_y / frame.height)),
        side,
        confidence,
    )


def split_evenly(image: Image.Image, count: int) -> list[Image.Image]:
    if count <= 0:
        raise ValueError("frame count must be positive")
    bounds = [round(index * image.width / count) for index in range(count + 1)]
    return [image.crop((bounds[index], 0, bounds[index + 1], image.height)).convert("RGBA")
            for index in range(count)]


def inferred_square_frame_count(image: Image.Image) -> int | None:
    if image.height <= 0:
        return None
    ratio = image.width / image.height
    rounded = round(ratio)
    if 1 <= rounded <= 12 and abs(ratio - rounded) < 0.01:
        return rounded
    return None


def expand_walk_loop(frames: Sequence[Image.Image]) -> list[Image.Image]:
    if len(frames) != 3:
        raise ValueError("only a three-frame walk can be expanded automatically")
    # A forward/back loop avoids a hard jump while retaining every authored pose.
    return [frames[index].copy() for index in (0, 1, 2, 1, 0, 1)]


def normalize_frame(frame: Image.Image) -> Image.Image:
    """Trim residue and place one frame on the canonical 512px canvas."""
    rgba = frame.convert("RGBA")
    bbox = threshold_bbox(rgba)
    if bbox is None:
        raise ValueError("cannot normalize an empty frame")

    x0, y0, x1, y1 = bbox
    crop_box = (
        max(0, x0 - HALO_PADDING),
        max(0, y0 - HALO_PADDING),
        min(rgba.width, x1 + HALO_PADDING),
        min(rgba.height, y1 + HALO_PADDING),
    )
    subject = rgba.crop(crop_box)
    local_bbox = threshold_bbox(subject)
    if local_bbox is None:
        raise ValueError("frame became empty while trimming")
    significant_extent = max(local_bbox[2] - local_bbox[0], local_bbox[3] - local_bbox[1])
    scale = TARGET_EXTENT / max(1, significant_extent)
    new_size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    subject = subject.resize(new_size, Image.Resampling.NEAREST)
    # Integer resize rounding can land one pixel shy of the target.  Correct
    # that deterministically so independently processed poses cannot drift by
    # a pixel merely because their source dimensions differ.
    for _ in range(3):
        measured = threshold_bbox(subject)
        if measured is None:
            break
        measured_extent = max(measured[2] - measured[0], measured[3] - measured[1])
        if measured_extent == TARGET_EXTENT:
            break
        correction = TARGET_EXTENT / max(1, measured_extent)
        corrected_size = (
            max(1, round(subject.width * correction)),
            max(1, round(subject.height * correction)),
        )
        if corrected_size == subject.size:
            # Grow the dominant axis by one when normal rounding cannot move it.
            if subject.width >= subject.height:
                corrected_size = (subject.width + (1 if measured_extent < TARGET_EXTENT else -1), subject.height)
            else:
                corrected_size = (subject.width, subject.height + (1 if measured_extent < TARGET_EXTENT else -1))
        subject = subject.resize(corrected_size, Image.Resampling.NEAREST)
    placed_bbox = threshold_bbox(subject)
    if placed_bbox is None:
        raise ValueError("frame became empty while scaling")

    center = (placed_bbox[0] + placed_bbox[2]) / 2
    x = round(TARGET_CENTER_X - center)
    y = TARGET_BASELINE - placed_bbox[3]
    canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(subject, (x, y))
    return canvas


def assemble_strip(frames: Sequence[Image.Image]) -> Image.Image:
    strip = Image.new("RGBA", (FRAME_SIZE * len(frames), FRAME_SIZE), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame.convert("RGBA"), (index * FRAME_SIZE, 0))
    return strip


def remove_edge_green(image: Image.Image) -> Image.Image:
    """Remove only green-screen pixels connected to an outer image edge."""
    rgba = np.array(image.convert("RGBA"), copy=True)
    height, width = rgba.shape[:2]
    rgb = rgba[:, :, :3].astype(np.int16)
    alpha = rgba[:, :, 3]
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    keyed = (
        (alpha > 0)
        & (green > 100)
        & (green > red * 1.28)
        & (green > blue * 1.28)
        & ((green - np.maximum(red, blue)) > 24)
    )
    if not keyed.any():
        return Image.fromarray(rgba, "RGBA")

    edge_key_count = int(
        keyed[0, :].sum() + keyed[-1, :].sum()
        + keyed[:, 0].sum() + keyed[:, -1].sum()
    )
    perimeter = max(1, width * 2 + height * 2 - 4)
    # A genuine green screen occupies a substantial outer edge.  A handful of
    # green edge pixels is more likely a tail, sleeve, or prop touching a crop.
    if edge_key_count < max(16, round(perimeter * 0.05)):
        return Image.fromarray(rgba, "RGBA")

    seen = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        if keyed[0, x]:
            seen[0, x] = True
            queue.append((0, x))
        if keyed[height - 1, x] and not seen[height - 1, x]:
            seen[height - 1, x] = True
            queue.append((height - 1, x))
    for y in range(height):
        if keyed[y, 0] and not seen[y, 0]:
            seen[y, 0] = True
            queue.append((y, 0))
        if keyed[y, width - 1] and not seen[y, width - 1]:
            seen[y, width - 1] = True
            queue.append((y, width - 1))
    while queue:
        y, x = queue.popleft()
        for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if (0 <= next_y < height and 0 <= next_x < width
                    and keyed[next_y, next_x] and not seen[next_y, next_x]):
                seen[next_y, next_x] = True
                queue.append((next_y, next_x))
    rgba[seen, 3] = 0
    # Remove weak green antialiasing only immediately beside the keyed region.
    # Two controlled passes avoid reaching into legitimate green costume art.
    transparent = seen.copy()
    weak_green = (
        (rgba[:, :, 3] > 0)
        & (green > 55)
        & (green > red * 1.12)
        & (green > blue * 1.12)
        & ((green - np.maximum(red, blue)) > 8)
    )
    for _ in range(2):
        near = transparent.copy()
        near[1:, :] |= transparent[:-1, :]
        near[:-1, :] |= transparent[1:, :]
        near[:, 1:] |= transparent[:, :-1]
        near[:, :-1] |= transparent[:, 1:]
        spill = near & weak_green
        if not spill.any():
            break
        rgba[spill, 3] = 0
        transparent |= spill
    return Image.fromarray(rgba, "RGBA")


def remove_edge_neutral_backdrop(image: Image.Image) -> Image.Image:
    """Remove bright neutral generator backdrops connected to an image edge."""
    rgba = np.array(image.convert("RGBA"), copy=True)
    height, width = rgba.shape[:2]
    rgb = rgba[:, :, :3].astype(np.int16)
    alpha = rgba[:, :, 3]
    channel_range = rgb.max(axis=2) - rgb.min(axis=2)
    keyed = (alpha > 0) & (rgb.mean(axis=2) > 225) & (channel_range < 12)
    edge_key_count = int(
        keyed[0, :].sum() + keyed[-1, :].sum()
        + keyed[:, 0].sum() + keyed[:, -1].sum()
    )
    perimeter = max(1, width * 2 + height * 2 - 4)
    if edge_key_count < max(16, round(perimeter * 0.20)):
        return Image.fromarray(rgba, "RGBA")

    seen = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        for y in (0, height - 1):
            if keyed[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if keyed[y, x] and not seen[y, x]:
                seen[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if (0 <= next_y < height and 0 <= next_x < width
                    and keyed[next_y, next_x] and not seen[next_y, next_x]):
                seen[next_y, next_x] = True
                queue.append((next_y, next_x))
    rgba[seen, 3] = 0
    return Image.fromarray(rgba, "RGBA")


def remove_edge_background(image: Image.Image) -> Image.Image:
    return remove_edge_neutral_backdrop(remove_edge_green(image))


def source_strip_frames(source: Image.Image, frame_count: int) -> list[Image.Image]:
    cleaned = remove_edge_background(source)
    return [normalize_frame(frame) for frame in split_evenly(cleaned, frame_count)]


def atlas_action_frames(atlas: Image.Image, action: str) -> list[Image.Image]:
    if action not in COMPLETE_ATLAS_LAYOUT:
        raise ValueError(f"the 6x4 atlas does not contain {action}")
    if atlas.width % 6 or atlas.height % 4:
        raise ValueError("complete atlas must divide cleanly into a 6x4 grid")
    atlas = remove_edge_background(atlas)
    cell_width, cell_height = atlas.width // 6, atlas.height // 4
    frames: list[Image.Image] = []
    for column, row in COMPLETE_ATLAS_LAYOUT[action]:
        cell = atlas.crop((
            column * cell_width,
            row * cell_height,
            (column + 1) * cell_width,
            (row + 1) * cell_height,
        )).convert("RGBA")
        # Divider bleed is never authored sprite content.
        inset = max(2, min(cell.size) // 40)
        pixels = np.array(cell, copy=True)
        pixels[:inset, :, 3] = 0
        pixels[-inset:, :, 3] = 0
        pixels[:, :inset, 3] = 0
        pixels[:, -inset:, 3] = 0
        frames.append(normalize_frame(Image.fromarray(pixels, "RGBA")))
    return frames


def color_descriptor(image: Image.Image) -> np.ndarray:
    pixels = np.asarray(image.convert("RGBA")).reshape(-1, 4)
    rgb = pixels[pixels[:, 3] > 24, :3]
    if len(rgb) == 0:
        return np.zeros(144, dtype=np.float64)
    hsv = np.asarray(
        Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8), "RGB").convert("HSV")
    ).reshape(-1, 3).astype(np.int16)
    hue = np.minimum(11, hsv[:, 0] * 12 // 256)
    saturation = np.minimum(3, hsv[:, 1] * 4 // 256)
    value = np.minimum(2, hsv[:, 2] * 3 // 256)
    bucket = (hue * 4 + saturation) * 3 + value
    histogram = np.bincount(bucket, minlength=144).astype(np.float64)
    total = histogram.sum()
    return histogram / total if total else histogram


def combined_descriptor(frames: Iterable[Image.Image]) -> np.ndarray:
    descriptors = [color_descriptor(frame) for frame in frames]
    if not descriptors:
        return np.zeros(144, dtype=np.float64)
    result = np.sum(descriptors, axis=0)
    total = result.sum()
    return result / total if total else result


def descriptor_distance(left: np.ndarray, right: np.ndarray) -> float:
    # Hellinger distance is stable for differently sized silhouettes and makes
    # palette identity more important than pose geometry.
    return float(np.sqrt(np.square(np.sqrt(left) - np.sqrt(right)).sum()) / math.sqrt(2))


class SpriteDoctor:
    def __init__(
        self,
        project_root: Path = ROOT,
        animation_root: Path | None = None,
        require_death: bool = False,
    ) -> None:
        self.project_root = Path(project_root).resolve()
        self.animation_root = Path(animation_root or (self.project_root / "assets/sprites/character-animations")).resolve()
        self.sprite_root = self.project_root / "assets" / "sprites"
        self.require_death = require_death
        self._reference_cache: dict[str, tuple[Path, np.ndarray]] | None = None

    def character_dir(self, character: str) -> Path:
        if not character or any(character_part not in "abcdefghijklmnopqrstuvwxyz0123456789-"
                                for character_part in character.lower()) or character.lower() != character:
            raise ValueError(f"invalid character name: {character!r}")
        if character.startswith("-") or character.endswith("-") or "--" in character:
            raise ValueError(f"invalid character name: {character!r}")
        return self.animation_root / character

    def character_names(self) -> list[str]:
        if not self.animation_root.exists():
            return []
        return sorted(
            path.name for path in self.animation_root.iterdir()
            if path.is_dir() and not path.name.startswith("new-options") and not path.name.startswith(".")
        )

    def reference_path(self, character: str) -> Path | None:
        for group in REFERENCE_GROUPS:
            candidate = self.sprite_root / group / f"{character}.png"
            if candidate.exists():
                return candidate
        local_base = self.character_dir(character) / "base.png"
        return local_base if local_base.exists() else None

    def reference_descriptors(self) -> dict[str, tuple[Path, np.ndarray]]:
        if self._reference_cache is None:
            references: dict[str, tuple[Path, np.ndarray]] = {}
            for character in self.character_names():
                path = self.reference_path(character)
                if path:
                    with Image.open(path) as image:
                        references[character] = (path, color_descriptor(image))
            self._reference_cache = references
        return self._reference_cache

    @staticmethod
    def _override_image(
        overrides: Mapping[tuple[str, str], Image.Image | None] | None,
        character: str,
        action: str,
    ) -> tuple[bool, Image.Image | None]:
        key = (character, action)
        if overrides is not None and key in overrides:
            image = overrides[key]
            return True, image.copy() if image is not None else None
        return False, None

    def has_action(
        self,
        character: str,
        action: str,
        overrides: Mapping[tuple[str, str], Image.Image | None] | None = None,
    ) -> bool:
        found, image = self._override_image(overrides, character, action)
        if found:
            return image is not None
        return (self.character_dir(character) / f"{action}.png").exists()

    def expected_frame_count(
        self,
        character: str,
        action: str,
        overrides: Mapping[tuple[str, str], Image.Image | None] | None = None,
    ) -> int:
        if action == "walk" and not self.has_action(character, "unconscious", overrides):
            return 3
        return ACTION_SPECS[action].frames

    def load_sheet(
        self,
        character: str,
        action: str,
        overrides: Mapping[tuple[str, str], Image.Image | None] | None = None,
    ) -> Image.Image | None:
        found, image = self._override_image(overrides, character, action)
        if found:
            return image
        path = self.character_dir(character) / f"{action}.png"
        if not path.exists():
            return None
        with Image.open(path) as opened:
            return opened.copy()

    def weapon_anchors(
        self,
        characters: Sequence[str] | None = None,
    ) -> dict[str, dict[str, list[HandAnchor]]]:
        names = list(characters or self.character_names())
        unknown = sorted(set(names) - set(self.character_names()))
        if unknown:
            raise ValueError(f"unknown character(s): {', '.join(unknown)}")
        result: dict[str, dict[str, list[HandAnchor]]] = {}
        for character in names:
            actions: dict[str, list[HandAnchor]] = {}
            for action in ("melee", "ranged"):
                image = self.load_sheet(character, action)
                if image is None:
                    continue
                expected = self.expected_frame_count(character, action)
                actual = inferred_square_frame_count(image) or expected
                frames = split_evenly(image.convert("RGBA"), actual)
                actions[action] = [
                    detect_hand_anchor(frame, index + 1)
                    for index, frame in enumerate(frames)
                ]
            result[character] = actions
        return result

    def inspect_sheet(
        self,
        character: str,
        action: str,
        overrides: Mapping[tuple[str, str], Image.Image | None] | None = None,
    ) -> SheetInspection:
        path = self.character_dir(character) / f"{action}.png"
        expected_count = self.expected_frame_count(character, action, overrides)
        issues: list[Issue] = []
        try:
            image = self.load_sheet(character, action, overrides)
        except Exception as error:
            issues.append(Issue(
                "error", "unreadable_sheet", character, action,
                f"cannot read {path.name}: {error}", repairable=self.best_source(character, action) is not None,
            ))
            return SheetInspection(character, action, expected_count, None, None, [], [], issues, path)

        if image is None:
            requirement = ACTION_SPECS[action].requirement
            if action == "death" and self.require_death:
                requirement = "required"
            severity = "error" if requirement == "required" else "warning"
            code = "missing_sheet" if severity == "error" else "missing_recommended_sheet"
            source = self.best_source(character, action)
            issues.append(Issue(
                severity, code, character, action,
                f"{action}.png is missing" + ("; trusted source art is available" if source else ""),
                repairable=source is not None,
                confidence="high" if source else None,
                details={"source": str(source[0])} if source else {},
            ))
            return SheetInspection(character, action, expected_count, None, None, [], [], issues, path)

        original_mode = image.mode
        if original_mode != "RGBA":
            issues.append(Issue(
                "warning", "image_mode", character, action,
                f"image mode is {original_mode}; expected RGBA", repairable=True, confidence="high",
            ))
        image = image.convert("RGBA")
        inferred_count = inferred_square_frame_count(image)
        actual_count = inferred_count or (expected_count if image.width % expected_count == 0 else None)

        if inferred_count is not None and inferred_count != expected_count:
            repairable = action == "walk" and inferred_count == 3 and expected_count == 6
            source = self.best_source(character, action)
            issues.append(Issue(
                "error", "frame_count_mismatch", character, action,
                f"sheet contains {inferred_count} square frames; expected {expected_count}",
                repairable=repairable or source is not None,
                confidence="high" if repairable or source else None,
                details={"actual": inferred_count, "expected": expected_count},
            ))

        expected_size = (FRAME_SIZE * expected_count, FRAME_SIZE)
        if image.size != expected_size:
            issues.append(Issue(
                "error", "sheet_size", character, action,
                f"sheet is {image.width}x{image.height}; expected {expected_size[0]}x{expected_size[1]}",
                repairable=actual_count is not None or self.best_source(character, action) is not None,
                confidence="high" if actual_count is not None else None,
                details={"actual": list(image.size), "expected": list(expected_size)},
            ))

        if actual_count is None:
            issues.append(Issue(
                "error", "unsplittable_sheet", character, action,
                "the sheet cannot be divided into a reliable frame count",
                repairable=self.best_source(character, action) is not None,
            ))
            return SheetInspection(character, action, expected_count, None, image, [], [], issues, path)

        frames = split_evenly(image, actual_count)
        metrics = [measure_frame(frame, index + 1) for index, frame in enumerate(frames)]
        canonical_cells = image.height == FRAME_SIZE and all(frame.width == FRAME_SIZE for frame in frames)
        for metric in metrics:
            if metric.empty:
                issues.append(Issue(
                    "error", "empty_frame", character, action,
                    f"frame {metric.frame} contains no visible sprite pixels",
                    frame=metric.frame,
                    repairable=self.best_source(character, action) is not None,
                    confidence="high" if self.best_source(character, action) else None,
                ))
                continue
            if metric.edge_contact:
                issues.append(Issue(
                    "error", "clipped_frame", character, action,
                    f"frame {metric.frame} touches a cell edge and may be cropped",
                    frame=metric.frame, repairable=True, confidence="medium",
                    details={"bbox": list(metric.bbox or ())},
                ))
            if not canonical_cells:
                continue
            assert metric.extent is not None and metric.center_x is not None and metric.bottom is not None
            extent_delta = abs(metric.extent - TARGET_EXTENT)
            if extent_delta > max(8, round(TARGET_EXTENT * 0.03)):
                severity = "error" if extent_delta / TARGET_EXTENT > 0.08 else "warning"
                issues.append(Issue(
                    severity, "scale_mismatch", character, action,
                    f"frame {metric.frame} visible extent is {metric.extent}px; target is {TARGET_EXTENT}px",
                    frame=metric.frame, repairable=True, confidence="high",
                    details={"extent": metric.extent, "target": TARGET_EXTENT},
                ))
            if abs(metric.center_x - TARGET_CENTER_X) > 3:
                issues.append(Issue(
                    "warning", "center_mismatch", character, action,
                    f"frame {metric.frame} is centered at x={metric.center_x:.1f}; target is {TARGET_CENTER_X:.1f}",
                    frame=metric.frame, repairable=True, confidence="high",
                    details={"center_x": metric.center_x, "target": TARGET_CENTER_X},
                ))
            if abs(metric.bottom - TARGET_BASELINE) > 2:
                issues.append(Issue(
                    "warning", "baseline_mismatch", character, action,
                    f"frame {metric.frame} baseline is y={metric.bottom}; target is {TARGET_BASELINE}",
                    frame=metric.frame, repairable=True, confidence="high",
                    details={"bottom": metric.bottom, "target": TARGET_BASELINE},
                ))
            if metric.halo_spread > 8:
                issues.append(Issue(
                    "warning", "alpha_halo", character, action,
                    f"frame {metric.frame} has faint alpha residue {metric.halo_spread}px beyond its sprite",
                    frame=metric.frame, repairable=True, confidence="high",
                    details={"raw_bbox": list(metric.raw_bbox or ()), "bbox": list(metric.bbox or ())},
                ))
            if metric.detached_fragment_pixels:
                issues.append(Issue(
                    "warning", "detached_fragment", character, action,
                    f"frame {metric.frame} has {metric.detached_fragment_pixels} small opaque pixels detached from the main sprite",
                    frame=metric.frame, repairable=self.best_source(character, action) is not None,
                    confidence="medium",
                    details={"boxes": [list(box) for box in metric.detached_fragment_boxes]},
                ))
        return SheetInspection(character, action, expected_count, actual_count, image, frames, metrics, issues, path)

    def audit(
        self,
        characters: Sequence[str] | None = None,
        overrides: Mapping[tuple[str, str], Image.Image | None] | None = None,
        identity: bool = True,
    ) -> AuditResult:
        names = list(characters or self.character_names())
        virtual_names = {key[0] for key in (overrides or {})}
        known = set(self.character_names()) | virtual_names
        unknown = sorted(set(names) - known)
        if unknown:
            raise ValueError(f"unknown character(s): {', '.join(unknown)}")

        issues: list[Issue] = []
        inspections: dict[tuple[str, str], SheetInspection] = {}
        for character in names:
            for action in ACTION_SPECS:
                inspection = self.inspect_sheet(character, action, overrides)
                inspections[(character, action)] = inspection
                issues.extend(inspection.issues)

        if identity:
            issues.extend(self.identity_issues(names, inspections))
        return AuditResult(names, issues, inspections)

    def identity_issues(
        self,
        characters: Sequence[str],
        inspections: Mapping[tuple[str, str], SheetInspection],
    ) -> list[Issue]:
        references = self.reference_descriptors().copy()
        # Virtual/new characters may not be in the cache yet.
        for character in characters:
            if character not in references:
                path = self.reference_path(character)
                if path:
                    with Image.open(path) as image:
                        references[character] = (path, color_descriptor(image))

        issues: list[Issue] = []
        for character in characters:
            if character not in references:
                issues.append(Issue(
                    "warning", "missing_identity_reference", character, None,
                    "no matching base sprite was found for identity checks",
                ))
                continue
            own_path, own_descriptor = references[character]
            for action in ACTION_SPECS:
                inspection = inspections[(character, action)]
                usable = [frame for frame, metric in zip(inspection.frames, inspection.metrics) if not metric.empty]
                if not usable:
                    continue
                descriptor = combined_descriptor(usable)
                ranked = sorted(
                    (descriptor_distance(descriptor, candidate), name)
                    for name, (_, candidate) in references.items()
                )
                own_distance = descriptor_distance(descriptor, own_descriptor)
                best_distance, best_name = ranked[0]
                margin = own_distance - best_distance
                details = {
                    "reference": str(own_path),
                    "own_distance": round(own_distance, 4),
                    "best_match": best_name,
                    "best_distance": round(best_distance, 4),
                    "margin": round(margin, 4),
                }
                if (best_name != character and own_distance >= 0.40
                        and best_distance <= 0.24 and margin >= 0.18):
                    issues.append(Issue(
                        "error", "identity_mismatch", character, action,
                        f"{action}.png resembles {best_name} much more strongly than {character}",
                        repairable=False, confidence="high", details=details,
                    ))
                elif (best_name != character and own_distance >= 0.35
                      and best_distance <= 0.28 and margin >= 0.12):
                    issues.append(Issue(
                        "warning", "possible_identity_mismatch", character, action,
                        f"{action}.png may belong to {best_name} rather than {character}",
                        repairable=False, confidence="medium", details=details,
                    ))
        return issues

    def best_source(self, character: str, action: str) -> tuple[Path, str] | None:
        directory = self.character_dir(character)
        action_source = directory / f"{action}-generated-source.png"
        if action_source.exists():
            return action_source, "action-strip"
        complete = directory / "complete-transparent-source.png"
        if complete.exists() and action in COMPLETE_ATLAS_LAYOUT:
            return complete, "complete-atlas"
        return None

    def rebuild_from_source(self, character: str, action: str, expected_count: int) -> tuple[Image.Image, Path]:
        source = self.best_source(character, action)
        if source is None:
            raise ValueError(f"no trusted source is available for {character}/{action}")
        path, kind = source
        with Image.open(path) as opened:
            source_image = opened.convert("RGBA")
        if kind == "complete-atlas":
            frames = atlas_action_frames(source_image, action)
        else:
            source_count = 3 if action in {"melee", "ranged", "use", "hit"} else expected_count
            frames = source_strip_frames(source_image, source_count)
        if action == "walk" and len(frames) == 3 and expected_count == 6:
            frames = expand_walk_loop(frames)
        if len(frames) != expected_count:
            raise ValueError(f"source yielded {len(frames)} frames; expected {expected_count}")
        return assemble_strip(frames), path

    def reframe_existing(self, inspection: SheetInspection) -> Image.Image:
        if inspection.image is None or inspection.actual_count is None or not inspection.frames:
            raise ValueError("existing sheet is not repairable without source art")
        frames = [normalize_frame(frame) for frame in inspection.frames]
        if inspection.action == "walk" and len(frames) == 3 and inspection.expected_count == 6:
            frames = expand_walk_loop(frames)
        if len(frames) != inspection.expected_count:
            raise ValueError(
                f"cannot turn {len(frames)} existing frames into {inspection.expected_count} reliable frames"
            )
        return assemble_strip(frames)

    def plan_repairs(
        self,
        audit: AuditResult,
        identity_swaps: bool = False,
    ) -> RepairPlan:
        repairs: dict[tuple[str, str], Repair] = {}
        unresolved: list[Issue] = []
        for key, inspection in audit.inspections.items():
            geometry = [issue for issue in inspection.issues if issue.code in GEOMETRY_CODES]
            fragments = [issue for issue in inspection.issues if issue.code == "detached_fragment"]
            missing = [issue for issue in inspection.issues if issue.code in {"missing_sheet", "missing_recommended_sheet"}]
            if missing:
                source = self.best_source(inspection.character, inspection.action)
                if source:
                    try:
                        image, path = self.rebuild_from_source(
                            inspection.character, inspection.action, inspection.expected_count
                        )
                        repairs[key] = Repair(
                            inspection.character, inspection.action, image,
                            "rebuild missing sheet from same-character source art", "high", str(path),
                        )
                    except Exception:
                        if any(issue.severity == "error" for issue in missing):
                            unresolved.extend(missing)
                elif any(issue.severity == "error" for issue in missing):
                    unresolved.extend(missing)
                continue
            if not geometry and not fragments:
                continue

            severe = any(issue.code in {
                "unreadable_sheet", "empty_frame", "frame_count_mismatch", "unsplittable_sheet",
                "clipped_frame", "detached_fragment",
            }
                         for issue in inspection.issues)
            if severe and self.best_source(inspection.character, inspection.action):
                try:
                    image, path = self.rebuild_from_source(
                        inspection.character, inspection.action, inspection.expected_count
                    )
                    repairs[key] = Repair(
                        inspection.character, inspection.action, image,
                        "rebuild malformed sheet from same-character source art", "high", str(path),
                    )
                    continue
                except Exception:
                    pass
            if fragments:
                unresolved.extend(fragments)
                if not geometry:
                    continue
            try:
                image = self.reframe_existing(inspection)
                clipped = [issue for issue in geometry if issue.code == "clipped_frame"]
                confidence = "medium" if clipped else "high"
                reason = (
                    "reframe existing pixels; original edge contact still needs visual review"
                    if clipped else "normalize crop, scale, center, and baseline"
                )
                repairs[key] = Repair(
                    inspection.character, inspection.action, image,
                    reason, confidence, str(inspection.path),
                )
                unresolved.extend(clipped)
            except Exception:
                unresolved.extend(issue for issue in geometry if issue.severity == "error")

        # Installing newly recovered unconscious art changes the runtime's walk
        # contract immediately.  Upgrade a legacy three-frame walk in the same
        # transaction so a repair can never leave the character unloadable.
        upgraded_characters = {
            character for character, action in repairs if action == "unconscious"
        }
        for character in upgraded_characters:
            walk_key = (character, "walk")
            walk_image = repairs[walk_key].image if walk_key in repairs else self.load_sheet(character, "walk")
            if walk_image is None or inferred_square_frame_count(walk_image) != 3:
                continue
            walk_frames = [normalize_frame(frame) for frame in split_evenly(walk_image, 3)]
            repairs[walk_key] = Repair(
                character, "walk", assemble_strip(expand_walk_loop(walk_frames)),
                "expand legacy walk loop for recovered unconscious-enabled set", "high",
                repairs[walk_key].source if walk_key in repairs
                else str(self.character_dir(character) / "walk.png"),
            )

        identity_errors = [issue for issue in audit.issues if issue.code == "identity_mismatch"]
        repaired_identity: set[tuple[str, str]] = set()
        if identity_swaps:
            suggestions = {
                (issue.character, issue.action or ""): str(issue.details.get("best_match", ""))
                for issue in identity_errors
            }
            selected = set(audit.characters)
            for (character, action), other in sorted(suggestions.items()):
                if not other or other not in selected or character >= other:
                    continue
                if suggestions.get((other, action)) != character:
                    continue
                left = self.load_sheet(character, action)
                right = self.load_sheet(other, action)
                if left is None or right is None:
                    continue
                repairs[(character, action)] = Repair(
                    character, action, right.convert("RGBA"),
                    f"reciprocal high-confidence identity swap with {other}", "high",
                    str(self.character_dir(other) / f"{action}.png"),
                )
                repairs[(other, action)] = Repair(
                    other, action, left.convert("RGBA"),
                    f"reciprocal high-confidence identity swap with {character}", "high",
                    str(self.character_dir(character) / f"{action}.png"),
                )
                repaired_identity.update({(character, action), (other, action)})

        unresolved.extend(
            issue for issue in identity_errors
            if (issue.character, issue.action or "") not in repaired_identity
        )
        return RepairPlan(list(repairs.values()), unresolved)


def checkerboard(size: tuple[int, int], square: int = 8) -> Image.Image:
    image = Image.new("RGBA", size, (28, 30, 34, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], square):
        for x in range(0, size[0], square):
            if (x // square + y // square) % 2:
                draw.rectangle((x, y, x + square - 1, y + square - 1), fill=(42, 45, 50, 255))
    return image


def render_contact_sheet(
    doctor: SpriteDoctor,
    character: str,
    destination: Path,
    overrides: Mapping[tuple[str, str], Image.Image | None] | None = None,
) -> None:
    scale = 0.25
    cell = round(FRAME_SIZE * scale)
    label_width = 130
    row_height = cell + 28
    columns = 6
    width = label_width + columns * cell + 20
    height = 46 + len(ACTION_SPECS) * row_height
    contact = Image.new("RGBA", (width, height), (18, 20, 24, 255))
    draw = ImageDraw.Draw(contact)
    draw.text((12, 12), f"{character} - sprite audit", fill=(242, 226, 181, 255))

    for row, action in enumerate(ACTION_SPECS):
        top = 42 + row * row_height
        expected = doctor.expected_frame_count(character, action, overrides)
        draw.text((12, top + 6), f"{action} ({expected})", fill=(225, 225, 225, 255))
        image = doctor.load_sheet(character, action, overrides)
        if image is None:
            draw.text((12, top + 25), "MISSING", fill=(255, 105, 105, 255))
            continue
        actual = inferred_square_frame_count(image) or expected
        frames = split_evenly(image.convert("RGBA"), actual)
        for index, frame in enumerate(frames[:columns]):
            left = label_width + index * cell
            background = checkerboard((cell, cell))
            preview = frame.resize((cell, cell), Image.Resampling.NEAREST)
            background.alpha_composite(preview)
            contact.alpha_composite(background, (left, top))
            draw.line((left + cell // 2, top, left + cell // 2, top + cell - 1), fill=(50, 145, 170, 120))
            baseline = top + round(TARGET_BASELINE * scale)
            draw.line((left, baseline, left + cell - 1, baseline), fill=(215, 90, 70, 190))
            metric = measure_frame(frame, index + 1)
            if metric.bbox:
                box = tuple(round(value * scale) for value in metric.bbox)
                color = (255, 80, 80, 255) if metric.edge_contact else (90, 220, 130, 255)
                draw.rectangle((left + box[0], top + box[1], left + box[2] - 1, top + box[3] - 1), outline=color)
            draw.text((left + 4, top + cell + 4), str(index + 1), fill=(190, 190, 190, 255))
    destination.parent.mkdir(parents=True, exist_ok=True)
    contact.convert("RGB").save(destination, quality=94)


def render_weapon_anchor_sheet(
    doctor: SpriteDoctor,
    character: str,
    anchors: Mapping[str, Sequence[HandAnchor]],
    destination: Path,
) -> None:
    scale = 0.34
    cell = round(FRAME_SIZE * scale)
    label_width = 105
    width = label_width + cell * 3 + 20
    height = 44 + (cell + 34) * 2
    contact = Image.new("RGBA", (width, height), (18, 20, 24, 255))
    draw = ImageDraw.Draw(contact)
    draw.text((12, 12), f"{character} - weapon hand anchors", fill=(242, 226, 181, 255))
    for row, action in enumerate(("melee", "ranged")):
        top = 40 + row * (cell + 34)
        draw.text((12, top + 8), action.upper(), fill=(225, 225, 225, 255))
        image = doctor.load_sheet(character, action)
        if image is None:
            draw.text((12, top + 28), "MISSING", fill=(255, 105, 105, 255))
            continue
        action_anchors = list(anchors.get(action, ()))
        frames = split_evenly(image.convert("RGBA"), len(action_anchors) or 3)
        for index, (frame, anchor) in enumerate(zip(frames, action_anchors)):
            left = label_width + index * cell
            background = checkerboard((cell, cell))
            background.alpha_composite(frame.resize((cell, cell), Image.Resampling.NEAREST))
            contact.alpha_composite(background, (left, top))
            hand_x = left + round(anchor.x * cell)
            hand_y = top + round(anchor.y * cell)
            color = (255, 205, 65, 255)
            draw.ellipse((hand_x - 6, hand_y - 6, hand_x + 6, hand_y + 6), outline=color, width=2)
            draw.line((hand_x - 9, hand_y, hand_x + 9, hand_y), fill=color, width=2)
            draw.line((hand_x, hand_y - 9, hand_x, hand_y + 9), fill=color, width=2)
            draw.line((hand_x, hand_y, hand_x + anchor.side * 24, hand_y), fill=(80, 220, 245, 255), width=3)
            draw.text(
                (left + 4, top + cell + 4),
                f"F{index + 1}  {anchor.x:.3f},{anchor.y:.3f}  {anchor.confidence:.0%}",
                fill=(195, 195, 195, 255),
            )
    destination.parent.mkdir(parents=True, exist_ok=True)
    contact.convert("RGB").save(destination, quality=94)


def encode_png(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.convert("RGBA").save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def save_png_bytes_atomic(content: bytes, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix=f".{destination.stem}-", suffix=".tmp", dir=destination.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(handle, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def save_png_atomic(image: Image.Image, destination: Path) -> None:
    save_png_bytes_atomic(encode_png(image), destination)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def encode_weapon_anchors_lua(anchors: Mapping[str, Mapping[str, Sequence[HandAnchor]]]) -> str:
    output = [
        "-- Generated by tools/character_sprite_doctor.py weapon-anchors.",
        "-- Coordinates are normalized within each 512x512 attack frame.",
        "return {",
    ]
    for character in sorted(anchors):
        output.append(f'  ["{character}.png"]={{')
        for action in ("melee", "ranged"):
            values = anchors[character].get(action, ())
            encoded = ",".join(
                "{x=%.4f,y=%.4f,side=%d,confidence=%.3f}" %
                (anchor.x, anchor.y, anchor.side, anchor.confidence)
                for anchor in values
            )
            output.append(f"    {action}={{{encoded}}},")
        output.append("  },")
    output.append("}")
    return "\n".join(output) + "\n"


def weapon_anchor_report(
    anchors: Mapping[str, Mapping[str, Sequence[HandAnchor]]],
) -> dict[str, object]:
    values = [anchor for actions in anchors.values() for frames in actions.values() for anchor in frames]
    low_confidence = sum(anchor.confidence < 0.55 for anchor in values)
    return {
        "version": 1,
        "characters": {
            character: {
                action: [anchor.to_dict() for anchor in frames]
                for action, frames in actions.items()
            }
            for character, actions in sorted(anchors.items())
        },
        "summary": {
            "character_count": len(anchors),
            "anchor_count": len(values),
            "low_confidence": low_confidence,
        },
    }


def apply_weapon_anchor_overrides(
    anchors: dict[str, dict[str, list[HandAnchor]]],
    path: Path,
) -> int:
    if not path.exists():
        return 0
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("weapon attachment overrides must contain a JSON object")
    applied = 0
    for character, actions in value.items():
        if character not in anchors or not isinstance(actions, dict):
            raise ValueError(f"unknown character in weapon attachment overrides: {character}")
        for action, frames in actions.items():
            if action not in {"melee", "ranged"} or not isinstance(frames, list):
                raise ValueError(f"invalid weapon attachment override action: {character}/{action}")
            for item in frames:
                if not isinstance(item, dict):
                    raise ValueError(f"invalid weapon attachment override: {character}/{action}")
                frame = int(item.get("frame", 0))
                if frame < 1 or frame > len(anchors[character][action]):
                    raise ValueError(f"invalid weapon attachment frame: {character}/{action}/{frame}")
                x, y = float(item["x"]), float(item["y"])
                side = int(item.get("side", anchors[character][action][frame - 1].side))
                if not 0 <= x <= 1 or not 0 <= y <= 1 or side not in {-1, 1}:
                    raise ValueError(f"weapon attachment override is out of range: {character}/{action}/{frame}")
                anchors[character][action][frame - 1] = HandAnchor(frame, x, y, side, 1.0)
                applied += 1
    return applied


def emit_audit(result: AuditResult) -> None:
    for issue in result.issues:
        location = issue.character
        if issue.action:
            location += f"/{issue.action}"
        if issue.frame:
            location += f"[{issue.frame}]"
        print(f"{issue.severity.upper():7} {location}: {issue.message}")
    counts = result.counts
    print(
        f"Audit complete: {len(result.characters)} character(s), "
        f"{counts['error']} error(s), {counts['warning']} warning(s), {counts['info']} info"
    )


def selected_characters(doctor: SpriteDoctor, values: Sequence[str], all_requested: bool) -> list[str]:
    if all_requested:
        return doctor.character_names()
    if not values:
        raise ValueError("choose at least one character or pass --all")
    return list(dict.fromkeys(values))


def save_repair_plan(
    doctor: SpriteDoctor,
    plan: RepairPlan,
    output_root: Path,
    apply: bool,
    run_stamp: str,
) -> tuple[Path, Path | None]:
    output_root = output_root.resolve()
    preview_root = output_root / run_stamp / "preview"
    backup_root = output_root / "backups" / run_stamp if apply else None
    if not apply:
        for repair in plan.repairs:
            save_png_atomic(repair.image, preview_root / repair.character / f"{repair.action}.png")
        return preview_root, backup_root

    # Encode every replacement before touching game assets, then finish every
    # backup before replacing the first target.  A bad image or backup failure
    # therefore cannot leave a half-applied character set.
    encoded = [encode_png(repair.image) for repair in plan.repairs]
    assert backup_root is not None
    targets = [
        doctor.character_dir(repair.character) / f"{repair.action}.png"
        for repair in plan.repairs
    ]
    for repair, target in zip(plan.repairs, targets):
        if target.exists():
            backup = backup_root / repair.character / target.name
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup)
    for content, target in zip(encoded, targets):
        save_png_bytes_atomic(content, target)
    return preview_root, backup_root


def install_source_copy(source: Path, destination: Path, backup_root: Path | None) -> None:
    if source.resolve() == destination.resolve():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if backup_root is not None and destination.exists():
        backup = backup_root / destination.parent.name / destination.name
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(destination, backup)
    shutil.copy2(source, destination)


def command_audit(args: argparse.Namespace) -> int:
    doctor = SpriteDoctor(ROOT, require_death=args.require_death)
    names = list(args.characters) or doctor.character_names()
    result = doctor.audit(names, identity=not args.geometry_only)
    emit_audit(result)
    if args.report:
        write_json(Path(args.report), result.to_dict())
    if args.contact_sheets:
        contact_root = Path(args.contact_sheets)
        for name in names:
            render_contact_sheet(doctor, name, contact_root / f"{name}.png")
        print(f"Contact sheets: {contact_root.resolve()}")
    has_failure = result.counts["error"] > 0 or (args.strict and result.counts["warning"] > 0)
    return 1 if has_failure else 0


def command_repair(args: argparse.Namespace) -> int:
    doctor = SpriteDoctor(ROOT, require_death=args.require_death)
    names = selected_characters(doctor, args.characters, args.all)
    before = doctor.audit(names, identity=not args.geometry_only)
    plan = doctor.plan_repairs(before, identity_swaps=args.identity_swaps)
    run_stamp = timestamp()
    output_root = Path(args.output_root)
    preview_root, backup_root = save_repair_plan(doctor, plan, output_root, args.apply, run_stamp)
    overrides = {} if args.apply else plan.overrides()
    after = doctor.audit(names, overrides=overrides, identity=not args.geometry_only)

    print(f"Planned {len(plan.repairs)} repair(s); {len(plan.unresolved)} issue(s) still need authored art or review")
    for repair in plan.repairs:
        print(f"FIX     {repair.character}/{repair.action}: {repair.reason} [{repair.confidence} confidence]")
    emit_audit(after)

    run_root = output_root.resolve() / run_stamp
    report = {
        "mode": "apply" if args.apply else "preview",
        "repairs": [repair.to_dict() for repair in plan.repairs],
        "unresolved": [issue.to_dict() for issue in plan.unresolved],
        "post_audit": after.to_dict(),
    }
    report_path = Path(args.report) if args.report else run_root / "report.json"
    write_json(report_path, report)
    if args.contact_sheets:
        contacts = run_root / "contact-sheets"
        for name in names:
            render_contact_sheet(doctor, name, contacts / f"{name}.png", overrides=overrides)
        print(f"Contact sheets: {contacts}")
    if args.apply:
        print(f"Applied repairs. Backups: {backup_root}")
    else:
        print(f"Preview only; game assets were not changed. Preview: {preview_root}")
    print(f"Report: {report_path.resolve()}")
    return 1 if after.counts["error"] else 0


def atlas_repairs(doctor: SpriteDoctor, character: str, source: Path) -> list[Repair]:
    with Image.open(source) as opened:
        atlas = opened.convert("RGBA")
    modern = doctor.has_action(character, "unconscious")
    repairs: list[Repair] = []
    for action in COMPLETE_ATLAS_LAYOUT:
        frames = atlas_action_frames(atlas, action)
        if action == "walk" and modern:
            frames = expand_walk_loop(frames)
        repairs.append(Repair(
            character, action, assemble_strip(frames),
            "import from complete 6x4 master atlas", "high", str(source.resolve()),
        ))
    return repairs


def command_import_atlas(args: argparse.Namespace) -> int:
    doctor = SpriteDoctor(ROOT, require_death=args.require_death)
    source = Path(args.source).resolve()
    if not source.exists():
        raise ValueError(f"source does not exist: {source}")
    repairs = atlas_repairs(doctor, args.character, source)
    plan = RepairPlan(repairs, [])
    run_stamp = timestamp()
    output_root = Path(args.output_root)
    preview_root, backup_root = save_repair_plan(doctor, plan, output_root, args.apply, run_stamp)
    source_destination = doctor.character_dir(args.character) / "complete-transparent-source.png"
    if args.apply:
        install_source_copy(source, source_destination, backup_root)
    else:
        install_source_copy(source, preview_root / args.character / source_destination.name, None)
    overrides = {} if args.apply else plan.overrides()
    result = doctor.audit([args.character], overrides=overrides)
    emit_audit(result)
    run_root = output_root.resolve() / run_stamp
    report_path = Path(args.report) if args.report else run_root / "report.json"
    write_json(report_path, {
        "mode": "apply" if args.apply else "preview",
        "repairs": [repair.to_dict() for repair in repairs],
        "post_audit": result.to_dict(),
    })
    if args.contact_sheet:
        render_contact_sheet(doctor, args.character, run_root / f"{args.character}-contact.png", overrides)
    print(f"{'Installed' if args.apply else 'Previewed'} 6x4 atlas for {args.character}")
    print(f"Report: {report_path.resolve()}")
    return 1 if result.counts["error"] else 0


def command_import_action(args: argparse.Namespace) -> int:
    doctor = SpriteDoctor(ROOT, require_death=args.require_death)
    source = Path(args.source).resolve()
    if not source.exists():
        raise ValueError(f"source does not exist: {source}")
    expected = doctor.expected_frame_count(args.character, args.action)
    source_count = args.source_frames or expected
    with Image.open(source) as opened:
        frames = source_strip_frames(opened.convert("RGBA"), source_count)
    if args.action == "walk" and len(frames) == 3 and expected == 6:
        frames = expand_walk_loop(frames)
    if len(frames) != expected:
        raise ValueError(f"processed {len(frames)} frames; {args.action} requires {expected}")
    repair = Repair(
        args.character, args.action, assemble_strip(frames),
        "import action-specific source strip", "high", str(source),
    )
    repairs = [repair]
    # Adding unconscious art changes the runtime walk contract from 3 to 6.
    if args.action == "unconscious":
        walk = doctor.load_sheet(args.character, "walk")
        if walk is not None and inferred_square_frame_count(walk) == 3:
            walk_frames = [normalize_frame(frame) for frame in split_evenly(walk, 3)]
            repairs.append(Repair(
                args.character, "walk", assemble_strip(expand_walk_loop(walk_frames)),
                "expand legacy walk loop for modern unconscious-enabled set", "high",
                str(doctor.character_dir(args.character) / "walk.png"),
            ))

    plan = RepairPlan(repairs, [])
    run_stamp = timestamp()
    output_root = Path(args.output_root)
    preview_root, backup_root = save_repair_plan(doctor, plan, output_root, args.apply, run_stamp)
    source_destination = doctor.character_dir(args.character) / f"{args.action}-generated-source.png"
    if args.apply:
        install_source_copy(source, source_destination, backup_root)
    else:
        install_source_copy(source, preview_root / args.character / source_destination.name, None)
    overrides = {} if args.apply else plan.overrides()
    result = doctor.audit([args.character], overrides=overrides)
    emit_audit(result)
    run_root = output_root.resolve() / run_stamp
    report_path = Path(args.report) if args.report else run_root / "report.json"
    write_json(report_path, {
        "mode": "apply" if args.apply else "preview",
        "repairs": [item.to_dict() for item in repairs],
        "post_audit": result.to_dict(),
    })
    if args.contact_sheet:
        render_contact_sheet(doctor, args.character, run_root / f"{args.character}-contact.png", overrides)
    print(f"{'Installed' if args.apply else 'Previewed'} {args.action} for {args.character}")
    print(f"Report: {report_path.resolve()}")
    return 1 if result.counts["error"] else 0


def command_weapon_anchors(args: argparse.Namespace) -> int:
    doctor = SpriteDoctor(ROOT)
    names = list(args.characters) or doctor.character_names()
    anchors = doctor.weapon_anchors(names)
    override_path = Path(getattr(args, "overrides", DEFAULT_WEAPON_ANCHOR_OVERRIDES)).resolve()
    applied_overrides = apply_weapon_anchor_overrides(anchors, override_path)
    encoded = encode_weapon_anchors_lua(anchors)
    destination = Path(args.output).resolve()
    report = weapon_anchor_report(anchors)
    if args.check:
        current = destination.read_text(encoding="utf-8") if destination.exists() else ""
        if current != encoded:
            print(f"Weapon attachment list is stale: {destination}")
            return 1
        print(f"Weapon attachment list is current: {destination}")
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(encoded, encoding="utf-8")
        print(f"Weapon attachment list: {destination}")
    if args.report:
        write_json(Path(args.report), report)
        print(f"Weapon attachment report: {Path(args.report).resolve()}")
    if args.contact_sheets:
        contact_root = Path(args.contact_sheets)
        for character in names:
            render_weapon_anchor_sheet(
                doctor, character, anchors[character], contact_root / f"{character}.png"
            )
        print(f"Weapon anchor contact sheets: {contact_root.resolve()}")
    summary = report["summary"]
    assert isinstance(summary, dict)
    print(
        f"Detected {summary['anchor_count']} hand point(s) for "
        f"{summary['character_count']} character(s); {summary['low_confidence']} need visual review; "
        f"{applied_overrides} authored override(s) applied"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Audit, repair, and import Mouse Frontier character sprite sheets."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit = subparsers.add_parser("audit", help="audit complete character animation sets")
    audit.add_argument("characters", nargs="*", help="character directory names; defaults to every character")
    audit.add_argument("--report", help="write the machine-readable JSON report here")
    audit.add_argument("--contact-sheets", metavar="DIR", help="render visual QA sheets into this directory")
    audit.add_argument("--require-death", action="store_true", help="treat missing death art as an error")
    audit.add_argument("--geometry-only", action="store_true", help="skip cross-character identity matching")
    audit.add_argument("--strict", action="store_true", help="return failure for warnings as well as errors")
    audit.set_defaults(func=command_audit)

    repair = subparsers.add_parser("repair", help="preview or apply safe crop/scale repairs")
    repair.add_argument("characters", nargs="*", help="character directory names")
    repair.add_argument("--all", action="store_true", help="repair every character")
    repair.add_argument("--apply", action="store_true", help="back up and replace game assets; default is preview only")
    repair.add_argument(
        "--identity-swaps", action="store_true",
        help="also swap reciprocal, high-confidence misassigned action sheets",
    )
    repair.add_argument("--require-death", action="store_true")
    repair.add_argument("--geometry-only", action="store_true", help="skip cross-character identity matching")
    repair.add_argument("--contact-sheets", action="store_true", help="render post-repair visual QA sheets")
    repair.add_argument("--report", help="write the JSON report here")
    repair.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    repair.set_defaults(func=command_repair)

    atlas = subparsers.add_parser("import-atlas", help="process an established 6x4 master atlas")
    atlas.add_argument("character")
    atlas.add_argument("source")
    atlas.add_argument("--apply", action="store_true")
    atlas.add_argument("--require-death", action="store_true")
    atlas.add_argument("--contact-sheet", action="store_true")
    atlas.add_argument("--report")
    atlas.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    atlas.set_defaults(func=command_import_atlas)

    action = subparsers.add_parser("import-action", help="process one generated horizontal action strip")
    action.add_argument("character")
    action.add_argument("action", choices=tuple(ACTION_SPECS))
    action.add_argument("source")
    action.add_argument("--source-frames", type=int, help="number of panels in the source image")
    action.add_argument("--apply", action="store_true")
    action.add_argument("--require-death", action="store_true")
    action.add_argument("--contact-sheet", action="store_true")
    action.add_argument("--report")
    action.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    action.set_defaults(func=command_import_action)

    anchors = subparsers.add_parser(
        "weapon-anchors",
        help="detect melee/ranged hand points and generate the runtime attachment list",
    )
    anchors.add_argument("characters", nargs="*", help="character directories; defaults to every character")
    anchors.add_argument(
        "--output", default=str(ROOT / "game" / "weapon_attachment_points.lua"),
        help="generated Lua attachment list",
    )
    anchors.add_argument("--report", help="optional JSON report with confidence values")
    anchors.add_argument(
        "--overrides", default=str(DEFAULT_WEAPON_ANCHOR_OVERRIDES),
        help="JSON file containing reviewed per-frame corrections",
    )
    anchors.add_argument("--contact-sheets", metavar="DIR", help="render hand-point review sheets")
    anchors.add_argument("--check", action="store_true", help="fail when the generated list is out of date")
    anchors.set_defaults(func=command_weapon_anchors)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except (OSError, ValueError) as error:
        parser.error(str(error))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
