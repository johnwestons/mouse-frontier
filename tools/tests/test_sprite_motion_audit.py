from __future__ import annotations

from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from PIL import Image, ImageDraw

from tools.build_directional_character_assets import core_horizontal_anchor_x, visible_bbox
from tools import sprite_motion_audit as audit


class SpriteMotionAuditCenterMetricTests(unittest.TestCase):
    @staticmethod
    def _tail_frames() -> list[Image.Image]:
        frames = []
        for side in ("left", "right"):
            frame = Image.new("RGBA", (128, 96))
            draw = ImageDraw.Draw(frame)
            draw.rectangle((54, 15, 76, 80), fill=(35, 110, 190, 255))
            draw.rectangle((20, 69, 56, 72) if side == "left" else (74, 69, 107, 72),
                           fill=(35, 110, 190, 255))
            frames.append(frame)
        return frames

    def _audit(self, frames: list[Image.Image], settings: dict):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            strip = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height))
            for index, frame in enumerate(frames):
                strip.alpha_composite(frame, (index * frame.width, 0))
            source = root / "source.png"
            strip.save(source)
            original = source.read_bytes()
            issues = []
            result = audit.audit_animation(
                "test_walk",
                {"path": "source.png", "frame_width": frames[0].width,
                 "frame_height": frames[0].height, "frame_count": len(frames), "loop": False},
                root, {"center_tolerance": 20, **settings}, [], root / "review",
                False, None, issues,
            )
            self.assertEqual(source.read_bytes(), original)
            sheet = (root / "review/contact-sheets/test_walk.png").read_bytes()
            return result, issues, hashlib.sha256(sheet).hexdigest()

    def test_default_bbox_keeps_existing_center_warning(self) -> None:
        result, issues, _ = self._audit(self._tail_frames(), {})
        warnings = [item for item in issues if item["code"] == "center_jitter"]
        self.assertEqual(len(warnings), 1)
        self.assertEqual(warnings[0]["severity"], "warning")
        measured = result["center_metrics"]
        self.assertEqual(set(measured), {"metric", "positions", "bbox_positions", "tolerance"})
        self.assertEqual(measured["metric"], "bbox")
        self.assertEqual(measured["positions"], measured["bbox_positions"])
        self.assertEqual(measured["tolerance"], 20)
        self.assertGreater(max(measured["positions"]) - min(measured["positions"]), 20)
        self.assertEqual(warnings[0]["details"], {"centers": measured["positions"], "tolerance": 20})

    def test_opted_core_reports_tail_extent_as_info_without_warning(self) -> None:
        frames = self._tail_frames()
        result, issues, _ = self._audit(frames, {"center_metric": "core"})
        measured = result["center_metrics"]
        self.assertEqual(measured["metric"], "core")
        expected = [core_horizontal_anchor_x(frame, visible_bbox(frame)) for frame in frames]
        self.assertEqual(measured["positions"], expected)
        self.assertEqual(max(expected) - min(expected), 0)
        self.assertGreater(max(measured["bbox_positions"]) - min(measured["bbox_positions"]), 20)
        self.assertFalse(any(item["severity"] in {"warning", "error"} for item in issues))
        evidence = [item for item in issues if item["code"] == "bbox_center_extent_change"]
        self.assertEqual(len(evidence), 1)
        self.assertEqual(evidence[0]["severity"], "info")
        self.assertEqual(evidence[0]["details"]["bbox_centers"], measured["bbox_positions"])
        self.assertEqual(evidence[0]["details"]["core_centers"], expected)
        self.assertEqual(evidence[0]["details"]["tolerance"], 20)

    def test_real_core_jitter_warns_even_when_outer_bbox_is_stable(self) -> None:
        frames = []
        for x in (35, 65):
            frame = Image.new("RGBA", (128, 96))
            draw = ImageDraw.Draw(frame)
            draw.rectangle((x, 15, x + 20, 80), fill=(35, 110, 190, 255))
            draw.rectangle((20, 69, 107, 72), fill=(35, 110, 190, 255))
            frames.append(frame)
        result, issues, _ = self._audit(frames, {"center_metric": "core"})
        measured = result["center_metrics"]
        self.assertEqual(len(set(measured["bbox_positions"])), 1)
        self.assertEqual(max(measured["positions"]) - min(measured["positions"]), 30)
        warning = [item for item in issues if item["code"] == "center_jitter"]
        self.assertEqual(len(warning), 1)
        self.assertEqual(warning[0]["severity"], "warning")
        self.assertEqual(warning[0]["details"]["tolerance"], 20)
        self.assertFalse(any(item["code"] == "bbox_center_extent_change" for item in issues))

    def test_core_uses_same_tolerance_boundary(self) -> None:
        frames = []
        for x in (35, 55):
            frame = Image.new("RGBA", (128, 96))
            draw = ImageDraw.Draw(frame)
            draw.rectangle((x, 15, x + 20, 80), fill=(35, 110, 190, 255))
            draw.rectangle((20, 69, 107, 72), fill=(35, 110, 190, 255))
            frames.append(frame)
        result, issues, _ = self._audit(frames, {"center_metric": "core"})
        positions = result["center_metrics"]["positions"]
        self.assertEqual(max(positions) - min(positions), 20)
        self.assertFalse(any(item["code"] == "center_jitter" for item in issues))

    def test_frame_metrics_and_contact_sheet_are_unchanged_by_metric_choice(self) -> None:
        frames = self._tail_frames()
        bbox, bbox_issues, bbox_sheet = self._audit(frames, {})
        explicit, explicit_issues, explicit_sheet = self._audit(frames, {"center_metric": "bbox"})
        core, _, core_sheet = self._audit(frames, {"center_metric": "core"})
        self.assertEqual(bbox["frames"], explicit["frames"])
        self.assertEqual(bbox["frames"], core["frames"])
        self.assertEqual(bbox_issues, explicit_issues)
        self.assertEqual(bbox_sheet, explicit_sheet)
        self.assertEqual(bbox_sheet, core_sheet)
        self.assertTrue(all(set(frame) == {"frame", "bbox", "visible_pixels"} for frame in core["frames"]))

    def test_unknown_metric_and_incompatible_core_alpha_are_rejected(self) -> None:
        for metric in (None, "", "centroid", "CORE", True, 0, ["core"], {"metric": "core"}):
            with self.subTest(metric=metric):
                with self.assertRaisesRegex(ValueError, "center_metric"):
                    audit.validate_center_metric({"center_metric": metric})
        for threshold in (15, 17, 24):
            with self.subTest(threshold=threshold):
                with self.assertRaisesRegex(ValueError, "alpha_threshold=16"):
                    audit.validate_center_metric({"center_metric": "core", "alpha_threshold": threshold})
        self.assertEqual(audit.validate_center_metric({"center_metric": "core", "alpha_threshold": 16}), "core")

    def test_invalid_metric_fails_cli_before_rendering(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            spec = root / "spec.json"
            spec.write_text(json.dumps({
                "version": 1, "character": "fixture", "animations": {"idle": {}},
                "gait": {}, "directions": {}, "audit": {"center_metric": "centroid"},
            }), encoding="utf-8")
            output = root / "review"
            with redirect_stdout(io.StringIO()) as log:
                code = audit.main([str(spec), "--project-root", str(root), "--output", str(output), "--no-gif"])
            self.assertEqual(code, 2)
            self.assertIn("center_metric", log.getvalue())
            self.assertFalse(output.exists())

    def test_core_audit_does_not_mutate_source_image_objects(self) -> None:
        frames = self._tail_frames()
        before = [frame.tobytes() for frame in frames]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with mock.patch.object(audit, "load_frames", return_value=(root / "unused.png", frames)):
                audit.audit_animation("fixture", {}, root, {"center_metric": "core"}, [],
                                      root / "review", False, None, [])
        self.assertEqual([frame.tobytes() for frame in frames], before)


if __name__ == "__main__":
    unittest.main()
