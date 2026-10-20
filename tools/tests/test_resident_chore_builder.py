"""Source splitting preserves silhouettes and normalization preserves pose scale."""
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw

from tools import build_resident_chore_assets as builder
from tools import sprite_motion_audit as audit


class ResidentChoreBuilderTests(unittest.TestCase):
    def test_scanline_components_match_pixel_auditor_for_diagonals_and_bridges(self):
        random = np.random.default_rng(84)
        for density in (0.12, 0.4, 0.8):
            mask = random.random((36, 41)) < density
            expected = sorted(audit.component_summary(mask), key=lambda item: (item["area"], item["bbox"]))
            actual = sorted(builder.component_summary(mask), key=lambda item: (item["area"], item["bbox"]))
            self.assertEqual(actual, expected)

    def test_staggered_components_preserve_tools_and_visible_colors_without_grid_cuts(self):
        image = Image.new("RGBA", (420, 220))
        draw = ImageDraw.Draw(image)
        for row in range(2):
            for column in range(4):
                x = 30 + column * 100
                y = 25 + row * 110
                draw.rectangle((x, y, x + 30, y + 70), fill=(180, 50 + column * 30, 20, 255))
                # The tool overlaps the nominal next column while remaining
                # connected to its own actor, and must not be grid-cropped.
                draw.rectangle((x + 29, y + 50, x + 79, y + 54), fill=(241, 241, 241, 255))
                draw.rectangle((x + 8, y + 30, x + 14, y + 36), fill=(255, 0, 0, 255))
                draw.rectangle((x + 10, y - 7, x + 12, y - 5), fill=(80, 160, 70, 255))
        # Same source contains transparent red metadata residue.
        image.putpixel((0, 0), (255, 0, 0, 1))
        with tempfile.TemporaryDirectory(dir=builder.ROOT / "output") as temporary:
            path = Path(temporary) / "source.png"
            image.save(path)
            source_hash = builder.sha256(path)
            rows, report = builder.split_source(path, 2)
            self.assertEqual(builder.sha256(path), source_hash)
        self.assertEqual([len(row) for row in rows], [4, 4])
        self.assertEqual(report["cleared_pixels"], 1)
        original = np.asarray(image)
        self.assertEqual(sum(np.count_nonzero(np.asarray(frame)[:, :, 3]) for row in rows for frame in row),
                         np.count_nonzero(original[:, :, 3] > 4))
        for row in rows:
            for frame in row:
                pixels = np.asarray(frame)
                self.assertEqual(int(np.count_nonzero(np.all(pixels == (255, 0, 0, 255), axis=2))), 49)
                self.assertEqual(int(np.count_nonzero(np.all(pixels == (80, 160, 70, 255), axis=2))), 9)
                self.assertEqual(frame.width, 80)

    def test_common_scale_keeps_crouch_height_and_anchors_without_clipping(self):
        cells = []
        for height in (45, 60, 75, 90):
            cells.append(Image.new("RGBA", (40, height), (60, 120, 180, 255)))
        strip, report = builder.normalize_row(cells, 180, 229)
        self.assertEqual(strip.size, (2048, 256))
        self.assertEqual(report["shared_scale"], 2)
        self.assertEqual([frame["output_size"][1] for frame in report["frames"]], [90, 120, 150, 180])
        self.assertEqual([frame["baseline"] for frame in report["frames"]], [229] * 4)
        self.assertEqual([frame["core_x"] for frame in report["frames"]], [256] * 4)

    def test_opaque_background_is_rejected_without_erasing_any_source_colors(self):
        image = Image.new("RGBA", (400, 300), (120, 70, 30, 255))
        with tempfile.TemporaryDirectory(dir=builder.ROOT / "output") as temporary:
            path = Path(temporary) / "opaque.png"
            image.save(path)
            source_hash = builder.sha256(path)
            with self.assertRaisesRegex(ValueError, "opaque background"):
                builder.split_source(path, 3)
            self.assertEqual(builder.sha256(path), source_hash)

    def test_waist_up_standing_row_is_rejected_before_normalization_hides_missing_legs(self):
        with self.assertRaisesRegex(ValueError, "missing legs"):
            builder.check_action_heights({"sweep": ("atlas.png", 272), "tend": ("atlas.png", 166)})
        builder.check_action_heights({"sweep": ("atlas.png", 207), "tend": ("atlas.png", 166)})
        # An independently generated replacement may use a different source scale.
        builder.check_action_heights({"sweep": ("atlas.png", 272), "tend": ("replacement.png", 166)})

    def test_reviewed_install_rejects_source_changes_and_records_exact_artifact_hashes(self):
        with tempfile.TemporaryDirectory(dir=builder.ROOT / "output") as temporary, patch.object(builder, "ROOT", Path(temporary)):
            output = builder.ROOT / "output/resident-chores/test-character"
            source_root = builder.ROOT / "output/resident-chores/sources"
            runtime = output / "runtime"
            destination = builder.ROOT / "assets/sprites/character-animations/test-character"
            spec = builder.ROOT / "character-motion/chores/test-character.json"
            for path in (source_root, runtime, destination, spec.parent, output / "audit"):
                path.mkdir(parents=True, exist_ok=True)
            source = source_root / "source.png"
            source.write_bytes(b"source pixels")
            spec.write_text("{}")
            (output / "audit/report.json").write_text("{}")
            (output / "contact-backgrounds.png").write_bytes(b"reviewed contact")
            actions = {}
            for action in builder.ACTIONS:
                path = runtime / f"{action}.png"
                path.write_bytes(action.encode())
                actions[action] = {"source": "source.png", "source_sha256": builder.sha256(source), "sha256": builder.sha256(path)}
            result = {"spec": str(spec.relative_to(builder.ROOT)), "actions": actions,
                      "audit": {"status": 0, "chore_summary": {"errors": 0, "warnings": 0},
                                "existing_motion_summary": {"errors": 0, "warnings": 0}},
                      "staged_evidence": {"spec": builder.sha256(spec), "audit": builder.sha256(output / "audit/report.json"),
                                          "contact": builder.sha256(output / "contact-backgrounds.png")}}
            (output / "build-report.json").write_text(json.dumps(result))
            source.write_bytes(b"changed source pixels")
            with self.assertRaisesRegex(ValueError, "source changed"):
                builder.install_reviewed("test-character", source_root)
            self.assertEqual(list(destination.iterdir()), [])
            source.write_bytes(b"source pixels")
            builder.install_reviewed("test-character", source_root)
            ledger = json.loads((spec.parent / "acceptance.json").read_text())["characters"]["test-character"]
            for action, detail in ledger["actions"].items():
                self.assertEqual(builder.sha256(destination / f"{action}.png"), detail["sha256"])


if __name__ == "__main__":
    unittest.main()
