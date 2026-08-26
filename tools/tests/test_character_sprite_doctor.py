from __future__ import annotations

import contextlib
import io
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
    FRAME_SIZE,
    HandAnchor,
    SpriteDoctor,
    apply_weapon_anchor_overrides,
    assemble_strip,
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
