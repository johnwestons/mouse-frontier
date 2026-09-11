"""Audit character animation strips and render review artifacts from a motion spec.

Project-local vendor copy of sprite-gait-overhaul/scripts/sprite_motion_audit.py,
retrieved 2026-09-10; upstream SHA-256:
a9c6d3ca5545eb9bffff5a5bcef0dceac05751da77cee61bd44cf5a0b6b5f97f.

Local extension: audit.center_metric may opt into the builder's actual-pixel
core anchor. Bounding-box behavior remains the default; other checks, limits,
frame metrics, and rendered review artifacts are unchanged.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import Counter, deque
from pathlib import Path
from statistics import median
from typing import Any, Sequence

try:
    import numpy as np
    from PIL import Image, ImageDraw
except ImportError as exc:  # pragma: no cover - depends on the invoking runtime
    raise SystemExit("sprite_motion_audit requires Pillow and NumPy") from exc


CANONICAL_DIRECTIONS = (
    "north", "northeast", "east", "southeast",
    "south", "southwest", "west", "northwest",
)


def issue(
    issues: list[dict[str, Any]], severity: str, code: str, message: str,
    *, animation: str | None = None, frame: int | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    value: dict[str, Any] = {"severity": severity, "code": code, "message": message}
    if animation is not None:
        value["animation"] = animation
    if frame is not None:
        value["frame"] = frame
    if details:
        value["details"] = details
    issues.append(value)


def validate_center_metric(settings: dict[str, Any]) -> str:
    """Validate an explicit measurement contract, never a warning waiver."""
    metric = settings.get("center_metric", "bbox")
    if not isinstance(metric, str) or metric not in {"bbox", "core"}:
        raise ValueError("audit.center_metric must be 'bbox' or 'core'")
    if metric == "core":
        if __package__ in {None, ""}:
            project_root = str(Path(__file__).resolve().parents[1])
            if project_root not in sys.path:
                sys.path.insert(0, project_root)
        from tools.build_directional_character_assets import ALPHA_THRESHOLD
        if int(settings.get("alpha_threshold", 16)) != ALPHA_THRESHOLD:
            raise ValueError(
                f"audit.center_metric='core' requires alpha_threshold={ALPHA_THRESHOLD} "
                "to match the builder's actual-pixel anchor"
            )
    return metric


def measured_core_center(frame: Image.Image) -> float:
    """Use exactly the builder's raster anchor and its significant-pixel box."""
    from tools.build_directional_character_assets import core_horizontal_anchor_x, visible_bbox
    return core_horizontal_anchor_x(frame, visible_bbox(frame))


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def alpha_bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    points = np.argwhere(mask)
    if len(points) == 0:
        return None
    top, left = points.min(axis=0)
    bottom, right = points.max(axis=0)
    return int(left), int(top), int(right) + 1, int(bottom) + 1


def component_summary(mask: np.ndarray) -> list[dict[str, Any]]:
    height, width = mask.shape
    visited = np.zeros((height, width), dtype=bool)
    result: list[dict[str, Any]] = []
    for start_y, start_x in np.argwhere(mask):
        y0, x0 = int(start_y), int(start_x)
        if visited[y0, x0]:
            continue
        visited[y0, x0] = True
        queue: deque[tuple[int, int]] = deque(((y0, x0),))
        area = 0
        left = right = x0
        top = bottom = y0
        while queue:
            y, x = queue.popleft()
            area += 1
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))
        result.append({"area": area, "bbox": [left, top, right + 1, bottom + 1]})
    return sorted(result, key=lambda item: item["area"], reverse=True)


def color_descriptor(frame: Image.Image, alpha_threshold: int) -> np.ndarray:
    pixels = np.asarray(frame.convert("RGBA")).reshape(-1, 4)
    rgb = pixels[pixels[:, 3] > alpha_threshold, :3]
    if len(rgb) == 0:
        return np.zeros(96, dtype=np.float64)
    hsv = np.asarray(
        Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8), "RGB").convert("HSV")
    ).reshape(-1, 3).astype(np.int16)
    bucket = (
        (np.minimum(7, hsv[:, 0] * 8 // 256) * 4
         + np.minimum(3, hsv[:, 1] * 4 // 256)) * 3
        + np.minimum(2, hsv[:, 2] * 3 // 256)
    )
    histogram = np.bincount(bucket, minlength=96).astype(np.float64)
    return histogram / histogram.sum() if histogram.sum() else histogram


def descriptor_distance(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.sqrt(np.square(np.sqrt(left) - np.sqrt(right)).sum()) / math.sqrt(2))


def aligned_mask(frame: Image.Image, bbox: tuple[int, int, int, int] | None) -> np.ndarray:
    size = max(frame.width, frame.height)
    canvas = np.zeros((size, size), dtype=bool)
    if bbox is None:
        return canvas
    source = np.asarray(frame.getchannel("A")) > 16
    left, _, right, bottom = bbox
    shift_x = round(size / 2 - (left + right) / 2)
    shift_y = round(size * 0.9 - bottom)
    source_y0, source_x0 = max(0, -shift_y), max(0, -shift_x)
    target_y0, target_x0 = max(0, shift_y), max(0, shift_x)
    height = min(frame.height - source_y0, size - target_y0)
    width = min(frame.width - source_x0, size - target_x0)
    if height > 0 and width > 0:
        canvas[target_y0:target_y0 + height, target_x0:target_x0 + width] = (
            source[source_y0:source_y0 + height, source_x0:source_x0 + width]
        )
    return canvas


def silhouette_distance(left: np.ndarray, right: np.ndarray) -> float:
    union = int(np.logical_or(left, right).sum())
    return 0.0 if union == 0 else 1.0 - int(np.logical_and(left, right).sum()) / union


def checkerboard(width: int, height: int, tile: int = 16) -> Image.Image:
    image = Image.new("RGBA", (width, height), (238, 238, 238, 255))
    draw = ImageDraw.Draw(image)
    alternate = (210, 210, 210, 255)
    for y in range(0, height, tile):
        for x in range(0, width, tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, min(width, x + tile) - 1, min(height, y + tile) - 1), fill=alternate)
    return image


def render_contact_sheet(
    name: str, frames: list[Image.Image], metrics: list[dict[str, Any]],
    labels: list[str], destination: Path,
) -> None:
    cell, header = 192, 42
    columns = min(8, max(1, len(frames)))
    rows = max(1, math.ceil(len(frames) / columns))
    sheet = Image.new("RGBA", (columns * cell, rows * (cell + header)), (30, 34, 40, 255))
    draw = ImageDraw.Draw(sheet)
    for index, frame in enumerate(frames):
        column, row = index % columns, index // columns
        x, y = column * cell, row * (cell + header)
        background = checkerboard(cell, cell)
        preview = frame.copy()
        preview.thumbnail((cell, cell), Image.Resampling.NEAREST)
        background.alpha_composite(preview, ((cell - preview.width) // 2, (cell - preview.height) // 2))
        sheet.alpha_composite(background, (x, y + header))
        label = labels[index] if index < len(labels) else f"frame_{index + 1}"
        draw.text((x + 6, y + 5), f"{name} · {index + 1}", fill=(250, 226, 166, 255))
        draw.text((x + 6, y + 21), label, fill=(225, 230, 236, 255))
        bbox = metrics[index].get("bbox") if index < len(metrics) else None
        if bbox:
            scale = min(cell / frame.width, cell / frame.height)
            offset_x = round((cell - frame.width * scale) / 2)
            offset_y = round((cell - frame.height * scale) / 2)
            baseline = y + header + offset_y + round(bbox[3] * scale)
            draw.line((x, baseline, x + cell - 1, baseline), fill=(255, 90, 90, 180), width=1)
            center = x + offset_x + round(((bbox[0] + bbox[2]) / 2) * scale)
            draw.line((center, y + header, center, y + header + cell - 1), fill=(90, 190, 255, 150), width=1)
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def render_gif(frames: list[Image.Image], destination: Path, duration_ms: int) -> None:
    previews: list[Image.Image] = []
    for frame in frames:
        background = checkerboard(256, 256)
        preview = frame.copy()
        preview.thumbnail((256, 256), Image.Resampling.NEAREST)
        background.alpha_composite(preview, ((256 - preview.width) // 2, (256 - preview.height) // 2))
        previews.append(background.convert("P", palette=Image.Palette.ADAPTIVE))
    if not previews:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    previews[0].save(
        destination, save_all=True, append_images=previews[1:], loop=0,
        duration=max(20, duration_ms), disposal=2,
    )


def load_frames(
    name: str, definition: dict[str, Any], project_root: Path,
    issues: list[dict[str, Any]],
) -> tuple[Path, list[Image.Image]]:
    relative = definition.get("path")
    if not isinstance(relative, str) or not relative:
        issue(issues, "error", "missing_path", "animation has no asset path", animation=name)
        return project_root, []
    path = (project_root / relative).resolve()
    if not path.is_file():
        issue(issues, "error", "missing_asset", f"asset does not exist: {relative}", animation=name)
        return path, []
    try:
        frame_width = int(definition.get("frame_width", 0))
        frame_height = int(definition.get("frame_height", 0))
        frame_count = int(definition.get("frame_count", 0))
    except (TypeError, ValueError):
        frame_width = frame_height = frame_count = 0
    if min(frame_width, frame_height, frame_count) <= 0:
        issue(issues, "error", "invalid_frame_geometry", "frame dimensions and count must be positive integers", animation=name)
        return path, []
    with Image.open(path) as opened:
        has_alpha = opened.mode in {"RGBA", "LA"} or "transparency" in opened.info
        image = opened.convert("RGBA")
    if not has_alpha:
        issue(issues, "error", "missing_alpha", "sprite strip has no alpha channel", animation=name)
    expected = (frame_width * frame_count, frame_height)
    if image.size != expected:
        issue(
            issues, "error", "sheet_dimensions",
            f"expected {expected[0]}x{expected[1]}, found {image.width}x{image.height}",
            animation=name,
        )
        return path, []
    return path, [
        image.crop((index * frame_width, 0, (index + 1) * frame_width, frame_height))
        for index in range(frame_count)
    ]


def audit_animation(
    name: str, definition: dict[str, Any], project_root: Path,
    settings: dict[str, Any], pose_labels: list[str], output_root: Path,
    make_gif: bool, gait_duration_ms: int | None, issues: list[dict[str, Any]],
) -> dict[str, Any]:
    center_metric = validate_center_metric(settings)
    path, frames = load_frames(name, definition, project_root, issues)
    if not frames:
        return {"name": name, "path": str(path), "frames": []}
    alpha_threshold = int(settings.get("alpha_threshold", 16))
    edge_margin = int(settings.get("edge_margin", 2))
    detached_component_ratio = max(0, float(settings.get("detached_component_ratio", 0.003)))
    metrics: list[dict[str, Any]] = []
    descriptors: list[np.ndarray] = []
    masks: list[np.ndarray] = []
    digests: dict[str, list[int]] = {}
    for index, frame in enumerate(frames, 1):
        alpha = np.asarray(frame.getchannel("A"))
        significant = alpha > alpha_threshold
        bbox = alpha_bbox(significant)
        components = component_summary(significant)
        visible = int(significant.sum())
        metric = {"frame": index, "bbox": list(bbox) if bbox else None, "visible_pixels": visible}
        metrics.append(metric)
        descriptors.append(color_descriptor(frame, alpha_threshold))
        masks.append(aligned_mask(frame, bbox))
        digest = hashlib.sha256(frame.tobytes()).hexdigest()
        digests.setdefault(digest, []).append(index)
        if bbox is None:
            issue(issues, "error", "empty_frame", "frame has no significant pixels", animation=name, frame=index)
            continue
        left, top, right, bottom = bbox
        if (
            left <= edge_margin or top <= edge_margin
            or right >= frame.width - edge_margin or bottom >= frame.height - edge_margin
        ):
            issue(
                issues, "error", "clipped_frame", "significant art touches the frame edge",
                animation=name, frame=index, details={"bbox": list(bbox)},
            )
        if components:
            detached = [
                component for component in components[1:]
                if component["area"] >= max(16, round(visible * detached_component_ratio))
            ]
            if detached:
                issue(
                    issues, "warning", "detached_components",
                    "substantial pixels are detached from the main sprite",
                    animation=name, frame=index, details={"components": detached},
                )
        corner_alpha = [
            int(alpha[0, 0]), int(alpha[0, -1]), int(alpha[-1, 0]), int(alpha[-1, -1]),
        ]
        if any(value > alpha_threshold for value in corner_alpha):
            issue(
                issues, "error", "opaque_corner_background",
                "a frame corner is opaque; background or checker residue is likely",
                animation=name, frame=index, details={"corner_alpha": corner_alpha},
            )

    usable = [metric for metric in metrics if metric["bbox"]]
    bbox_positions = [(metric["bbox"][0] + metric["bbox"][2]) / 2 for metric in usable]
    centers = (
        [measured_core_center(frames[metric["frame"] - 1]) for metric in usable]
        if center_metric == "core" else list(bbox_positions)
    )
    center_tolerance = int(settings.get("center_tolerance", max(6, round(frames[0].width * 0.03))))
    center_metrics = {
        "metric": center_metric, "positions": centers,
        "bbox_positions": bbox_positions, "tolerance": center_tolerance,
    }
    if len(usable) > 1:
        bottoms = [metric["bbox"][3] for metric in usable]
        tops = [metric["bbox"][1] for metric in usable]
        baseline_tolerance = int(settings.get("baseline_tolerance", max(4, round(frames[0].height * 0.015))))
        if max(bottoms) - min(bottoms) > baseline_tolerance:
            issue(
                issues, "warning", "baseline_jitter", "foot baseline varies across the strip",
                animation=name, details={"bottoms": bottoms, "tolerance": baseline_tolerance},
            )
        if max(centers) - min(centers) > center_tolerance:
            issue(
                issues, "warning", "center_jitter", "sprite center varies across the strip",
                animation=name, details={"centers": centers, "tolerance": center_tolerance},
            )
        elif center_metric == "core" and max(bbox_positions) - min(bbox_positions) > center_tolerance:
            issue(
                issues, "info", "bbox_center_extent_change",
                "bounding-box center varies while the declared core anchor remains stable",
                animation=name, details={
                    "bbox_centers": bbox_positions, "core_centers": centers,
                    "tolerance": center_tolerance,
                },
            )
        heights = [metric["bbox"][3] - metric["bbox"][1] for metric in usable]
        top_tolerance = max(12, round(float(median(heights)) * 0.08))
        if max(tops) - min(tops) > top_tolerance:
            issue(
                issues, "warning", "top_bound_jitter", "top bounds vary more than expected",
                animation=name, details={"tops": tops, "tolerance": top_tolerance},
            )
        shared_descriptor = np.sum(descriptors, axis=0)
        if shared_descriptor.sum():
            shared_descriptor /= shared_descriptor.sum()
        palette_drift = [
            {"frame": index + 1, "distance": round(descriptor_distance(value, shared_descriptor), 4)}
            for index, value in enumerate(descriptors)
            if descriptor_distance(value, shared_descriptor) > 0.30
        ]
        if palette_drift:
            issue(
                issues, "warning", "identity_palette_drift",
                "one or more frames drift from the strip's shared palette",
                animation=name, details={"comparisons": palette_drift},
            )

    duplicate_groups = [group for group in digests.values() if len(group) > 1]
    if duplicate_groups:
        issue(
            issues, "warning", "exact_duplicate_frames", "animation contains byte-identical frames",
            animation=name, details={"groups": duplicate_groups},
        )
    if len(frames) > 1 and len(digests) <= len(frames) // 2:
        issue(
            issues, "error", "low_effective_motion",
            f"{len(frames)} frames contain only {len(digests)} unique images",
            animation=name,
        )
    if definition.get("loop", False) and len(masks) > 1:
        internal = [silhouette_distance(masks[index], masks[index + 1]) for index in range(len(masks) - 1)]
        seam = silhouette_distance(masks[-1], masks[0])
        internal_median = float(median(internal)) if internal else 0.0
        if seam > max(0.55, internal_median * 1.8 + 0.05):
            issue(
                issues, "warning", "loop_seam", "last-to-first loop seam is unusually large",
                animation=name,
                details={"seam": round(seam, 4), "internal_median": round(internal_median, 4)},
            )

    labels = pose_labels if definition.get("role") == "gait" else []
    render_contact_sheet(name, frames, metrics, labels, output_root / "contact-sheets" / f"{name}.png")
    if make_gif:
        if definition.get("role") == "gait" and gait_duration_ms:
            duration = gait_duration_ms
        else:
            fps = float(definition.get("fps", 6) or 6)
            duration = round(1000 / max(0.1, fps))
        render_gif(frames, output_root / "previews" / f"{name}.gif", duration)
    return {"name": name, "path": str(path), "frames": metrics, "center_metrics": center_metrics}


def validate_gait(
    manifest: dict[str, Any], animations: dict[str, Any], issues: list[dict[str, Any]],
) -> dict[str, Any]:
    gait = manifest.get("gait")
    if not isinstance(gait, dict):
        issue(issues, "error", "missing_gait", "motion specification has no gait object")
        return {}
    poses = gait.get("pose_order")
    if not isinstance(poses, list) or len(poses) != 8 or not all(isinstance(value, str) and value for value in poses):
        issue(issues, "error", "invalid_pose_order", "gait pose_order must contain eight named phases")
        poses = []
    profile: dict[str, Any] = {"pose_order": poses}
    for key in ("speed_multipliers", "acceleration_multipliers"):
        values = gait.get(key)
        if (
            not isinstance(values, list) or len(values) != len(poses)
            or not all(finite_number(value) and value > 0 for value in values)
        ):
            issue(issues, "error", f"invalid_{key}", f"{key} must contain one positive number per pose")
            continue
        average = sum(values) / len(values)
        profile[f"{key}_average"] = round(average, 6)
        if abs(average - 1) > 0.03:
            issue(
                issues, "warning", f"off_center_{key}",
                f"{key} average is {average:.4f}, not near the base value 1.0",
            )
        half = len(values) // 2
        if half and any(abs(values[index] - values[index + half]) > 0.0001 for index in range(half)):
            issue(issues, "warning", f"asymmetric_{key}", f"{key} does not repeat for the opposite step")
    pixels = gait.get("pixels_per_frame")
    speed = gait.get("base_speed")
    if not finite_number(pixels) or pixels <= 0 or not finite_number(speed) or speed <= 0:
        issue(issues, "error", "invalid_gait_timing", "pixels_per_frame and base_speed must be positive numbers")
    elif poses:
        profile["nominal_pose_ms"] = round(1000 * pixels / speed)
        profile["nominal_cycle_seconds"] = round(len(poses) * pixels / speed, 4)
    for name, definition in animations.items():
        if definition.get("role") == "gait" and definition.get("frame_count") != len(poses):
            issue(
                issues, "error", "gait_frame_count",
                f"gait animation has {definition.get('frame_count')} frames but the profile has {len(poses)} poses",
                animation=name,
            )
    return profile


def validate_directions(
    manifest: dict[str, Any], animations: dict[str, Any], issues: list[dict[str, Any]],
) -> None:
    directions = manifest.get("directions")
    if not isinstance(directions, dict):
        issue(issues, "error", "missing_directions", "motion specification has no directions map")
        return
    walk_actions: set[str] = set()
    idle_actions: set[str] = set()
    for direction in CANONICAL_DIRECTIONS:
        mapping = directions.get(direction)
        if not isinstance(mapping, dict):
            issue(issues, "error", "missing_direction", f"direction is not mapped: {direction}")
            continue
        walk_action = mapping.get("walk_animation", mapping.get("animation"))
        idle_action = mapping.get("idle_animation")
        if walk_action not in animations:
            issue(issues, "error", "unknown_walk_animation", f"{direction} references unknown walk animation: {walk_action}")
        elif animations[walk_action].get("role") != "gait":
            issue(issues, "error", "direction_not_gait", f"{direction} references a non-gait walk animation: {walk_action}")
        else:
            walk_actions.add(walk_action)
        if idle_action not in animations:
            issue(issues, "error", "unknown_idle_animation", f"{direction} references unknown idle animation: {idle_action}")
        elif animations[idle_action].get("role") != "directional_idle":
            issue(issues, "error", "direction_not_idle", f"{direction} references a non-directional idle animation: {idle_action}")
        else:
            idle_actions.add(idle_action)
        if not isinstance(mapping.get("mirror_x"), bool):
            issue(issues, "error", "missing_mirror_decision", f"{direction} must explicitly set mirror_x")
    if len(walk_actions) < 5:
        issue(issues, "error", "insufficient_walk_direction_coverage", "eight-sector motion requires at least five authored walk views")
    if len(idle_actions) < 5:
        issue(issues, "error", "insufficient_idle_direction_coverage", "eight-sector motion requires at least five authored idle views")
    extras = sorted(set(directions) - set(CANONICAL_DIRECTIONS))
    if extras:
        issue(issues, "warning", "extra_directions", "non-canonical direction mappings are present", details={"directions": extras})


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path)
    parser.add_argument("--strict", action="store_true", help="treat warnings as a failing audit")
    parser.add_argument("--no-gif", action="store_true")
    args = parser.parse_args(argv)

    spec_path = args.spec.resolve()
    project_root = args.project_root.resolve()
    try:
        manifest = json.loads(spec_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Unable to read motion specification: {exc}")
        return 2
    if not isinstance(manifest, dict):
        print("Motion specification root must be a JSON object")
        return 2
    character = manifest.get("character")
    if not isinstance(character, str) or not character.strip():
        print("Motion specification requires a non-empty character name")
        return 2
    raw_animations = manifest.get("animations")
    if not isinstance(raw_animations, dict) or not raw_animations:
        print("Motion specification requires at least one animation")
        return 2

    output_root = (args.output or project_root / "output" / "character-motion" / character).resolve()
    issues: list[dict[str, Any]] = []
    if manifest.get("version") != 1:
        issue(issues, "error", "unsupported_spec_version", "motion specification version must be 1")
    invalid_definitions = [name for name, value in raw_animations.items() if not isinstance(value, dict)]
    for name in invalid_definitions:
        issue(issues, "error", "invalid_animation", "animation definition must be an object", animation=name)
    animations = {
        name: value for name, value in raw_animations.items() if isinstance(value, dict)
    }
    if not animations:
        issue(issues, "error", "missing_animations", "motion specification has no valid animation definitions")
    validate_directions(manifest, animations, issues)
    profile = validate_gait(manifest, animations, issues)
    pose_labels = manifest.get("gait", {}).get("pose_order", [])
    gait_duration_ms = profile.get("nominal_pose_ms")
    settings = manifest.get("audit") if isinstance(manifest.get("audit"), dict) else {}
    try:
        validate_center_metric(settings)
    except (TypeError, ValueError) as exc:
        print(f"Invalid audit settings: {exc}")
        return 2
    results = [
        audit_animation(
            name, definition, project_root, settings, pose_labels, output_root,
            not args.no_gif, gait_duration_ms, issues,
        )
        for name, definition in animations.items()
        if isinstance(definition, dict)
    ]
    counts = Counter(value["severity"] for value in issues)
    report = {
        "spec_version": manifest.get("version"),
        "character": character,
        "spec": str(spec_path),
        "project_root": str(project_root),
        "motion_profile": profile,
        "summary": {"errors": counts["error"], "warnings": counts["warning"]},
        "issues": issues,
        "animations": results,
    }
    output_root.mkdir(parents=True, exist_ok=True)
    report_path = output_root / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Audited {len(results)} animation(s): {counts['error']} error(s), {counts['warning']} warning(s)")
    print(f"Review artifacts: {output_root}")
    print(f"Report: {report_path}")
    return 1 if counts["error"] or (args.strict and counts["warning"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
