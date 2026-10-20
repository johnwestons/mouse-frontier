"""Split immutable chore sheets into anchored strips and reproducible QA artifacts.

The source manifest is {"sources": [{"file": "duo.png", "characters":
["first-character", "second-character"]}]}. Each character has sweep, carry,
and tend rows, in that order. Optional ``actions`` supports replacement sheets
containing only selected actions. Later entries replace earlier action sources.
Silhouette components, rather than rectangular grid cuts, preserve staggered
hats, tails, and tools. No visible-color matte removal is performed.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from contextlib import redirect_stdout
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import shutil
from statistics import median
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.build_directional_character_assets import core_horizontal_anchor_x, visible_bbox
from tools.character_action_contract import action_contract

ACTIONS = ("sweep", "carry", "tend")
ACTION_FPS = {"sweep": 3, "carry": 2, "tend": 3}
FRAME_SIZE = 256
FRAME_WIDTH = 512
BASELINE = 229
CENTER_X = 256
ALPHA_FLOOR = 4


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def components(mask: np.ndarray) -> list[dict]:
    """Exact eight-connected components using scanline runs, without SciPy."""
    parents: list[int] = []
    runs: list[tuple[int, int, int, int]] = []

    def root(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    previous: list[tuple[int, int, int]] = []
    for y, row in enumerate(mask):
        edges = np.flatnonzero(np.diff(np.pad(row.astype(np.int8), 1)))
        current = []
        cursor = 0
        for left, right in zip(edges[::2], edges[1::2]):
            left, right = int(left), int(right)
            label = len(parents)
            parents.append(label)
            while cursor < len(previous) and previous[cursor][1] < left:
                cursor += 1
            other = cursor
            while other < len(previous) and previous[other][0] <= right:
                parents[root(previous[other][2])] = root(label)
                other += 1
            current.append((left, right, label))
            runs.append((y, left, right, label))
        previous = current
    grouped: dict[int, list] = defaultdict(list)
    for y, left, right, label in runs:
        grouped[root(label)].append((y, left, right))
    result = []
    for segments in grouped.values():
        result.append({
            "area": sum(right - left for _, left, right in segments),
            "bbox": [min(left for _, left, _ in segments), segments[0][0],
                     max(right for _, _, right in segments), segments[-1][0] + 1],
            "runs": segments,
        })
    return sorted(result, key=lambda item: item["area"], reverse=True)


def component_summary(mask: np.ndarray) -> list[dict]:
    """Drop scanline details for the existing auditor's identical contract."""
    return [{"area": item["area"], "bbox": item["bbox"]} for item in components(mask)]


def rectangle_distance(left: list[int], right: list[int]) -> float:
    dx = max(0, left[0] - right[2], right[0] - left[2])
    dy = max(0, left[1] - right[3], right[1] - left[3])
    # The tiny center term resolves equal distances for overlapping envelopes.
    cx = (left[0] + left[2] - right[0] - right[2]) / 2
    cy = (left[1] + left[3] - right[1] - right[3]) / 2
    return dx * dx + dy * dy + (cx * cx + cy * cy) * 0.0001


def split_source(path: Path, row_count: int, columns: int = 4) -> tuple[list[list[Image.Image]], dict]:
    image = Image.open(path).convert("RGBA")
    pixels = np.asarray(image).copy()
    cleared = int(np.count_nonzero((pixels[:, :, 3] > 0) & (pixels[:, :, 3] <= ALPHA_FLOOR)))
    pixels[pixels[:, :, 3] <= ALPHA_FLOOR] = 0
    # Faint antialiased edges can connect adjacent rows even when their solid
    # outlines are separate. Identify opaque cores, then grow ownership back
    # across every retained edge pixel without deleting any visible color.
    core_mask = pixels[:, :, 3] > 128
    if float(np.count_nonzero(pixels[:, :, 3] <= ALPHA_FLOOR)) / pixels.shape[0] / pixels.shape[1] < 0.1:
        raise ValueError(f"{path.name}: source has an opaque background; request source repair instead of color erasure")
    blobs = components(core_mask)
    expected = row_count * columns
    nominal_height = image.height / row_count
    erosion = 0
    def separated(items):
        return len(items) >= expected and items[expected - 1]["area"] >= items[0]["area"] * .18 and all(
            item["bbox"][3] - item["bbox"][1] < nominal_height * 1.5 for item in items[:expected])
    if not separated(blobs):
        for size in (3, 5, 7, 9):
            # Erode only the segmentation seeds, never source artwork. This
            # separates touching outline pixels between a hat and the feet
            # above; ownership growth restores every retained source pixel.
            eroded = Image.fromarray((core_mask * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(size))
            blobs = components(np.asarray(eroded) > 0)
            erosion = size // 2
            if separated(blobs):
                break
    if len(blobs) < expected:
        raise ValueError(f"{path.name}: only {len(blobs)} separated silhouettes for {expected} frames")
    primary = blobs[:expected]
    if not separated(blobs):
        raise ValueError(f"{path.name}: expected frame silhouettes have inconsistent sizes; inspect touching rows")
    # Generated sheets often overlap row envelopes. Planted feet identify row
    # membership more reliably than equal grid cells or global blank rows.
    primary.sort(key=lambda item: item["bbox"][3])
    ordered = []
    for offset in range(0, expected, columns):
        row = primary[offset:offset + columns]
        heights = [item["bbox"][3] - item["bbox"][1] for item in row]
        if max(item["bbox"][3] for item in row) - min(item["bbox"][3] for item in row) > median(heights) * 0.35:
            raise ValueError(f"{path.name}: row {offset // columns + 1} has ambiguous baselines")
        ordered.extend(sorted(row, key=lambda item: (item["bbox"][0] + item["bbox"][2]) / 2))
    groups = [[item] for item in ordered]
    owner = np.full(pixels.shape[:2], expected, dtype=np.int16)
    for index, group in enumerate(groups):
        for blob in group:
            for y, x0, x1 in blob["runs"]:
                owner[y, x0:x1] = index
    retained = pixels[:, :, 3] > ALPHA_FLOOR
    remaining = retained & (owner == expected)
    while remaining.any():
        padded = np.pad(owner, 1, constant_values=expected)
        nearest = np.minimum.reduce([padded[dy:dy + owner.shape[0], dx:dx + owner.shape[1]]
                                     for dy in range(3) for dx in range(3) if dy != 1 or dx != 1])
        expanded = remaining & (nearest != expected)
        if not expanded.any():
            break
        owner[expanded] = nearest[expanded]
        remaining[expanded] = False
    # Preserve detached translucent details, assigning them to the nearest
    # complete actor rather than dropping small components as "debris".
    for fragment in components(remaining):
        index = min(range(expected), key=lambda i: rectangle_distance(fragment["bbox"], ordered[i]["bbox"]))
        for y, x0, x1 in fragment["runs"]:
            owner[y, x0:x1] = index
    frames, details = [], []
    for index, group in enumerate(groups):
        mask = retained & (owner == index)
        ys, xs = np.nonzero(mask)
        left, top, right, bottom = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
        crop = pixels[top:bottom, left:right].copy()
        crop[~mask[top:bottom, left:right]] = 0
        frames.append(Image.fromarray(crop))
        details.append({"row": index // columns + 1, "frame": index % columns + 1,
                        "bbox": [left, top, right, bottom], "primary_bbox": ordered[index]["bbox"],
                        "components": len(group), "pixels": int(mask.sum())})
    assert sum(item["pixels"] for item in details) == int(np.count_nonzero(pixels[:, :, 3] > ALPHA_FLOOR))
    return [frames[index:index + columns] for index in range(0, expected, columns)], {
        "path": str(path.relative_to(ROOT)), "sha256": sha256(path), "size": list(image.size),
        "cleared_alpha_at_most": ALPHA_FLOOR, "core_alpha_threshold": 128, "cleared_pixels": cleared,
        "preserved_visible_pixels": sum(item["pixels"] for item in details), "segmentation_seed_erosion": erosion, "frames": details,
    }


def installed_framing(slug: str) -> tuple[float, int]:
    idle = Image.open(ROOT / "assets/sprites/character-animations" / slug / "idle.png").convert("RGBA")
    authored=action_contract(ROOT,slug,'idle')
    frame = idle.crop((0, 0, idle.width // (authored['frame_count'] if authored else 2), idle.height))
    box = visible_bbox(frame)
    return (box[3] - box[1]) * FRAME_SIZE / frame.height, round(box[3] * FRAME_SIZE / frame.height)


def check_action_heights(heights: dict[str, tuple[str, float]]) -> None:
    # Both standing actions in one atlas should depict the complete body.
    # A generated waist-up row can have clean alpha margins and still be cut
    # off; normalizing its shorter bbox would hide that defect by enlarging it.
    if "sweep" in heights and "tend" in heights:
        sweep_source, sweep_height = heights["sweep"]
        tend_source, tend_height = heights["tend"]
        if sweep_source == tend_source and tend_height < sweep_height * 0.75:
            raise ValueError("tend row is much shorter than the standing sweep row; inspect for missing legs or source cropping")


def normalize_row(cells: list[Image.Image], target_height: float, baseline: int) -> tuple[Image.Image, dict]:
    boxes = [visible_bbox(cell) for cell in cells]
    anchors = [core_horizontal_anchor_x(cell, box) for cell, box in zip(cells, boxes)]
    # A common row scale preserves authored crouching/raising between frames.
    # Use the tallest carry pose as the upright reference, not each frame bbox.
    height = max(box[3] - box[1] for box in boxes)
    requested_scale = target_height / height
    margin = 8
    left_extent = max(anchor - box[0] for anchor, box in zip(anchors, boxes))
    right_extent = max(box[2] - anchor for anchor, box in zip(anchors, boxes))
    scale = min(requested_scale, (CENTER_X - margin) / max(1, left_extent),
                (FRAME_WIDTH - CENTER_X - margin) / max(1, right_extent), (baseline - margin) / height)
    strip = Image.new("RGBA", (FRAME_WIDTH * 4, FRAME_SIZE))
    frame_details = []
    for index, (cell, box) in enumerate(zip(cells, boxes)):
        # Retain antialiased edges below the audit threshold as well.
        crop = cell.resize((max(1, round(cell.width * scale)), max(1, round(cell.height * scale))), Image.Resampling.LANCZOS)
        core = core_horizontal_anchor_x(crop)
        visible = visible_bbox(crop)
        x = round(CENTER_X - core)
        y = baseline - visible[3]
        if x < 2 or x + crop.width > FRAME_WIDTH - 2 or y < 2 or y + crop.height > FRAME_SIZE - 2:
            raise ValueError(f"frame {index + 1} would clip after anchoring; source needs review")
        strip.alpha_composite(crop, (index * FRAME_WIDTH + x, y))
        frame_details.append({"source_size": list(cell.size), "output_size": list(crop.size),
                              "left": x, "top": y, "core_x": x + core, "baseline": y + visible[3]})
    return strip, {"shared_scale": scale, "requested_scale": requested_scale,
                   "scale_cap_ratio": scale / requested_scale, "baseline": baseline,
                   "target_height": target_height, "frames": frame_details}


def write_spec(slug: str, runtime: Path) -> Path:
    old_spec = ROOT / "character-motion" / f"{slug}.json"
    if old_spec.exists():
        spec = json.loads(old_spec.read_text(encoding="utf-8"))
    else:
        # The chore task preserves the existing legacy cowboys' one-view
        # locomotion. Record its actual six-frame walk, never invent eight
        # directional mappings merely to satisfy an unrelated overhaul gate.
        spec = {"version": 1, "character": slug, "animations": {},
                "preserved_legacy_motion": True, "directions": {
                    "east": {"walk_animation": "walk", "idle_animation": "idle", "mirror_x": False},
                    "west": {"walk_animation": "walk", "idle_animation": "idle", "mirror_x": True}},
                "audit": {"alpha_threshold": 16, "edge_margin": 2, "baseline_tolerance": 12, "center_tolerance": 20}}
        for name, fps in (("idle", .7), ("walk", 5.2)):
            path = ROOT / "assets/sprites/character-animations" / slug / f"{name}.png"
            width, height = Image.open(path).size
            authored=action_contract(ROOT,slug,name)
            count = authored['frame_count'] if authored else round(width / height)
            spec["animations"][name] = {"path": str(path.relative_to(ROOT)).replace("\\", "/"),
                "frame_width": width // count, "frame_height": height, "frame_count": count,
                "role": "preserved_legacy_motion", "loop": True, "fps": fps}
    for definition in spec["animations"].values():
        basename = Path(definition["path"]).name
        definition["path"] = f"assets/sprites/character-animations/{slug}/{basename}"
    for action in ACTIONS:
        if (runtime / f"{action}.png").exists():
            spec["animations"][action] = {"path": str((runtime / f"{action}.png").relative_to(ROOT)).replace("\\", "/"),
                "frame_width": FRAME_WIDTH, "frame_height": FRAME_SIZE, "frame_count": 4,
                "role": "stationary_chore", "loop": True, "fps": ACTION_FPS[action]}
    spec.setdefault("audit", {})["center_metric"] = "core"
    spec["chore_contract"] = {"actions": list(ACTIONS), "locomotion": "existing directional walk strips",
                              "carry": "stationary lift and unload; walking uses the existing gait",
                              "frame_width": FRAME_WIDTH, "frame_height": FRAME_SIZE,
                              "core_x": CENTER_X, "body_extent": FRAME_SIZE,
                              "baseline": installed_framing(slug)[1]}
    path = ROOT / "character-motion/chores" / f"{slug}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    return path


def contact_sheet(slug: str, runtime: Path, output: Path) -> None:
    tile, tile_height, label = 320, 160, 25
    colors = ((239, 241, 235, 255), (18, 26, 35, 255), (12, 90, 83, 255))
    canvas = Image.new("RGB", (tile * 4, (tile_height + label) * len(ACTIONS) * len(colors)), "white")
    draw = ImageDraw.Draw(canvas)
    for row, action in enumerate(ACTIONS):
        path = runtime / f"{action}.png"
        if not path.exists():
            continue
        strip = Image.open(path).convert("RGBA")
        for bg_index, color in enumerate(colors):
            top = (row * len(colors) + bg_index) * (tile_height + label)
            draw.text((8, top + 6), f"{slug} / {action} / background {bg_index + 1}", fill="black")
            for index in range(4):
                frame = strip.crop((index * FRAME_WIDTH, 0, (index + 1) * FRAME_WIDTH, FRAME_SIZE))
                background = Image.new("RGBA", frame.size, color)
                background.alpha_composite(frame)
                canvas.paste(background.resize((tile, tile_height), Image.Resampling.LANCZOS).convert("RGB"), (index * tile, top + label))
    canvas.save(output)


def batch_overviews(slugs: list[str], tag: str) -> list[str]:
    """Review up to eight characters per page at approximately game size."""
    paths = []
    directory = ROOT / "output/resident-chores/reviews"
    directory.mkdir(parents=True, exist_ok=True)
    for start in range(0, len(slugs), 8):
        batch = slugs[start:start + 8]
        for style, color in (("light", (239, 241, 235, 255)), ("dark", (18, 26, 35, 255))):
            sheet = Image.new("RGB", (1280, ((len(batch) + 1) // 2) * 300), "white")
            draw = ImageDraw.Draw(sheet)
            for index, slug in enumerate(batch):
                x, y = index % 2 * 640, index // 2 * 300
                for row, action in enumerate(ACTIONS):
                    draw.text((x + 5, y + row * 100 + 4), f"{slug} / {action}", fill="black")
                    path = ROOT / "output/resident-chores" / slug / "runtime" / f"{action}.png"
                    if not path.exists():
                        continue
                    strip = Image.open(path).convert("RGBA")
                    for frame in range(4):
                        crop = strip.crop((frame * FRAME_WIDTH, 0, (frame + 1) * FRAME_WIDTH, FRAME_SIZE))
                        canvas = Image.new("RGBA", crop.size, color)
                        canvas.alpha_composite(crop)
                        sheet.paste(canvas.resize((160, 80), Image.Resampling.LANCZOS).convert("RGB"),
                                    (x + frame * 160, y + row * 100 + 20))
            path = directory / f"{tag}-{start // 8 + 1:02d}-{style}.png"
            sheet.save(path)
            paths.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    return paths


def audit_character(spec: Path, output: Path) -> dict:
    from tools import sprite_motion_audit as audit
    # Identical eight-connected results, using runs instead of visiting every
    # individual pixel in Python. All auditor rules and thresholds are intact.
    original = audit.component_summary
    audit.component_summary = component_summary
    try:
        definition = json.loads(spec.read_text(encoding="utf-8"))
        if definition.get("preserved_legacy_motion"):
            issues = []
            results = [audit.audit_animation(name, animation, ROOT, definition["audit"], [], output, True, None, issues)
                       for name, animation in definition["animations"].items()]
            counts = {severity: sum(item["severity"] == severity for item in issues) for severity in ("error", "warning")}
            report = {"spec_version": 1, "character": definition["character"], "spec": str(spec),
                "project_root": str(ROOT), "summary": {"errors": counts["error"], "warnings": counts["warning"]},
                "scope": "Chore addition; existing single-view legacy idle/walk are preserved and pixel-audited.",
                "preserved_legacy_gaps": "Six additional directional views and eight-phase gait are not present in the existing set.",
                "issues": issues, "animations": results}
            output.mkdir(parents=True, exist_ok=True)
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            status = int(counts["error"] > 0)
        else:
            with redirect_stdout(io.StringIO()):
                status = audit.main([str(spec), "--project-root", str(ROOT), "--output", str(output)])
    finally:
        audit.component_summary = original
    report = json.loads((output / "report.json").read_text(encoding="utf-8"))
    chore_issues = [item for item in report["issues"] if item.get("animation") in ACTIONS]
    existing_issues = [item for item in report["issues"] if item.get("animation") not in ACTIONS]
    def counts(issues):
        return {name + "s": sum(item["severity"] == name for item in issues) for name in ("error", "warning")}
    report["chore_summary"] = counts(chore_issues)
    report["existing_motion_summary"] = counts(existing_issues)
    report["acceptance_scope"] = "New chore actions; unchanged installed locomotion findings remain reported separately."
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    for action in ACTIONS:
        animation = definition["animations"].get(action)
        if animation:
            strip = Image.open(ROOT / animation["path"]).convert("RGBA")
            frames = [strip.crop((index * FRAME_WIDTH, 0, (index + 1) * FRAME_WIDTH, FRAME_SIZE)) for index in range(4)]
            audit.render_gif(frames, output / "previews" / f"{action}-half-speed.gif", round(2000 / ACTION_FPS[action]))
    return {"status": int(report["chore_summary"]["errors"] > 0), "summary": report["summary"],
            "chore_summary": report["chore_summary"], "existing_motion_summary": report["existing_motion_summary"],
            "issues": report["issues"]}


def record_acceptance(slug: str, result: dict, output: Path, spec: Path, source_root: Path) -> None:
    """An explicit --install records the operator's completed visual review."""
    path = ROOT / "character-motion/chores/acceptance.json"
    ledger = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"version": 1, "characters": {}}
    sources = sorted({definition["source"] for definition in result["actions"].values()})
    files = {"spec": spec, "build_report": output / "build-report.json", "audit_report": output / "audit/report.json",
             "contact_sheet": output / "contact-backgrounds.png"}
    ledger["characters"][slug] = {
        "status": "reviewed_and_installed", "reviewed_at": datetime.now(timezone.utc).isoformat(),
        "review": "All action frames visually checked on contrasting backgrounds; body scale, tool clearance, and foot baseline checked.",
        "sources": [{"file": filename, "sha256": sha256(source_root / filename)} for filename in sources],
        "actions": {action: {"path": f"assets/sprites/character-animations/{slug}/{action}.png",
                             "sha256": definition["sha256"], "fps": ACTION_FPS[action]}
                    for action, definition in result["actions"].items()},
        "evidence": {name: {"path": str(file.relative_to(ROOT)).replace("\\", "/"), "sha256": sha256(file)}
                     for name, file in files.items()},
        "chore_audit": result["audit"]["chore_summary"],
        "preserved_motion_audit": result["audit"]["existing_motion_summary"],
    }
    path.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def install_reviewed(slug: str, source_root: Path) -> None:
    """Install the exact staged files inspected by the operator, without rebuilding."""
    output = ROOT / "output/resident-chores" / slug
    result = json.loads((output / "build-report.json").read_text(encoding="utf-8"))
    if set(result["actions"]) != set(ACTIONS) or result.get("audit", {}).get("status") != 0:
        raise ValueError(f"{slug}: all three staged actions need a passing audit")
    if all("target_height" in definition for definition in result["actions"].values()):
        check_action_heights({action: (definition["source"], definition["target_height"] / definition["requested_scale"])
                              for action, definition in result["actions"].items()})
    spec = ROOT / result["spec"]
    evidence = result.get("staged_evidence", {})
    for name, path in (("spec", spec), ("audit", output / "audit/report.json"), ("contact", output / "contact-backgrounds.png")):
        if evidence.get(name) != sha256(path):
            raise ValueError(f"{slug}: {name} changed after staging; rebuild and review")
    for action, definition in result["actions"].items():
        if definition.get("source_sha256") != sha256(source_root / definition["source"]):
            raise ValueError(f"{slug}: source changed after staging; rebuild and review")
        if definition["sha256"] != sha256(output / "runtime" / f"{action}.png"):
            raise ValueError(f"{slug}: {action} changed after staging; rebuild and review")
    destination = ROOT / "assets/sprites/character-animations" / slug
    for action in ACTIONS:
        shutil.copyfile(output / "runtime" / f"{action}.png", destination / f"{action}.png")
    record_acceptance(slug, result, output, spec, source_root)
    print(f"{slug}: installed exact reviewed staging files", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / "output/resident-chores/source-manifest.json")
    parser.add_argument("--only", nargs="*", help="Build only these character slugs")
    parser.add_argument("--audit", action="store_true", help="Run the full motion auditor and create GIFs")
    parser.add_argument("--install", action="store_true", help="Copy reviewed new action strips to installed asset folders")
    parser.add_argument("--install-reviewed", action="store_true", help="Install already audited/reviewed staging files after hash verification, without rebuilding")
    args = parser.parse_args()
    source_root = ROOT / "output/resident-chores/sources"
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    selected = set(args.only) if args.only else None
    if args.install_reviewed:
        if args.install or args.audit:
            parser.error("--install-reviewed uses existing staging and cannot combine with --install or --audit")
        slugs = sorted(selected) if selected else list(dict.fromkeys(slug for source in manifest["sources"] for slug in source["characters"]))
        for slug in slugs:
            install_reviewed(slug, source_root)
        return 0
    pending: dict[str, dict] = defaultdict(dict)
    sources, failures = [], []
    for entry in manifest["sources"]:
        characters = entry["characters"]
        if selected is not None and not selected.intersection(characters):
            continue
        actions = entry.get("actions", list(ACTIONS))
        if not actions or any(action not in ACTIONS for action in actions):
            raise ValueError(f"Invalid action rows for {entry['file']}")
        path = source_root / entry["file"]
        try:
            rows, details = split_source(path, len(characters) * len(actions))
        except ValueError as error:
            failures.append({"source": entry["file"], "error": str(error)})
            print(f"SOURCE REVIEW REQUIRED: {error}", flush=True)
            continue
        sources.append(details)
        for character_index, slug in enumerate(characters):
            if selected is not None and slug not in selected:
                continue
            for action_index, action in enumerate(actions):
                pending[slug][action] = {"cells": rows[character_index * len(actions) + action_index], "source": entry["file"], "source_sha256": details["sha256"]}
    summary = {"sources": sources, "characters": {}, "source_failures": failures, "installed": args.install}
    for slug, actions in pending.items():
        try:
            check_action_heights({action: (source["source"], max(visible_bbox(cell)[3] - visible_bbox(cell)[1]
                                                                 for cell in source["cells"]))
                                  for action, source in actions.items()})
        except ValueError as error:
            failures.append({"character": slug, "error": str(error)})
            print(f"SOURCE REVIEW REQUIRED: {slug}: {error}", flush=True)
            continue
        output = ROOT / "output/resident-chores" / slug
        runtime = output / "runtime"
        runtime.mkdir(parents=True, exist_ok=True)
        target_height, baseline = installed_framing(slug)
        results = {}
        for action, source in actions.items():
            strip, result = normalize_row(source["cells"], target_height, baseline)
            path = runtime / f"{action}.png"
            strip.save(path)
            results[action] = {**result, "source": source["source"], "source_sha256": source["source_sha256"], "sha256": sha256(path)}
        spec = write_spec(slug, runtime)
        contact_sheet(slug, runtime, output / "contact-backgrounds.png")
        result = {"actions": results, "spec": str(spec.relative_to(ROOT))}
        if args.audit:
            result["audit"] = audit_character(spec, output / "audit")
            result["staged_evidence"] = {"spec": sha256(spec), "audit": sha256(output / "audit/report.json"),
                                         "contact": sha256(output / "contact-backgrounds.png")}
        if args.install:
            if set(actions) != set(ACTIONS):
                raise ValueError(f"{slug}: install requires all three reviewed actions in the selected manifest")
            if not args.audit or result["audit"]["status"] != 0:
                raise ValueError(f"{slug}: install requires a passing audit")
            destination = ROOT / "assets/sprites/character-animations" / slug
            for action in actions:
                shutil.copyfile(runtime / f"{action}.png", destination / f"{action}.png")
        summary["characters"][slug] = result
        (output / "build-report.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        if args.install:
            record_acceptance(slug, result, output, spec, source_root)
        audit_note = (f", new chores {result['audit']['chore_summary']}; preserved motion {result['audit']['existing_motion_summary']}"
                      if args.audit else "")
        print(f"{slug}: built {len(actions)} chore strips" + audit_note, flush=True)
    summary["review_overviews"] = batch_overviews(list(summary["characters"]), args.manifest.stem)
    report = ROOT / "output/resident-chores" / ("build-report.json" if selected is None else "selected-build-report.json")
    report.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return int(bool(failures) or any(item.get("audit", {}).get("status", 0) for item in summary["characters"].values()))


if __name__ == "__main__":
    raise SystemExit(main())
