from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.character_motion_acceptance_gate import (  # noqa: E402
    CANONICAL_DIRECTIONS,
    REVIEW_FLAGS,
    audit_locomotion_mattes,
    audit_per_frame_geometry,
    frame_has_opaque_rectangular_matte,
    prepare_review_artifacts,
    sha256_file,
    validate_manual_review,
    validate_prompt_provenance,
)


class CharacterMotionAcceptanceGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.project_root = Path(self.temp.name)
        self.character = "test-mouse"
        self.character_root = self.project_root / "output" / "character-motion" / self.character
        self.source_root = self.character_root / "source"
        self.runtime_root = self.character_root / "runtime"
        self.source_root.mkdir(parents=True)
        self.runtime_root.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def _transparent_sprite(size: int = 64, offset: int = 0) -> Image.Image:
        image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.ellipse((16 + offset, 8, 47 + offset, 55), fill=(165, 110, 72, 255))
        draw.rectangle((22 + offset, 40, 28 + offset, 60), fill=(55, 45, 40, 255))
        draw.rectangle((35 + offset, 40, 41 + offset, 57), fill=(55, 45, 40, 255))
        return image

    def _write_strip(self, path: Path, frames: list[Image.Image]) -> None:
        strip = Image.new("RGBA", (sum(frame.width for frame in frames), frames[0].height), (0, 0, 0, 0))
        x = 0
        for frame in frames:
            strip.alpha_composite(frame, (x, 0))
            x += frame.width
        path.parent.mkdir(parents=True, exist_ok=True)
        strip.save(path)

    def _fixture(self) -> tuple[dict, dict]:
        walk_path = self.runtime_root / "walk.png"
        idle_path = self.runtime_root / "idle.png"
        self._write_strip(walk_path, [self._transparent_sprite(offset=index % 2) for index in range(8)])
        self._write_strip(idle_path, [self._transparent_sprite(), self._transparent_sprite(offset=1)])

        motion_spec = {
            "version": 1,
            "character": self.character,
            "animations": {
                "walk_east": {
                    "path": walk_path.relative_to(self.project_root).as_posix(),
                    "frame_width": 64,
                    "frame_height": 64,
                    "frame_count": 8,
                    "role": "gait",
                    "fps": 10,
                },
                "idle_east": {
                    "path": idle_path.relative_to(self.project_root).as_posix(),
                    "frame_width": 64,
                    "frame_height": 64,
                    "frame_count": 2,
                    "role": "directional_idle",
                    "fps": 1,
                },
            },
            "directions": {
                direction: {
                    "walk_animation": "walk_east",
                    "idle_animation": "idle_east",
                    "mirror_x": direction in {"west", "southwest", "northwest"},
                }
                for direction in CANONICAL_DIRECTIONS
            },
            "gait": {
                "pose_order": [
                    "left_contact",
                    "left_weight_down",
                    "right_passing",
                    "right_knee_up",
                    "right_contact",
                    "right_weight_down",
                    "left_passing",
                    "left_knee_up",
                ]
            },
        }

        walk_source = self.source_root / "walk-reviewed.png"
        idle_source = self.source_root / "idle-reviewed.png"
        shutil.copyfile(walk_path, walk_source)
        shutil.copyfile(idle_path, idle_source)
        build_manifest = {
            "version": 1,
            "character": self.character,
            "source_root": self.source_root.relative_to(self.project_root).as_posix(),
            "idle_sets": [{"source": idle_source.name}],
            "walks": {"walk.png": {"source": walk_source.name}},
        }
        return motion_spec, build_manifest

    def _write_audit_evidence(self) -> None:
        contact_root = self.character_root / "audit" / "contact-sheets"
        contact_root.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (32, 32), "navy").save(contact_root / "walk_east.png")
        Image.new("RGB", (32, 32), "teal").save(contact_root / "idle_east.png")
        (self.character_root / "audit" / "report.json").write_text(
            json.dumps({"summary": {"errors": 0, "warnings": 0}, "issues": []}), encoding="utf-8"
        )
        sprite_root = self.character_root / "sprite-doctor"
        sprite_root.mkdir(parents=True, exist_ok=True)
        (sprite_root / "report.json").write_text(
            json.dumps({"summary": {"errors": 0, "warnings": 1}, "issues": [
                {"severity": "warning", "action": "sit", "code": "legacy_duplicate"}
            ]}),
            encoding="utf-8",
        )

    def test_detects_baked_checkerboard_and_nearly_solid_matte(self) -> None:
        checkerboard = Image.new("RGBA", (64, 64), (0, 0, 0, 255))
        draw = ImageDraw.Draw(checkerboard)
        for y in range(0, 64, 8):
            for x in range(0, 64, 8):
                color = (210, 210, 210, 255) if (x // 8 + y // 8) % 2 else (245, 245, 245, 255)
                draw.rectangle((x, y, x + 7, y + 7), fill=color)
        suspicious, _ = frame_has_opaque_rectangular_matte(checkerboard)
        self.assertTrue(suspicious)

        matte = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        ImageDraw.Draw(matte).rectangle((8, 8, 55, 55), fill=(255, 0, 255, 255))
        matte.putpixel((20, 20), (0, 0, 0, 0))
        matte.putpixel((21, 20), (0, 0, 0, 0))
        suspicious, metrics = frame_has_opaque_rectangular_matte(matte)
        self.assertTrue(suspicious)
        self.assertGreater(metrics["opaque_fill_ratio"], 0.99)

    def test_transparent_character_silhouette_is_not_a_rectangular_matte(self) -> None:
        suspicious, metrics = frame_has_opaque_rectangular_matte(self._transparent_sprite())
        self.assertFalse(suspicious)
        self.assertLess(metrics["opaque_fill_ratio"], 0.97)

    def test_locomotion_audit_reports_only_the_bad_frame(self) -> None:
        frames = [self._transparent_sprite() for _ in range(8)]
        frames[3] = Image.new("RGBA", (64, 64), (230, 230, 230, 255))
        walk_path = self.runtime_root / "walk.png"
        self._write_strip(walk_path, frames)
        spec = {
            "animations": {
                "walk_east": {
                    "path": walk_path.relative_to(self.project_root).as_posix(),
                    "frame_width": 64,
                    "frame_height": 64,
                    "frame_count": 8,
                    "role": "gait",
                }
            }
        }
        issues = audit_locomotion_mattes(spec, self.project_root)
        self.assertEqual([issue.code for issue in issues], ["opaque_rectangular_matte_or_checkerboard"])
        self.assertIn("frames[4]", issues[0].location)

    def test_per_frame_scale_allows_only_small_uniform_normalization(self) -> None:
        safe = {"walks": {"walk.png": {"frame_adjustments": {
            "1": {"scale_x": 1.04, "scale_y": 1.04},
            "2": {"scale_x": 1.030, "scale_y": 1.034},
        }}}}
        self.assertEqual(audit_per_frame_geometry(safe), [])

        unsafe = {"walks": {"walk.png": {"frame_adjustments": {
            "1": {"scale_x": 0.747},
            "2": {"scale_x": 1.051, "scale_y": 1.051},
            "3": {"rotation": 2},
        }}}}
        codes = {issue.code for issue in audit_per_frame_geometry(unsafe)}
        self.assertIn("anisotropic_per_frame_scale", codes)
        self.assertIn("excessive_per_frame_scale", codes)
        self.assertIn("dangerous_per_frame_geometry", codes)

    def test_prompt_provenance_requires_candid_reconstruction_and_covers_sources(self) -> None:
        _, build = self._fixture()
        artifacts = []
        for name in ("walk-reviewed.png", "idle-reviewed.png"):
            path = self.source_root / name
            artifacts.append({
                "path": path.relative_to(self.project_root).as_posix(),
                "sha256": sha256_file(path),
            })
        provenance = {
            "version": 1,
            "character": self.character,
            "records": [{
                "id": "reconstructed-generation",
                "capture": "reconstructed",
                "prompt_text": "Faithfully reconstructed prompt.",
                "reconstruction_notes": "Original call text unavailable; this is not verbatim.",
                "artifacts": artifacts,
            }],
        }
        self.assertEqual(
            validate_prompt_provenance(
                provenance,
                character=self.character,
                build_manifest=build,
                project_root=self.project_root,
                character_root=self.character_root,
            ),
            [],
        )

        provenance["records"][0]["verbatim"] = True
        codes = {
            issue.code
            for issue in validate_prompt_provenance(
                provenance,
                character=self.character,
                build_manifest=build,
                project_root=self.project_root,
                character_root=self.character_root,
            )
        }
        self.assertIn("reconstructed_prompt_claimed_verbatim", codes)

    def test_prepare_review_creates_half_speed_gif_and_half_cycle_sheet(self) -> None:
        spec, _ = self._fixture()
        self._write_audit_evidence()
        template_path, issues = prepare_review_artifacts(spec, self.project_root, self.character_root)
        self.assertEqual(issues, [])
        one_x = self.character_root / "semantic-review" / "previews-1x" / "walk_east.gif"
        half = self.character_root / "semantic-review" / "previews-half-speed" / "walk_east.gif"
        comparison = self.character_root / "semantic-review" / "half-cycle-sheets" / "walk_east.png"
        self.assertTrue(template_path.is_file())
        self.assertTrue(comparison.is_file())
        with Image.open(one_x) as image:
            self.assertEqual(image.n_frames, 8)
            self.assertEqual(image.info["duration"], 100)
        with Image.open(half) as image:
            self.assertEqual(image.n_frames, 8)
            self.assertEqual(image.info["duration"], 200)

    def test_complete_hash_bound_manual_review_passes(self) -> None:
        spec, _ = self._fixture()
        self._write_audit_evidence()
        template_path, issues = prepare_review_artifacts(spec, self.project_root, self.character_root)
        self.assertEqual(issues, [])
        review = json.loads(template_path.read_text(encoding="utf-8"))
        review.update({
            "status": "accepted",
            "reviewer": "visual-reviewer",
            "reviewed_on": "2026-09-09",
            "overall_notes": "All directions were reviewed against the identity reference.",
        })
        for direction in CANONICAL_DIRECTIONS:
            review["directions"][direction].update({flag: True for flag in REVIEW_FLAGS})
            review["directions"][direction]["notes"] = "Contacts alternate and equipment remains body-fixed."
        self.assertEqual(
            validate_manual_review(
                review,
                motion_spec=spec,
                project_root=self.project_root,
                character_root=self.character_root,
            ),
            [],
        )

    def test_manual_review_rejects_external_or_stale_evidence(self) -> None:
        spec, _ = self._fixture()
        self._write_audit_evidence()
        template_path, _ = prepare_review_artifacts(spec, self.project_root, self.character_root)
        review = json.loads(template_path.read_text(encoding="utf-8"))
        review.update({
            "status": "accepted",
            "reviewer": "visual-reviewer",
            "reviewed_on": "2026-09-09",
            "overall_notes": "Reviewed.",
        })
        for direction in CANONICAL_DIRECTIONS:
            review["directions"][direction].update({flag: True for flag in REVIEW_FLAGS})
            review["directions"][direction]["notes"] = "Reviewed."
        external = self.project_root / "unrelated.png"
        Image.new("RGB", (4, 4), "red").save(external)
        review["directions"]["north"]["evidence"]["preview_1x"] = {
            "path": external.relative_to(self.project_root).as_posix(),
            "sha256": sha256_file(external),
        }
        external_report = self.project_root / "unrelated-report.json"
        external_report.write_text(
            json.dumps({"summary": {"errors": 0, "warnings": 0}, "issues": []}),
            encoding="utf-8",
        )
        review["reports"]["motion_audit"] = {
            "path": external_report.relative_to(self.project_root).as_posix(),
            "sha256": sha256_file(external_report),
        }
        half = self.character_root / "semantic-review" / "previews-half-speed" / "walk_east.gif"
        half.write_bytes(half.read_bytes() + b"changed")

        codes = {
            issue.code
            for issue in validate_manual_review(
                review,
                motion_spec=spec,
                project_root=self.project_root,
                character_root=self.character_root,
            )
        }
        self.assertIn("non_character_local_evidence", codes)
        self.assertIn("wrong_direction_evidence", codes)
        self.assertIn("wrong_review_report", codes)
        self.assertIn("stale_evidence_hash", codes)


if __name__ == "__main__":
    unittest.main()
