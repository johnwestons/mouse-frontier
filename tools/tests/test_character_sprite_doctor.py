from __future__ import annotations

import contextlib
import io
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image, ImageDraw


TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from character_sprite_doctor import (  # noqa: E402
    ACTION_SPECS,
    ALL_ACTION_SPECS,
    FRAME_SIZE,
    HandAnchor,
    SpriteDoctor,
    apply_weapon_anchor_overrides,
    assemble_strip,
    build_parser,
    command_audit,
    command_weapon_anchors,
    detect_hand_anchor,
    encode_weapon_anchors_lua,
    measure_frame,
    remove_edge_neutral_backdrop,
    remove_edge_green,
    save_repair_plan,
    weapon_anchor_report,
)


def frame(color: tuple[int, int, int, int], box: tuple[int, int, int, int] = (156, 73, 356, 458)) -> Image.Image:
    image = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((box[0], box[1], box[2] - 1, box[3] - 1), fill=color)
    return image


class SpriteDoctorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.animation_root = self.root / "assets" / "sprites" / "character-animations"
        self.base_root = self.root / "assets" / "sprites" / "MainCharacters"
        self.animation_root.mkdir(parents=True)
        self.base_root.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def add_character(self, name: str, color: tuple[int, int, int, int]) -> Path:
        directory = self.animation_root / name
        directory.mkdir()
        base = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(base).rectangle((70, 20, 185, 235), fill=color)
        base.save(self.base_root / f"{name}.png")

        neutral = frame(color)
        # Presence of unconscious.png selects the modern six-frame walk contract.
        for action, spec in ACTION_SPECS.items():
            if action == "death":
                continue
            count = spec.frames
            assemble_strip([neutral] * count).save(directory / f"{action}.png")
        return directory

    def doctor(self) -> SpriteDoctor:
        return SpriteDoctor(self.root, self.animation_root)

    def test_staged_locomotion_audit_preserves_installed_assets_and_records_hashes(self) -> None:
        installed = self.add_character("test-mouse", (190, 65, 45, 255))
        installed_hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in installed.glob("*.png")}
        staging_root = self.root / "output" / "character-motion"
        staged = staging_root / "test-mouse" / "runtime"
        staged.mkdir(parents=True)
        for action in ALL_ACTION_SPECS:
            if action not in {"idle", "walk"} and not action.startswith(("idle_", "walk_")):
                continue
            count = 8 if action.startswith("walk") else 2
            assemble_strip([frame((190, 65, 45, 255))] * count).save(staged / f"{action}.png")
        report_path = self.root / "doctor-report.json"
        contacts = self.root / "contacts"
        args = build_parser().parse_args([
            "audit", "test-mouse", "--animation-root", str(staging_root),
            "--animation-subdirectory", "runtime", "--locomotion-only", "--geometry-only",
            "--report", str(report_path), "--contact-sheets", str(contacts),
        ])
        with patch("character_sprite_doctor.ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            exit_code = command_audit(args)
        report = json.loads(report_path.read_text(encoding="utf-8"))
        self.assertEqual(exit_code, 0)
        self.assertEqual(len(report["audited_inputs"]), 16)
        self.assertFalse(any(issue.get("action") in {"sit", "lay", "melee", "death"} for issue in report["issues"]))
        for reference in report["audited_inputs"]:
            path = self.root / reference["path"]
            self.assertEqual(path.parent, staged)
            self.assertEqual(reference["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(installed_hashes, {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in installed.glob("*.png")})
        self.assertEqual(self.doctor().character_dir("test-mouse"), installed)
        with Image.open(contacts / "test-mouse.png") as contact:
            self.assertEqual(contact.size, (130 + 8 * 128 + 20, 46 + 16 * 156))

    def test_virtual_repair_pixels_are_not_claimed_as_audited_file_bytes(self) -> None:
        self.add_character("test-mouse", (190, 65, 45, 255))
        result = self.doctor().audit(["test-mouse"], identity=False, locomotion_only=True, overrides={
            ("test-mouse", "walk"): assemble_strip([frame((60, 100, 150, 255))] * 6),
        })
        self.assertNotIn("walk", [record["action"] for record in result.audited_inputs])
        self.assertIn("idle", [record["action"] for record in result.audited_inputs])

    def _core_manifest(self) -> Path:
        path = self.root / "character-motion" / "test-mouse-build.json"
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps({
            "character": "test-mouse",
            "framing": {"frame_size": 512, "target_height": 385, "center_x": 256, "baseline": 458, "horizontal_anchor": "core"},
            "idle_sets": [{"outputs": ["idle.png"]}], "walks": {"walk.png": {}},
        }), encoding="utf-8")
        return path

    @staticmethod
    def _tailed_frame(tail_end: int, body_width: int = 100) -> Image.Image:
        sprite = frame((190, 65, 45, 255), (256 - body_width // 2, 73, 256 + body_width // 2, 458))
        ImageDraw.Draw(sprite).rectangle((290, 415, tail_end, 430), fill=(190, 65, 45, 255))
        return sprite

    def test_explicit_core_contract_checks_body_anchor_and_preserves_real_misalignment(self) -> None:
        directory = self.add_character("test-mouse", (190, 65, 45, 255))
        manifest = self._core_manifest()
        sprites = [self._tailed_frame(430), self._tailed_frame(420)]
        assemble_strip(sprites).save(directory / "idle.png")
        legacy = self.doctor().inspect_sheet("test-mouse", "idle")
        self.assertIn("center_mismatch", {issue.code for issue in legacy.issues})
        doctor = SpriteDoctor(self.root, build_manifest=manifest)
        inspection = doctor.inspect_sheet("test-mouse", "idle")
        self.assertNotIn("center_mismatch", {issue.code for issue in inspection.issues})
        self.assertEqual(inspection.framing_measurements[0]["anchor_x"], 255)
        moved = Image.new("RGBA", sprites[0].size)
        moved.alpha_composite(sprites[0], (10, -6))
        changed = doctor.inspect_sheet("test-mouse", "idle", {("test-mouse", "idle"): assemble_strip([moved, sprites[1]])})
        codes = {issue.code for issue in changed.issues}
        self.assertIn("center_mismatch", codes)
        self.assertIn("baseline_mismatch", codes)

    def test_core_scale_metric_separates_tail_pose_from_body_resize(self) -> None:
        self.add_character("test-mouse", (190, 65, 45, 255))
        doctor = SpriteDoctor(self.root, build_manifest=self._core_manifest())
        tail_only = assemble_strip([self._tailed_frame(440), self._tailed_frame(340)])
        legacy = self.doctor().inspect_sheet("test-mouse", "idle", {("test-mouse", "idle"): tail_only})
        self.assertIn("adjacent_scale_jump", {issue.code for issue in legacy.issues})
        inspection = doctor.inspect_sheet("test-mouse", "idle", {("test-mouse", "idle"): tail_only})
        self.assertNotIn("adjacent_scale_jump", {issue.code for issue in inspection.issues})
        self.assertTrue(any(issue.code == "pose_extent_change" and issue.severity == "info" for issue in inspection.issues))
        body_resize = assemble_strip([self._tailed_frame(440), self._tailed_frame(340, body_width=120)])
        inspection = doctor.inspect_sheet("test-mouse", "idle", {("test-mouse", "idle"): body_resize})
        issue = next(issue for issue in inspection.issues if issue.code == "adjacent_scale_jump")
        self.assertEqual(issue.severity, "warning")
        self.assertEqual(issue.details["comparisons"][0]["width_metric"], "bbox")
        self.assertGreater(issue.details["comparisons"][0]["width_change"], 0.10)
        self.assertGreater(issue.details["comparisons"][0]["core_width_change"], 0.10)

    def test_one_pixel_equipment_bridge_does_not_create_a_body_resize_alarm(self) -> None:
        self.add_character("test-mouse", (190, 65, 45, 255))
        doctor = SpriteDoctor(self.root, build_manifest=self._core_manifest())
        sprites = []
        # The 177-row torso band requires 62 occupied pixels for eligibility.
        # Reducing this already connected equipment bridge from 62 to 61 pixels
        # splits the selected support run, although body and bbox are unchanged.
        for bridge_bottom in (261, 260):
            sprite = frame((190, 65, 45, 255), (206, 73, 306, 458))
            draw = ImageDraw.Draw(sprite)
            draw.rectangle((310, 200, 339, 310), fill=(190, 65, 45, 255))
            draw.rectangle((306, 200, 309, bridge_bottom), fill=(190, 65, 45, 255))
            sprites.append(sprite)
        inspection = doctor.inspect_sheet("test-mouse", "idle", {("test-mouse", "idle"): assemble_strip(sprites)})
        first, second = inspection.framing_measurements
        self.assertEqual(first["bbox_width"], second["bbox_width"])
        self.assertEqual(first["height"], second["height"])
        self.assertGreater(abs(first["core_width"] - second["core_width"]) / min(first["core_width"], second["core_width"]), 0.10)
        self.assertNotIn("adjacent_scale_jump", {issue.code for issue in inspection.issues})
        self.assertTrue(any(issue.code == "core_support_topology_change" and issue.severity == "info" for issue in inspection.issues))

    def test_framing_contract_is_hashed_and_cannot_change_between_load_and_audit(self) -> None:
        self.add_character("test-mouse", (190, 65, 45, 255))
        path = self._core_manifest()
        doctor = SpriteDoctor(self.root, build_manifest=path)
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        result = doctor.audit(["test-mouse"], identity=False, locomotion_only=True)
        self.assertEqual(result.to_dict()["framing_contract"]["sha256"], expected)
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "manifest changed"):
            doctor.audit(["test-mouse"], identity=False, locomotion_only=True)

    def test_crop_scale_center_and_baseline_are_detected_and_repaired(self) -> None:
        directory = self.add_character("test-mouse", (190, 65, 45, 255))
        bad = frame((190, 65, 45, 255), (12, 90, 212, 390))
        # A remote alpha speck emulates the faint residue that often defeats getbbox().
        bad.putpixel((470, 30), (0, 255, 0, 1))
        assemble_strip([bad] * 3).save(directory / "melee.png")

        doctor = self.doctor()
        before = doctor.audit(["test-mouse"])
        codes = {issue.code for issue in before.issues if issue.action == "melee"}
        self.assertIn("scale_mismatch", codes)
        self.assertIn("center_mismatch", codes)
        self.assertIn("baseline_mismatch", codes)
        self.assertIn("alpha_halo", codes)

        plan = doctor.plan_repairs(before)
        repair = next(item for item in plan.repairs if item.action == "melee")
        after = doctor.audit(["test-mouse"], overrides={("test-mouse", "melee"): repair.image})
        remaining = {
            issue.code for issue in after.issues
            if issue.action == "melee" and issue.code in {
                "scale_mismatch", "center_mismatch", "baseline_mismatch", "alpha_halo"
            }
        }
        self.assertEqual(set(), remaining)

        repaired_frame = repair.image.crop((0, 0, FRAME_SIZE, FRAME_SIZE))
        metrics = measure_frame(repaired_frame, 1)
        self.assertEqual(385, metrics.extent)
        self.assertAlmostEqual(256.0, metrics.center_x, delta=0.5)
        self.assertEqual(458, metrics.bottom)

    def test_missing_sheet_is_rebuilt_from_complete_atlas(self) -> None:
        directory = self.add_character("atlas-mouse", (65, 145, 210, 255))
        (directory / "hit.png").unlink()

        atlas = Image.new("RGBA", (600, 400), (0, 0, 0, 0))
        draw = ImageDraw.Draw(atlas)
        for row in range(4):
            for column in range(6):
                left, top = column * 100, row * 100
                draw.rectangle((left + 18, top + 10, left + 81, top + 89), fill=(65, 145, 210, 255))
        atlas.save(directory / "complete-transparent-source.png")

        doctor = self.doctor()
        before = doctor.audit(["atlas-mouse"])
        missing = [issue for issue in before.issues if issue.action == "hit" and issue.code == "missing_sheet"]
        self.assertEqual(1, len(missing))
        self.assertTrue(missing[0].repairable)

        plan = doctor.plan_repairs(before)
        repair = next(item for item in plan.repairs if item.action == "hit")
        self.assertIn("same-character source", repair.reason)
        after = doctor.audit(["atlas-mouse"], overrides={("atlas-mouse", "hit"): repair.image})
        self.assertFalse(any(issue.action == "hit" and issue.severity == "error" for issue in after.issues))

    def test_reciprocal_identity_mismatch_can_be_swapped_safely(self) -> None:
        red = (220, 45, 35, 255)
        blue = (35, 80, 220, 255)
        red_dir = self.add_character("red-mouse", red)
        blue_dir = self.add_character("blue-mouse", blue)
        assemble_strip([frame(blue)] * 3).save(red_dir / "melee.png")
        assemble_strip([frame(red)] * 3).save(blue_dir / "melee.png")

        doctor = self.doctor()
        audit = doctor.audit(["red-mouse", "blue-mouse"])
        mismatches = {
            (issue.character, issue.action) for issue in audit.issues
            if issue.code == "identity_mismatch"
        }
        self.assertEqual({("red-mouse", "melee"), ("blue-mouse", "melee")}, mismatches)

        conservative = doctor.plan_repairs(audit, identity_swaps=False)
        self.assertFalse(any(item.action == "melee" for item in conservative.repairs))
        enabled = doctor.plan_repairs(audit, identity_swaps=True)
        swapped = {(item.character, item.action) for item in enabled.repairs}
        self.assertIn(("red-mouse", "melee"), swapped)
        self.assertIn(("blue-mouse", "melee"), swapped)

        post = doctor.audit(["red-mouse", "blue-mouse"], overrides=enabled.overrides())
        self.assertFalse(any(issue.code == "identity_mismatch" for issue in post.issues))

    def test_legacy_three_frame_walk_changes_only_when_unconscious_art_exists(self) -> None:
        directory = self.add_character("legacy-mouse", (145, 100, 55, 255))
        (directory / "unconscious.png").unlink()
        neutral = frame((145, 100, 55, 255))
        assemble_strip([neutral] * 3).save(directory / "walk.png")

        doctor = self.doctor()
        legacy = doctor.audit(["legacy-mouse"])
        self.assertFalse(any(issue.action == "walk" and issue.code == "frame_count_mismatch" for issue in legacy.issues))

        unconscious = assemble_strip([neutral] * 2)
        modern = doctor.audit(
            ["legacy-mouse"], overrides={("legacy-mouse", "unconscious"): unconscious}
        )
        self.assertTrue(any(issue.action == "walk" and issue.code == "frame_count_mismatch" for issue in modern.issues))

    def test_directional_contract_requires_complete_eight_frame_gaits_and_idles(self) -> None:
        directory = self.add_character("directional-mouse", (145, 100, 55, 255))
        neutral = frame((145, 100, 55, 255))
        assemble_strip([neutral] * 8).save(directory / "walk.png")
        for action in ("walk_north", "walk_northeast", "walk_southeast", "walk_south"):
            assemble_strip([neutral] * 8).save(directory / f"{action}.png")
        for action in ("idle_north", "idle_northeast", "idle_southeast", "idle_south"):
            assemble_strip([neutral] * 2).save(directory / f"{action}.png")

        complete = self.doctor().audit(["directional-mouse"], identity=False)
        self.assertEqual(8, complete.inspections[("directional-mouse", "walk")].expected_count)
        self.assertEqual(8, complete.inspections[("directional-mouse", "walk_north")].actual_count)
        self.assertFalse(any(
            issue.severity == "error" and issue.action and (
                issue.action.startswith("walk_") or issue.action.startswith("idle_")
            ) for issue in complete.issues
        ))

        for action in ("walk_west", "walk_northwest", "walk_southwest"):
            assemble_strip([neutral] * 8).save(directory / f"{action}.png")
        for action in ("idle_west", "idle_northwest", "idle_southwest"):
            assemble_strip([neutral] * 2).save(directory / f"{action}.png")
        authored_west = self.doctor().audit(["directional-mouse"], identity=False)
        self.assertEqual(8, authored_west.inspections[("directional-mouse", "walk_west")].actual_count)

        (directory / "idle_south.png").unlink()
        partial = self.doctor().audit(["directional-mouse"], identity=False)
        self.assertTrue(any(
            issue.action == "idle_south" and issue.code == "missing_sheet"
            for issue in partial.issues
        ))

    def test_detached_opaque_fragment_is_reported_instead_of_silently_deleted(self) -> None:
        directory = self.add_character("fragment-mouse", (120, 180, 70, 255))
        contaminated = frame((120, 180, 70, 255))
        ImageDraw.Draw(contaminated).rectangle((18, 18, 21, 21), fill=(255, 255, 255, 255))
        assemble_strip([contaminated] * 3).save(directory / "use.png")

        doctor = self.doctor()
        audit = doctor.audit(["fragment-mouse"])
        fragments = [issue for issue in audit.issues if issue.action == "use" and issue.code == "detached_fragment"]
        self.assertEqual(3, len(fragments))
        self.assertTrue(all(not issue.repairable for issue in fragments))

        plan = doctor.plan_repairs(audit)
        self.assertTrue(any(issue.code == "detached_fragment" for issue in plan.unresolved))

    def test_ferret_style_fragments_are_found_when_basic_geometry_passes(self) -> None:
        directory = self.add_character("ferret-scout", (205, 105, 45, 255))
        clean = frame((205, 105, 45, 255), (64, 139, 449, 458))
        bad_three = clean.copy()
        bad_four = clean.copy()
        ImageDraw.Draw(bad_three).rectangle((205, 97, 219, 112), fill=(235, 120, 35, 255))
        ImageDraw.Draw(bad_four).rectangle((205, 94, 219, 109), fill=(235, 120, 35, 255))
        assemble_strip([clean, clean, bad_three, bad_four, clean, clean]).save(directory / "walk.png")

        inspection = self.doctor().inspect_sheet("ferret-scout", "walk")
        codes = {issue.code for issue in inspection.issues}
        fragment_frames = {
            issue.frame for issue in inspection.issues if issue.code == "detached_fragment"
        }
        self.assertEqual({3, 4}, fragment_frames)
        self.assertIn("top_bound_jitter", codes)
        self.assertIn("adjacent_scale_jump", codes)
        self.assertNotIn("scale_mismatch", codes)
        self.assertNotIn("center_mismatch", codes)
        self.assertNotIn("baseline_mismatch", codes)

    def test_substantial_fragment_entering_panel_boundary_is_reported(self) -> None:
        directory = self.add_character("boundary-mouse", (95, 145, 205, 255))
        contaminated = frame((95, 145, 205, 255), (64, 73, 449, 458))
        ImageDraw.Draw(contaminated).rectangle((0, 210, 23, 233), fill=(225, 115, 45, 255))
        assemble_strip([contaminated] * 3).save(directory / "use.png")
        codes = {
            issue.code for issue in self.doctor().inspect_sheet("boundary-mouse", "use").issues
        }
        self.assertIn("panel_boundary_fragment", codes)

    def test_green_screen_cleanup_preserves_small_green_edge_art(self) -> None:
        screen = Image.new("RGBA", (200, 120), (20, 235, 25, 255))
        ImageDraw.Draw(screen).rectangle((65, 20, 135, 110), fill=(180, 65, 40, 255))
        cleaned = remove_edge_green(screen)
        self.assertEqual(0, cleaned.getpixel((0, 0))[3])
        self.assertEqual(255, cleaned.getpixel((100, 60))[3])

        edge_art = Image.new("RGBA", (200, 120), (0, 0, 0, 0))
        ImageDraw.Draw(edge_art).rectangle((0, 45, 5, 65), fill=(25, 210, 40, 255))
        preserved = remove_edge_green(edge_art)
        self.assertEqual(255, preserved.getpixel((2, 55))[3])

    def test_neutral_backdrop_cleanup_preserves_enclosed_light_art(self) -> None:
        backdrop = Image.new("RGBA", (200, 120), (242, 242, 242, 255))
        draw = ImageDraw.Draw(backdrop)
        draw.rectangle((55, 15, 145, 110), fill=(90, 55, 30, 255))
        draw.rectangle((80, 40, 120, 80), fill=(248, 248, 245, 255))
        cleaned = remove_edge_neutral_backdrop(backdrop)
        self.assertEqual(0, cleaned.getpixel((0, 0))[3])
        self.assertEqual(255, cleaned.getpixel((100, 60))[3])

    def test_recovering_unconscious_art_upgrades_legacy_walk_in_same_plan(self) -> None:
        directory = self.add_character("upgrade-mouse", (155, 85, 175, 255))
        neutral = frame((155, 85, 175, 255))
        (directory / "unconscious.png").unlink()
        assemble_strip([neutral] * 3).save(directory / "walk.png")
        assemble_strip([neutral] * 2).save(directory / "unconscious-generated-source.png")

        doctor = self.doctor()
        before = doctor.audit(["upgrade-mouse"])
        plan = doctor.plan_repairs(before)
        repaired_actions = {(item.character, item.action) for item in plan.repairs}
        self.assertIn(("upgrade-mouse", "unconscious"), repaired_actions)
        self.assertIn(("upgrade-mouse", "walk"), repaired_actions)

        after = doctor.audit(["upgrade-mouse"], overrides=plan.overrides())
        self.assertFalse(any(issue.action == "walk" and issue.severity == "error" for issue in after.issues))

    def test_apply_creates_backup_before_replacing_sheet(self) -> None:
        directory = self.add_character("backup-mouse", (70, 135, 185, 255))
        bad = frame((70, 135, 185, 255), (15, 120, 215, 420))
        target = directory / "ranged.png"
        assemble_strip([bad] * 3).save(target)
        original = target.read_bytes()

        doctor = self.doctor()
        plan = doctor.plan_repairs(doctor.audit(["backup-mouse"]))
        _, backup_root = save_repair_plan(
            doctor, plan, self.root / "output" / "sprite-doctor", True, "test-run"
        )
        self.assertIsNotNone(backup_root)
        backup = backup_root / "backup-mouse" / "ranged.png"  # type: ignore[operator]
        self.assertEqual(original, backup.read_bytes())
        self.assertNotEqual(original, target.read_bytes())
        repaired = doctor.audit(["backup-mouse"])
        self.assertFalse(any(issue.action == "ranged" and issue.severity == "error" for issue in repaired.issues))

    def test_hand_anchor_follows_the_extended_attack_arm(self) -> None:
        right_attack = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        right_draw = ImageDraw.Draw(right_attack)
        right_draw.rectangle((190, 120, 320, 459), fill=(120, 75, 45, 255))
        right_draw.rectangle((300, 225, 445, 275), fill=(185, 120, 75, 255))

        right = detect_hand_anchor(right_attack, 2)
        self.assertEqual(2, right.frame)
        self.assertEqual(1, right.side)
        self.assertGreater(right.x, 0.76)
        self.assertAlmostEqual(0.49, right.y, delta=0.08)
        self.assertGreater(right.confidence, 0.8)

        left_attack = right_attack.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        left = detect_hand_anchor(left_attack, 3)
        self.assertEqual(-1, left.side)
        self.assertLess(left.x, 0.24)
        self.assertAlmostEqual(right.y, left.y, delta=0.01)

    def test_empty_attack_frame_gets_reviewable_fallback_anchor(self) -> None:
        empty = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        anchor = detect_hand_anchor(empty, 1)
        self.assertEqual(HandAnchor(1, 0.28, 0.46, -1, 0.0), anchor)

    def test_detached_fleck_does_not_pull_anchor_away_from_attack_hand(self) -> None:
        attack = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(attack)
        draw.rectangle((190, 120, 320, 459), fill=(110, 70, 40, 255))
        draw.rectangle((65, 225, 200, 275), fill=(180, 115, 70, 255))
        # A detached muzzle flash, spark, or generation fleck must not be
        # mistaken for the opposite-side hand merely because it is outermost.
        draw.rectangle((490, 240, 492, 242), fill=(255, 225, 90, 255))

        anchor = detect_hand_anchor(attack, 1)
        self.assertEqual(-1, anchor.side)
        self.assertLess(anchor.x, 0.24)
        self.assertAlmostEqual(0.49, anchor.y, delta=0.08)

    def test_weapon_anchor_export_is_sorted_stable_and_reports_confidence(self) -> None:
        anchors = {
            "zeta-mouse": {
                "ranged": [HandAnchor(1, 0.123456, 0.654321, -1, 0.5)],
            },
            "alpha-mouse": {
                "melee": [HandAnchor(1, 0.75, 0.25, 1, 0.8754)],
            },
        }
        encoded = encode_weapon_anchors_lua(anchors)
        self.assertLess(encoded.index('["alpha-mouse.png"]'), encoded.index('["zeta-mouse.png"]'))
        self.assertIn("melee={{x=0.7500,y=0.2500,side=1,confidence=0.875}}", encoded)
        self.assertIn("ranged={{x=0.1235,y=0.6543,side=-1,confidence=0.500}}", encoded)
        self.assertTrue(encoded.endswith("}\n"))

        report = weapon_anchor_report(anchors)
        self.assertEqual(2, report["summary"]["character_count"])
        self.assertEqual(2, report["summary"]["anchor_count"])
        self.assertEqual(1, report["summary"]["low_confidence"])

    def test_reviewed_weapon_anchor_override_replaces_only_named_frame(self) -> None:
        anchors = {
            "review-mouse": {
                "melee": [
                    HandAnchor(1, 0.2, 0.4, -1, 0.6),
                    HandAnchor(2, 0.8, 0.4, 1, 0.7),
                ],
            },
        }
        override_path = self.root / "weapon-overrides.json"
        override_path.write_text(
            '{"review-mouse":{"melee":[{"frame":2,"x":0.625,"y":0.375,"side":-1}]}}',
            encoding="utf-8",
        )

        self.assertEqual(1, apply_weapon_anchor_overrides(anchors, override_path))
        self.assertEqual(HandAnchor(1, 0.2, 0.4, -1, 0.6), anchors["review-mouse"]["melee"][0])
        self.assertEqual(HandAnchor(2, 0.625, 0.375, -1, 1.0), anchors["review-mouse"]["melee"][1])

    def test_weapon_anchor_check_detects_stale_runtime_data(self) -> None:
        self.add_character("anchor-mouse", (165, 95, 55, 255))
        destination = self.root / "game" / "weapon_attachment_points.lua"
        arguments = SimpleNamespace(
            characters=["anchor-mouse"],
            output=str(destination),
            report=None,
            contact_sheets=None,
            check=False,
            overrides=str(self.root / "missing-overrides.json"),
        )
        with patch("character_sprite_doctor.ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, command_weapon_anchors(arguments))
            arguments.check = True
            self.assertEqual(0, command_weapon_anchors(arguments))
            destination.write_text("-- stale\n", encoding="utf-8")
            self.assertEqual(1, command_weapon_anchors(arguments))


if __name__ == "__main__":
    unittest.main()
