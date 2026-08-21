from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from character_sprite_doctor import (  # noqa: E402
    ACTION_SPECS,
    FRAME_SIZE,
    SpriteDoctor,
    assemble_strip,
    measure_frame,
    remove_edge_green,
    save_repair_plan,
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


if __name__ == "__main__":
    unittest.main()
