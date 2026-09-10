"""Semantic acceptance gate for directional character-motion overhauls.

This complements the structural sprite-motion audit.  It deliberately refuses to
infer gait semantics from pixel variance: a durable, hash-bound visual review is
required for every direction.  Run ``--prepare-review`` first to create 1x and
half-speed previews, half-cycle comparison sheets, and a review JSON template.

Per-frame normalization policy
------------------------------
Only uniform scale adjustments within 5 percent of authored size are accepted.
The x/y factors may differ by at most 0.5 percentage points to tolerate decimal
rounding.  Larger uniform changes and all anisotropic stretching are source-art
problems and must be re-authored instead of hidden by the build pipeline.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import string
from dataclasses import asdict, dataclass
from datetime import date
from pathlib import Path
from typing import Any, Iterable, Iterator

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
CANONICAL_DIRECTIONS = (
    "north",
    "northeast",
    "east",
    "southeast",
    "south",
    "southwest",
    "west",
    "northwest",
)
REVIEW_FLAGS = (
    "walk_phase_order_valid",
    "alternating_foot_contacts_valid",
    "idle_matches_walk",
    "identity_preserved",
    "asymmetry_preserved",
    "reviewed_at_1x",
    "reviewed_at_half_speed",
)
UNIFORM_SCALE_LIMIT = 0.05
ANISOTROPY_TOLERANCE = 0.005
OPAQUE_ALPHA = 240
VISIBLE_ALPHA = 16
RECTANGULAR_FILL_THRESHOLD = 0.97
RECTANGULAR_FRAME_AREA_THRESHOLD = 0.08
RECTANGULAR_AXIS_THRESHOLD = 0.20
IMAGE_SUFFIXES = {".png", ".gif", ".webp", ".jpg", ".jpeg"}
DISALLOWED_GEOMETRY_KEYS = {
    "width",
    "height",
    "resize_width",
    "resize_height",
    "stretch_x",
    "stretch_y",
    "shear_x",
    "shear_y",
    "rotation",
    "rotate",
}


@dataclass(frozen=True)
class GateIssue:
    code: str
    message: str
    location: str | None = None


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def project_path(project_root: Path, value: str) -> Path:
    candidate = Path(value)
    return candidate.resolve() if candidate.is_absolute() else (project_root / candidate).resolve()


def relative_project_path(project_root: Path, path: Path) -> str:
    return path.resolve().relative_to(project_root.resolve()).as_posix()


def _alpha_rectangle_metrics(frame: Image.Image) -> dict[str, float | list[int]] | None:
    alpha = frame.convert("RGBA").getchannel("A")
    visible = alpha.point(lambda value: 255 if value >= VISIBLE_ALPHA else 0)
    bbox = visible.getbbox()
    if bbox is None:
        return None

    x0, y0, x1, y1 = bbox
    bbox_area = (x1 - x0) * (y1 - y0)
    frame_area = frame.width * frame.height
    if bbox_area <= 0 or frame_area <= 0:
        return None

    bbox_alpha = alpha.crop(bbox)
    histogram = bbox_alpha.histogram()
    opaque_pixels = sum(histogram[OPAQUE_ALPHA:])
    visible_pixels = sum(histogram[VISIBLE_ALPHA:])
    return {
        "bbox": [x0, y0, x1, y1],
        "opaque_fill_ratio": opaque_pixels / bbox_area,
        "visible_fill_ratio": visible_pixels / bbox_area,
        "bbox_frame_area_ratio": bbox_area / frame_area,
        "bbox_width_ratio": (x1 - x0) / frame.width,
        "bbox_height_ratio": (y1 - y0) / frame.height,
    }


def frame_has_opaque_rectangular_matte(frame: Image.Image) -> tuple[bool, dict[str, Any]]:
    """Return whether alpha describes a large, nearly solid rectangular panel.

    This catches both flat mattes and baked checkerboards: color variation does
    not excuse a rectangular region whose alpha is almost entirely opaque.
    """

    metrics = _alpha_rectangle_metrics(frame)
    if metrics is None:
        return False, {}
    suspicious = (
        metrics["opaque_fill_ratio"] >= RECTANGULAR_FILL_THRESHOLD
        and metrics["visible_fill_ratio"] >= RECTANGULAR_FILL_THRESHOLD
        and metrics["bbox_frame_area_ratio"] >= RECTANGULAR_FRAME_AREA_THRESHOLD
        and metrics["bbox_width_ratio"] >= RECTANGULAR_AXIS_THRESHOLD
        and metrics["bbox_height_ratio"] >= RECTANGULAR_AXIS_THRESHOLD
    )
    return bool(suspicious), metrics


def split_animation_frames(animation: dict[str, Any], project_root: Path) -> list[Image.Image]:
    path = project_path(project_root, str(animation["path"]))
    frame_width = int(animation["frame_width"])
    frame_height = int(animation["frame_height"])
    frame_count = int(animation["frame_count"])
    with Image.open(path) as source:
        strip = source.convert("RGBA")
    expected = (frame_width * frame_count, frame_height)
    if strip.size != expected:
        raise ValueError(f"{path}: expected horizontal strip {expected}, found {strip.size}")
    return [
        strip.crop((index * frame_width, 0, (index + 1) * frame_width, frame_height))
        for index in range(frame_count)
    ]


def audit_locomotion_mattes(motion_spec: dict[str, Any], project_root: Path) -> list[GateIssue]:
    issues: list[GateIssue] = []
    animations = motion_spec.get("animations", {})
    if not isinstance(animations, dict):
        return [GateIssue("invalid_motion_spec", "animations must be an object", "animations")]

    for animation_name, animation in animations.items():
        if not isinstance(animation, dict) or animation.get("role") != "gait":
            continue
        try:
            frames = split_animation_frames(animation, project_root)
        except (KeyError, OSError, TypeError, ValueError) as exc:
            issues.append(GateIssue("unreadable_gait_strip", str(exc), f"animations.{animation_name}"))
            continue
        for index, frame in enumerate(frames, start=1):
            suspicious, metrics = frame_has_opaque_rectangular_matte(frame)
            if suspicious:
                issues.append(
                    GateIssue(
                        "opaque_rectangular_matte_or_checkerboard",
                        (
                            f"{animation_name} frame {index} is a nearly solid opaque rectangle "
                            f"(opaque bbox fill {metrics['opaque_fill_ratio']:.3f}, "
                            f"bbox/frame area {metrics['bbox_frame_area_ratio']:.3f}); "
                            "remove the matte or baked checkerboard and re-author if needed"
                        ),
                        f"animations.{animation_name}.frames[{index}]",
                    )
                )
    return issues


def _iter_adjustment_records(value: Any, location: str) -> Iterator[tuple[str, dict[str, Any]]]:
    if isinstance(value, dict):
        transform_keys = {"scale", "scale_x", "scale_y"} | DISALLOWED_GEOMETRY_KEYS
        if transform_keys.intersection(value):
            yield location, value
            return
        for key, child in value.items():
            yield from _iter_adjustment_records(child, f"{location}.{key}" if location else str(key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _iter_adjustment_records(child, f"{location}[{index}]")


def _adjustment_roots(value: Any, location: str = "") -> Iterator[tuple[str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            child_location = f"{location}.{key}" if location else str(key)
            if key in {"frame_adjustments", "output_adjustments"}:
                yield child_location, child
            else:
                yield from _adjustment_roots(child, child_location)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _adjustment_roots(child, f"{location}[{index}]")


def audit_per_frame_geometry(build_manifest: dict[str, Any]) -> list[GateIssue]:
    issues: list[GateIssue] = []
    for root_location, root in _adjustment_roots(build_manifest):
        for location, adjustment in _iter_adjustment_records(root, root_location):
            forbidden = sorted(DISALLOWED_GEOMETRY_KEYS.intersection(adjustment))
            if forbidden:
                issues.append(
                    GateIssue(
                        "dangerous_per_frame_geometry",
                        f"per-frame geometric correction uses forbidden keys: {', '.join(forbidden)}",
                        location,
                    )
                )

            try:
                scalar = float(adjustment.get("scale", 1.0))
                scale_x = scalar * float(adjustment.get("scale_x", 1.0))
                scale_y = scalar * float(adjustment.get("scale_y", 1.0))
            except (TypeError, ValueError):
                issues.append(GateIssue("invalid_per_frame_scale", "scale values must be numeric", location))
                continue
            if not (math.isfinite(scale_x) and math.isfinite(scale_y) and scale_x > 0 and scale_y > 0):
                issues.append(GateIssue("invalid_per_frame_scale", "scale values must be positive and finite", location))
                continue
            if abs(scale_x - scale_y) > ANISOTROPY_TOLERANCE:
                issues.append(
                    GateIssue(
                        "anisotropic_per_frame_scale",
                        (
                            f"per-frame scale ({scale_x:.4f}, {scale_y:.4f}) stretches authored art; "
                            f"x/y may differ by at most {ANISOTROPY_TOLERANCE:.3f}"
                        ),
                        location,
                    )
                )
            if max(abs(scale_x - 1.0), abs(scale_y - 1.0)) > UNIFORM_SCALE_LIMIT + 1e-9:
                issues.append(
                    GateIssue(
                        "excessive_per_frame_scale",
                        (
                            f"per-frame scale ({scale_x:.4f}, {scale_y:.4f}) exceeds the "
                            f"allowed +/-{UNIFORM_SCALE_LIMIT * 100:.0f}% uniform normalization"
                        ),
                        location,
                    )
                )
    return issues


def _build_source_paths(build_manifest: dict[str, Any], project_root: Path) -> tuple[Path, set[Path]]:
    source_root_value = build_manifest.get("source_root")
    if not isinstance(source_root_value, str) or not source_root_value.strip():
        raise ValueError("build manifest requires source_root")
    source_root = project_path(project_root, source_root_value)
    sources: set[Path] = set()

    idle_sets = build_manifest.get("idle_sets", [])
    if isinstance(idle_sets, list):
        for item in idle_sets:
            if isinstance(item, dict) and isinstance(item.get("source"), str):
                sources.add((source_root / item["source"]).resolve())
    walks = build_manifest.get("walks", {})
    if isinstance(walks, dict):
        for item in walks.values():
            if isinstance(item, dict) and isinstance(item.get("source"), str):
                sources.add((source_root / item["source"]).resolve())
    return source_root, sources


def _validate_hash_bound_path(
    reference: Any,
    *,
    project_root: Path,
    character_root: Path,
    location: str,
    require_character_local: bool = True,
) -> tuple[Path | None, list[GateIssue]]:
    issues: list[GateIssue] = []
    if not isinstance(reference, dict):
        return None, [GateIssue("invalid_evidence_reference", "evidence must contain path and sha256", location)]
    path_value = reference.get("path")
    expected_hash = reference.get("sha256")
    if not isinstance(path_value, str) or not path_value.strip():
        issues.append(GateIssue("missing_evidence_path", "evidence path is required", f"{location}.path"))
        return None, issues
    if Path(path_value).is_absolute():
        issues.append(
            GateIssue(
                "non_portable_evidence_path",
                "evidence paths must be project-relative so the review survives moving the workspace",
                f"{location}.path",
            )
        )
    path = project_path(project_root, path_value)
    if require_character_local and not is_within(path, character_root):
        issues.append(
            GateIssue(
                "non_character_local_evidence",
                f"evidence resolves outside {relative_project_path(project_root, character_root)}",
                f"{location}.path",
            )
        )
    if not path.is_file():
        issues.append(GateIssue("missing_evidence_file", f"evidence file does not exist: {path_value}", location))
        return path, issues
    if (
        not isinstance(expected_hash, str)
        or len(expected_hash) != 64
        or any(character not in string.hexdigits for character in expected_hash)
    ):
        issues.append(GateIssue("missing_evidence_hash", "evidence requires a SHA-256 digest", f"{location}.sha256"))
    elif sha256_file(path).lower() != expected_hash.lower():
        issues.append(GateIssue("stale_evidence_hash", f"evidence changed after review: {path_value}", location))
    return path, issues


def validate_prompt_provenance(
    provenance: dict[str, Any],
    *,
    character: str,
    build_manifest: dict[str, Any],
    project_root: Path,
    character_root: Path,
) -> list[GateIssue]:
    issues: list[GateIssue] = []
    if provenance.get("version") != 1:
        issues.append(GateIssue("invalid_provenance_version", "prompt provenance version must be 1", "version"))
    if provenance.get("character") != character:
        issues.append(GateIssue("provenance_character_mismatch", "prompt provenance character does not match", "character"))

    try:
        source_root, required_sources = _build_source_paths(build_manifest, project_root)
    except ValueError as exc:
        return issues + [GateIssue("invalid_build_source_root", str(exc), "source_root")]
    expected_source_root = character_root / "source"
    if not is_within(source_root, expected_source_root):
        issues.append(
            GateIssue(
                "non_character_local_source_art",
                "reviewed source_root must live under the character's output source directory",
                "source_root",
            )
        )

    records = provenance.get("records")
    if not isinstance(records, list) or not records:
        return issues + [GateIssue("missing_prompt_records", "prompt provenance needs at least one record", "records")]

    covered: set[Path] = set()
    seen_ids: set[str] = set()
    for index, record in enumerate(records):
        location = f"records[{index}]"
        if not isinstance(record, dict):
            issues.append(GateIssue("invalid_prompt_record", "prompt record must be an object", location))
            continue
        record_id = record.get("id")
        if not isinstance(record_id, str) or not record_id.strip():
            issues.append(GateIssue("missing_prompt_record_id", "prompt record id is required", f"{location}.id"))
        elif record_id in seen_ids:
            issues.append(GateIssue("duplicate_prompt_record_id", f"duplicate prompt record id: {record_id}", f"{location}.id"))
        else:
            seen_ids.add(record_id)

        capture = record.get("capture")
        if capture not in {"exact", "reconstructed"}:
            issues.append(
                GateIssue(
                    "ambiguous_prompt_capture",
                    "capture must be exactly 'exact' or 'reconstructed'",
                    f"{location}.capture",
                )
            )
        prompt_text = record.get("prompt_text")
        if not isinstance(prompt_text, str) or not prompt_text.strip():
            issues.append(GateIssue("missing_prompt_text", "prompt_text is required", f"{location}.prompt_text"))
        if capture == "exact" and not str(record.get("capture_source", "")).strip():
            issues.append(
                GateIssue(
                    "missing_exact_prompt_source",
                    "exact prompt records require capture_source describing where the exact text came from",
                    f"{location}.capture_source",
                )
            )
        if capture == "reconstructed":
            if not str(record.get("reconstruction_notes", "")).strip():
                issues.append(
                    GateIssue(
                        "missing_reconstruction_notes",
                        "reconstructed prompts require reconstruction_notes",
                        f"{location}.reconstruction_notes",
                    )
                )
            false_verbatim = any(
                record.get(key) is True for key in ("verbatim", "is_verbatim", "exact_prompt")
            )
            label = str(record.get("label", "")).lower()
            if false_verbatim or "verbatim" in label or "exact prompt" in label:
                issues.append(
                    GateIssue(
                        "reconstructed_prompt_claimed_verbatim",
                        "a reconstructed prompt may not be labelled exact or verbatim",
                        location,
                    )
                )

        artifacts = record.get("artifacts")
        if not isinstance(artifacts, list) or not artifacts:
            issues.append(GateIssue("missing_prompt_artifacts", "prompt record needs generated artifacts", f"{location}.artifacts"))
            continue
        for artifact_index, reference in enumerate(artifacts):
            artifact_location = f"{location}.artifacts[{artifact_index}]"
            path, path_issues = _validate_hash_bound_path(
                reference,
                project_root=project_root,
                character_root=expected_source_root,
                location=artifact_location,
            )
            issues.extend(path_issues)
            if path is not None:
                covered.add(path.resolve())

    for required in sorted(required_sources):
        if required.resolve() not in covered:
            try:
                label = relative_project_path(project_root, required)
            except ValueError:
                label = str(required)
            issues.append(
                GateIssue(
                    "build_source_without_prompt_provenance",
                    f"reviewed build source has no prompt record: {label}",
                    "records",
                )
            )
    return issues


def _checkerboard(size: tuple[int, int], square: int = 12) -> Image.Image:
    image = Image.new("RGBA", size, (48, 51, 58, 255))
    draw = ImageDraw.Draw(image)
    light = (70, 74, 82, 255)
    for y in range(0, size[1], square):
        for x in range(0, size[0], square):
            if (x // square + y // square) % 2:
                draw.rectangle((x, y, min(x + square - 1, size[0] - 1), min(y + square - 1, size[1] - 1)), fill=light)
    return image


def _composited_preview_frames(frames: Iterable[Image.Image]) -> list[Image.Image]:
    rendered: list[Image.Image] = []
    for frame in frames:
        background = _checkerboard(frame.size)
        background.alpha_composite(frame.convert("RGBA"))
        rendered.append(background.convert("P", palette=Image.Palette.ADAPTIVE))
    return rendered


def render_walk_previews(frames: list[Image.Image], fps: float, one_x: Path, half_speed: Path) -> None:
    if not math.isfinite(fps) or fps <= 0:
        raise ValueError("walk fps must be positive and finite")
    rendered = _composited_preview_frames(frames)
    one_x.parent.mkdir(parents=True, exist_ok=True)
    half_speed.parent.mkdir(parents=True, exist_ok=True)
    duration = max(20, round(1000 / fps))
    rendered[0].save(one_x, save_all=True, append_images=rendered[1:], duration=duration, loop=0, disposal=2)
    rendered[0].save(
        half_speed,
        save_all=True,
        append_images=rendered[1:],
        duration=duration * 2,
        loop=0,
        disposal=2,
    )


def render_half_cycle_sheet(
    frames: list[Image.Image], pose_order: list[str], destination: Path, display_size: int = 192
) -> None:
    if len(frames) != 8 or len(pose_order) != 8:
        raise ValueError("half-cycle comparison requires exactly eight gait frames and pose labels")
    label_width = 168
    row_height = display_size + 30
    sheet = Image.new("RGBA", (label_width + display_size * 2, row_height * 4), (24, 27, 32, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for row in range(4):
        opposite = row + 4
        draw.text((8, row * row_height + 8), f"{row + 1}: {pose_order[row]}", font=font, fill=(235, 238, 242, 255))
        draw.text((8, row * row_height + 23), f"{opposite + 1}: {pose_order[opposite]}", font=font, fill=(170, 178, 188, 255))
        for column, frame_index in enumerate((row, opposite)):
            backdrop = _checkerboard((display_size, display_size), square=8)
            preview = frames[frame_index].copy()
            preview.thumbnail((display_size, display_size), Image.Resampling.LANCZOS)
            x = (display_size - preview.width) // 2
            y = (display_size - preview.height) // 2
            backdrop.alpha_composite(preview, (x, y))
            sheet.alpha_composite(backdrop, (label_width + column * display_size, row * row_height + 30))
            draw.text(
                (label_width + column * display_size + 5, row * row_height + 7),
                f"frame {frame_index + 1}",
                font=font,
                fill=(235, 238, 242, 255),
            )
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(destination, quality=94)


def evidence_reference(project_root: Path, path: Path) -> dict[str, str]:
    return {
        "path": relative_project_path(project_root, path),
        "sha256": sha256_file(path) if path.is_file() else "",
    }


def expected_review_artifacts(
    motion_spec: dict[str, Any], project_root: Path, character_root: Path
) -> dict[str, dict[str, Path]]:
    artifacts: dict[str, dict[str, Path]] = {}
    directions = motion_spec.get("directions", {})
    for direction in CANONICAL_DIRECTIONS:
        mapping = directions.get(direction, {}) if isinstance(directions, dict) else {}
        walk = str(mapping.get("walk_animation", f"walk_{direction}"))
        idle = str(mapping.get("idle_animation", f"idle_{direction}"))
        artifacts[direction] = {
            "walk_contact_sheet": character_root / "audit" / "contact-sheets" / f"{walk}.png",
            "idle_contact_sheet": character_root / "audit" / "contact-sheets" / f"{idle}.png",
            "preview_1x": character_root / "semantic-review" / "previews-1x" / f"{walk}.gif",
            "preview_half_speed": character_root / "semantic-review" / "previews-half-speed" / f"{walk}.gif",
            "half_cycle_sheet": character_root / "semantic-review" / "half-cycle-sheets" / f"{walk}.png",
        }
    return artifacts


def prepare_review_artifacts(
    motion_spec: dict[str, Any], project_root: Path, character_root: Path
) -> tuple[Path, list[GateIssue]]:
    issues: list[GateIssue] = []
    animations = motion_spec.get("animations", {})
    pose_order = motion_spec.get("gait", {}).get("pose_order", [])
    expected = expected_review_artifacts(motion_spec, project_root, character_root)
    rendered_walks: set[str] = set()
    for direction in CANONICAL_DIRECTIONS:
        mapping = motion_spec.get("directions", {}).get(direction, {})
        walk = mapping.get("walk_animation")
        if not isinstance(walk, str) or walk in rendered_walks:
            continue
        animation = animations.get(walk)
        if not isinstance(animation, dict):
            issues.append(GateIssue("missing_walk_animation", f"missing animation {walk}", f"directions.{direction}"))
            continue
        try:
            frames = split_animation_frames(animation, project_root)
            paths = expected[direction]
            render_walk_previews(frames, float(animation.get("fps", 0)), paths["preview_1x"], paths["preview_half_speed"])
            render_half_cycle_sheet(frames, list(pose_order), paths["half_cycle_sheet"])
            rendered_walks.add(walk)
        except (KeyError, OSError, TypeError, ValueError) as exc:
            issues.append(GateIssue("review_artifact_generation_failed", str(exc), f"animations.{walk}"))

    template = {
        "version": 1,
        "character": motion_spec.get("character"),
        "status": "pending",
        "reviewer": "",
        "reviewed_on": "",
        "overall_notes": "",
        "directions": {},
        "reports": {
            "motion_audit": evidence_reference(project_root, character_root / "audit" / "report.json"),
            "sprite_doctor": evidence_reference(project_root, character_root / "sprite-doctor" / "report.json"),
        },
    }
    for direction in CANONICAL_DIRECTIONS:
        mapping = motion_spec.get("directions", {}).get(direction, {})
        entry: dict[str, Any] = {
            "walk_animation": mapping.get("walk_animation"),
            "idle_animation": mapping.get("idle_animation"),
            **{flag: False for flag in REVIEW_FLAGS},
            "notes": "",
            "evidence": {
                key: evidence_reference(project_root, path)
                for key, path in expected[direction].items()
            },
        }
        template["directions"][direction] = entry

    template_path = character_root / "semantic-review-template.json"
    template_path.parent.mkdir(parents=True, exist_ok=True)
    template_path.write_text(json.dumps(template, indent=2) + "\n", encoding="utf-8")
    return template_path, issues


def _validate_clean_reports(report_paths: dict[str, Path]) -> list[GateIssue]:
    issues: list[GateIssue] = []
    motion_path = report_paths.get("motion_audit")
    if motion_path and motion_path.is_file():
        try:
            motion = load_json(motion_path)
            summary = motion.get("summary", {})
            if summary.get("errors") != 0 or summary.get("warnings") != 0:
                issues.append(
                    GateIssue(
                        "motion_audit_not_strictly_clean",
                        "motion audit must report exactly 0 errors and 0 warnings",
                        "reports.motion_audit",
                    )
                )
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            issues.append(GateIssue("invalid_motion_audit_report", str(exc), "reports.motion_audit"))
    sprite_path = report_paths.get("sprite_doctor")
    if sprite_path and sprite_path.is_file():
        try:
            sprite = load_json(sprite_path)
            if sprite.get("summary", {}).get("errors") != 0:
                issues.append(GateIssue("sprite_doctor_errors", "sprite doctor report contains errors", "reports.sprite_doctor"))
            for item in sprite.get("issues", []):
                if not isinstance(item, dict) or item.get("severity") not in {"error", "warning"}:
                    continue
                action = str(item.get("action", ""))
                if action == "idle" or action == "walk" or action.startswith("idle_") or action.startswith("walk_"):
                    issues.append(
                        GateIssue(
                            "sprite_doctor_locomotion_issue",
                            f"sprite doctor {item.get('severity')} for {action}: {item.get('code', 'unknown')}",
                            "reports.sprite_doctor",
                        )
                    )
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            issues.append(GateIssue("invalid_sprite_doctor_report", str(exc), "reports.sprite_doctor"))
    return issues


def validate_manual_review(
    review: dict[str, Any],
    *,
    motion_spec: dict[str, Any],
    project_root: Path,
    character_root: Path,
) -> list[GateIssue]:
    issues: list[GateIssue] = []
    character = str(motion_spec.get("character", ""))
    if review.get("version") != 1:
        issues.append(GateIssue("invalid_review_version", "semantic review version must be 1", "version"))
    if review.get("character") != character:
        issues.append(GateIssue("review_character_mismatch", "semantic review character does not match", "character"))
    if review.get("status") != "accepted":
        issues.append(GateIssue("review_not_accepted", "semantic review status must be 'accepted'", "status"))
    if not str(review.get("reviewer", "")).strip():
        issues.append(GateIssue("missing_reviewer", "semantic review requires a reviewer", "reviewer"))
    try:
        date.fromisoformat(str(review.get("reviewed_on", "")))
    except ValueError:
        issues.append(GateIssue("invalid_review_date", "reviewed_on must use YYYY-MM-DD", "reviewed_on"))
    if not str(review.get("overall_notes", "")).strip():
        issues.append(GateIssue("missing_overall_review_notes", "overall_notes must record the review conclusion", "overall_notes"))

    expected_artifacts = expected_review_artifacts(motion_spec, project_root, character_root)
    directions = review.get("directions")
    if not isinstance(directions, dict):
        return issues + [GateIssue("missing_direction_reviews", "directions must be an object", "directions")]

    spec_directions = motion_spec.get("directions", {})
    for direction in CANONICAL_DIRECTIONS:
        location = f"directions.{direction}"
        entry = directions.get(direction)
        if not isinstance(entry, dict):
            issues.append(GateIssue("missing_direction_review", f"missing review for {direction}", location))
            continue
        mapping = spec_directions.get(direction, {}) if isinstance(spec_directions, dict) else {}
        for animation_key in ("walk_animation", "idle_animation"):
            if entry.get(animation_key) != mapping.get(animation_key):
                issues.append(
                    GateIssue(
                        "review_animation_mismatch",
                        f"{animation_key} does not match the motion spec",
                        f"{location}.{animation_key}",
                    )
                )
        for flag in REVIEW_FLAGS:
            if entry.get(flag) is not True:
                issues.append(GateIssue("semantic_review_flag_not_accepted", f"{flag} must be true", f"{location}.{flag}"))
        if not str(entry.get("notes", "")).strip():
            issues.append(GateIssue("missing_direction_review_notes", "direction review notes are required", f"{location}.notes"))

        evidence = entry.get("evidence")
        if not isinstance(evidence, dict):
            issues.append(GateIssue("missing_direction_evidence", "direction evidence is required", f"{location}.evidence"))
            continue
        for key, expected_path in expected_artifacts[direction].items():
            path, path_issues = _validate_hash_bound_path(
                evidence.get(key),
                project_root=project_root,
                character_root=character_root,
                location=f"{location}.evidence.{key}",
            )
            issues.extend(path_issues)
            if path is not None and path.resolve() != expected_path.resolve():
                issues.append(
                    GateIssue(
                        "wrong_direction_evidence",
                        f"{key} must reference {relative_project_path(project_root, expected_path)}",
                        f"{location}.evidence.{key}.path",
                    )
                )

    reports = review.get("reports")
    report_paths: dict[str, Path] = {}
    if not isinstance(reports, dict):
        issues.append(GateIssue("missing_review_reports", "review requires motion_audit and sprite_doctor reports", "reports"))
    else:
        expected_reports = {
            "motion_audit": character_root / "audit" / "report.json",
            "sprite_doctor": character_root / "sprite-doctor" / "report.json",
        }
        for key, expected_path in expected_reports.items():
            path, path_issues = _validate_hash_bound_path(
                reports.get(key),
                project_root=project_root,
                character_root=character_root,
                location=f"reports.{key}",
            )
            issues.extend(path_issues)
            if path is not None:
                report_paths[key] = path
                if path.resolve() != expected_path.resolve():
                    issues.append(
                        GateIssue(
                            "wrong_review_report",
                            f"{key} must reference {relative_project_path(project_root, expected_path)}",
                            f"reports.{key}.path",
                        )
                    )
    issues.extend(_validate_clean_reports(report_paths))
    return issues


def run_gate(
    *,
    motion_spec_path: Path,
    build_manifest_path: Path,
    review_path: Path,
    provenance_path: Path,
    project_root: Path,
    prepare_review: bool = False,
) -> dict[str, Any]:
    motion_spec = load_json(motion_spec_path)
    build_manifest = load_json(build_manifest_path)
    character = str(motion_spec.get("character", ""))
    character_root = project_root / "output" / "character-motion" / character
    issues: list[GateIssue] = []
    if not character:
        issues.append(GateIssue("missing_character", "motion spec requires character", "character"))
    if build_manifest.get("character") != character:
        issues.append(GateIssue("build_character_mismatch", "build manifest character does not match", "character"))

    if not is_within(review_path, character_root):
        issues.append(
            GateIssue(
                "non_character_local_review",
                "semantic-review.json must live beneath the character's output directory",
                str(review_path),
            )
        )
    if not is_within(provenance_path, character_root / "source"):
        issues.append(
            GateIssue(
                "non_character_local_provenance",
                "prompt-provenance.json must live beneath the character's source directory",
                str(provenance_path),
            )
        )

    issues.extend(audit_locomotion_mattes(motion_spec, project_root))
    issues.extend(audit_per_frame_geometry(build_manifest))

    template_path: Path | None = None
    if prepare_review:
        template_path, generation_issues = prepare_review_artifacts(motion_spec, project_root, character_root)
        issues.extend(generation_issues)
    else:
        try:
            provenance = load_json(provenance_path)
            issues.extend(
                validate_prompt_provenance(
                    provenance,
                    character=character,
                    build_manifest=build_manifest,
                    project_root=project_root,
                    character_root=character_root,
                )
            )
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            issues.append(GateIssue("missing_or_invalid_prompt_provenance", str(exc), str(provenance_path)))
        try:
            review = load_json(review_path)
            issues.extend(
                validate_manual_review(
                    review,
                    motion_spec=motion_spec,
                    project_root=project_root,
                    character_root=character_root,
                )
            )
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            issues.append(GateIssue("missing_or_invalid_semantic_review", str(exc), str(review_path)))

    return {
        "version": 1,
        "character": character,
        "status": "accepted" if not issues and not prepare_review else ("prepared" if not issues else "rejected"),
        "mode": "prepare-review" if prepare_review else "acceptance",
        "policy": {
            "maximum_uniform_per_frame_scale_delta": UNIFORM_SCALE_LIMIT,
            "maximum_per_frame_scale_axis_difference": ANISOTROPY_TOLERANCE,
            "opaque_rectangular_bbox_fill_threshold": RECTANGULAR_FILL_THRESHOLD,
        },
        "summary": {"errors": len(issues)},
        "issues": [asdict(issue) for issue in issues],
        "review_template": (
            relative_project_path(project_root, template_path) if template_path is not None else None
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("motion_spec", type=Path)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--build-manifest", type=Path)
    parser.add_argument("--review", type=Path)
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--prepare-review", action="store_true")
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    motion_spec_path = project_path(project_root, str(args.motion_spec))
    motion_spec = load_json(motion_spec_path)
    character = str(motion_spec.get("character", ""))
    character_root = project_root / "output" / "character-motion" / character
    build_manifest_path = (
        project_path(project_root, str(args.build_manifest))
        if args.build_manifest
        else project_root / "character-motion" / f"{character}-build.json"
    )
    review_path = (
        project_path(project_root, str(args.review))
        if args.review
        else character_root / "semantic-review.json"
    )
    provenance_path = (
        project_path(project_root, str(args.provenance))
        if args.provenance
        else character_root / "source" / "prompt-provenance.json"
    )
    report_path = (
        project_path(project_root, str(args.report))
        if args.report
        else character_root / "acceptance-gate" / "report.json"
    )
    if not is_within(report_path, character_root):
        parser.error("--report must resolve inside output/character-motion/<character>")

    report = run_gate(
        motion_spec_path=motion_spec_path,
        build_manifest_path=build_manifest_path,
        review_path=review_path,
        provenance_path=provenance_path,
        project_root=project_root,
        prepare_review=args.prepare_review,
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for issue in report["issues"]:
        location = f" [{issue['location']}]" if issue.get("location") else ""
        print(f"FAIL {issue['code']}{location}: {issue['message']}")
    print(f"Character motion acceptance gate: {report['status']} ({report['summary']['errors']} errors)")
    print(f"Report: {report_path}")
    return 0 if report["status"] in {"accepted", "prepared"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
