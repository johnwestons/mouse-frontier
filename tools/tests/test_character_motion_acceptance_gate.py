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
    audit_source_resolution_normalization,
    audit_current_motion_evidence,
    frame_has_opaque_rectangular_matte,
    prepare_review_artifacts,
    sha256_file,
    validate_manual_review,
    validate_prompt_provenance,
    validate_sprite_doctor_inputs,
    validate_motion_center_contract,
    validate_motion_center_metrics,
    split_animation_frames,
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
            ], "audited_inputs": [
                {"character": self.character, "action": path.stem,
                 "path": path.relative_to(self.project_root).as_posix(), "sha256": sha256_file(path)}
                for path in sorted(self.runtime_root.glob("*.png"))
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

    def _resolution_fixture(self) -> tuple[dict, dict]:
        _, build = self._fixture()
        replacement = self._transparent_sprite().resize((192, 192), Image.Resampling.NEAREST)
        replacement.save(self.source_root / "high-resolution-phase.png")
        entry = {"source": "high-resolution-phase.png", "resolution_normalization": {
            "mode": "reviewed_visible_height", "source_visible_height": 159, "target_visible_height": 53,
        }}
        build["walks"]["walk.png"].update({"fixed_grid": True, "frame_sources": [entry] + [None] * 7})
        return build, entry

    def test_high_resolution_replacement_is_not_a_body_scale_error(self) -> None:
        build, entry = self._resolution_fixture()
        self.assertEqual(audit_source_resolution_normalization(build, self.project_root), [])
        entry["resolution_normalization"] = "match_base_visible_height"
        self.assertEqual(audit_source_resolution_normalization(build, self.project_root), [])

    def test_reviewed_height_cannot_bypass_body_scale_limit(self) -> None:
        build, entry = self._resolution_fixture()
        entry["resolution_normalization"]["target_visible_height"] = 53 * 1.07
        codes = {issue.code for issue in audit_source_resolution_normalization(build, self.project_root)}
        self.assertIn("excessive_resolution_body_scale", codes)
        entry["resolution_normalization"].update({"source_visible_height": 159 / 1.07, "target_visible_height": 53})
        codes = {issue.code for issue in audit_source_resolution_normalization(build, self.project_root)}
        self.assertIn("unverified_source_resolution_height", codes)
        self.assertIn("excessive_resolution_body_scale", codes)

    def test_resolution_and_frame_corrections_share_one_scale_budget(self) -> None:
        build, entry = self._resolution_fixture()
        entry["resolution_normalization"]["target_visible_height"] = 53 * 1.03
        build["walks"]["walk.png"]["frame_adjustments"] = {"1": {"scale_x": 1.03, "scale_y": 1.03}}
        self.assertEqual(audit_per_frame_geometry(build), [])
        codes = {issue.code for issue in audit_source_resolution_normalization(build, self.project_root)}
        self.assertIn("excessive_resolution_body_scale", codes)

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

        provenance["records"][0].pop("verbatim")
        shutil.copyfile(self.source_root / "walk-reviewed.png", self.source_root / "override.png")
        build["walks"]["walk.png"]["frame_sources"] = [{"source": "override.png", "resolution_normalization": "match_base_visible_height"}] + [None] * 7
        codes = {issue.code for issue in validate_prompt_provenance(provenance, character=self.character, build_manifest=build, project_root=self.project_root, character_root=self.character_root)}
        self.assertIn("build_source_without_prompt_provenance", codes)

    def test_mechanical_derivation_requires_hash_bound_ancestry(self) -> None:
        _, build = self._fixture()
        def ref(path):
            return {'path': path.relative_to(self.project_root).as_posix(), 'sha256': sha256_file(path)}
        source = self.source_root / 'walk-reviewed.png'
        derived = self.source_root / 'layered-walk.png'
        shutil.copyfile(source, derived)
        tooling = self.source_root / 'rig.lua'
        tooling.write_text('-- retained authoring fixture')
        build['walks']['walk.png']['source'] = derived.name
        provenance = {'version': 1, 'character': self.character, 'records': [{
            'id': 'source', 'capture': 'exact', 'capture_source': 'test fixture',
            'prompt_text': 'Original fixture prompt',
            'artifacts': [ref(source), ref(self.source_root / 'idle-reviewed.png')]}],
            'derivations': [{'id': 'layered', 'kind': 'layered_2d_authoring',
                'method': 'Bake leg articulation while preserving source body pixels',
                'inputs': [ref(source)], 'tooling': [ref(tooling)], 'outputs': [ref(derived)]}]}
        def check():
            return validate_prompt_provenance(provenance, character=self.character, build_manifest=build,
                                             project_root=self.project_root, character_root=self.character_root)
        self.assertEqual(check(), [])
        provenance['derivations'][0]['inputs'] = [ref(derived)]
        self.assertIn('unproven_derived_input', {i.code for i in check()})
        provenance['derivations'][0]['inputs'] = [ref(source)]
        tooling.write_text('-- changed after review')
        self.assertIn('stale_evidence_hash', {i.code for i in check()})
        self.assertIn('build_source_without_prompt_provenance', {i.code for i in check()})

    def test_running_requires_its_own_review_flags_and_previews(self) -> None:
        from tools.character_gait_contract import RUN_PHASES
        from tools.character_motion_acceptance_gate import RUN_REVIEW_FLAGS
        spec, _ = self._fixture()
        run_path = self.runtime_root / 'run.png'
        shutil.copyfile(self.runtime_root / 'walk.png', run_path)
        spec['animations']['run_east'] = {**spec['animations']['walk_east'],
            'path': run_path.relative_to(self.project_root).as_posix(), 'pose_order': RUN_PHASES,
            'gait_kind': 'run', 'ground_clearance': [0, 0, 2, 1] * 2}
        spec['directions']['east']['run_animation'] = 'run_east'
        self._write_audit_evidence()
        shutil.copyfile(self.character_root / 'audit/contact-sheets/walk_east.png',
                        self.character_root / 'audit/contact-sheets/run_east.png')
        path, errors = prepare_review_artifacts(spec, self.project_root, self.character_root)
        self.assertEqual(errors, [])
        review = json.loads(path.read_text())
        entry = review['directions']['east']
        self.assertTrue(all(entry[flag] is False for flag in RUN_REVIEW_FLAGS))
        self.assertTrue((self.character_root / 'semantic-review/previews-half-speed/run_east.gif').is_file())
        issues = validate_manual_review(review, motion_spec=spec, project_root=self.project_root,
                                        character_root=self.character_root)
        locations = {i.location for i in issues if i.code == 'semantic_review_flag_not_accepted'}
        self.assertTrue(all('directions.east.' + flag in locations for flag in RUN_REVIEW_FLAGS))

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

    def test_review_binds_sprite_bytes_spec_and_build_manifest(self) -> None:
        spec, build = self._fixture()
        self._write_audit_evidence()
        template_path, _ = prepare_review_artifacts(spec, self.project_root, self.character_root, build_manifest=build)
        review = json.loads(template_path.read_text(encoding="utf-8"))
        with Image.open(self.runtime_root / "walk.png") as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((30, 30), (110, 80, 20, 255))
        changed.save(self.runtime_root / "walk.png")
        spec["directions"]["north"]["mirror_x"] = True
        build["walks"]["walk.png"]["source_frame_indices"] = list(reversed(range(8)))
        codes = {issue.code for issue in validate_manual_review(review, motion_spec=spec, project_root=self.project_root, character_root=self.character_root, build_manifest=build)}
        self.assertIn("stale_evidence_hash", codes)
        self.assertIn("stale_review_motion_spec", codes)
        self.assertIn("stale_review_build_manifest", codes)

    def test_audit_input_verification_rejects_stale_metrics_and_contact_pixels(self) -> None:
        spec, _ = self._fixture()
        self._write_audit_evidence()
        report_path = self.character_root / "audit" / "report.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["animations"] = []
        for name, definition in spec["animations"].items():
            metrics = []
            for index, frame in enumerate(split_animation_frames(definition, self.project_root), 1):
                alpha = frame.getchannel("A")
                metrics.append({"frame": index, "bbox": list(alpha.getbbox()), "visible_pixels": sum(alpha.histogram()[17:])})
            report["animations"].append({"name": name, "path": definition["path"], "frames": metrics})
        report_path.write_text(json.dumps(report), encoding="utf-8")
        # Correct metrics cannot legitimize unrelated contact-sheet art.
        codes = {issue.code for issue in audit_current_motion_evidence(spec, self.project_root, self.character_root)}
        self.assertIn("stale_motion_contact_sheet", codes)
        self.assertNotIn("stale_motion_audit_inputs", codes)
        report["animations"][0]["frames"][0]["visible_pixels"] += 1
        report_path.write_text(json.dumps(report), encoding="utf-8")
        codes = {issue.code for issue in audit_current_motion_evidence(spec, self.project_root, self.character_root)}
        self.assertIn("stale_motion_audit_inputs", codes)

    def test_core_center_contract_requires_matching_build_and_threshold(self) -> None:
        self.assertEqual(validate_motion_center_contract({}, {}), [])
        spec = {"audit": {"center_metric": "core", "alpha_threshold": 16}}
        self.assertIn("motion_center_contract_mismatch", {i.code for i in validate_motion_center_contract(spec, {})})
        build = {"framing": {"horizontal_anchor": "core"}}
        self.assertEqual(validate_motion_center_contract(spec, build), [])
        mixed = {**build, "walks": {"walk.png": {"horizontal_anchor": "bbox"}}}
        self.assertIn("motion_center_contract_mismatch", {i.code for i in validate_motion_center_contract(spec, mixed)})
        legacy_idle = {**build, "idle": {"horizontal_anchor": "bbox"}}
        self.assertIn("motion_center_contract_mismatch", {i.code for i in validate_motion_center_contract(spec, legacy_idle)})
        legacy_idle["idle_sets"] = []
        self.assertIn("motion_center_contract_mismatch", {i.code for i in validate_motion_center_contract(spec, legacy_idle)})
        spec["audit"]["alpha_threshold"] = 24
        self.assertIn("invalid_core_alpha_threshold", {i.code for i in validate_motion_center_contract(spec, build)})
        spec["audit"]["center_metric"] = "tail"
        self.assertIn("invalid_motion_center_metric", {i.code for i in validate_motion_center_contract(spec, build)})

    def test_core_center_evidence_is_recomputed_and_cannot_hide_drift(self) -> None:
        from tools.build_directional_character_assets import core_horizontal_anchor_x, visible_bbox
        frames = [self._transparent_sprite(), self._transparent_sprite(offset=1)]
        settings = {"center_metric": "core", "center_tolerance": 6}
        positions = [core_horizontal_anchor_x(frame, visible_bbox(frame)) for frame in frames]
        bbox_positions = [(visible_bbox(frame)[0] + visible_bbox(frame)[2]) / 2 for frame in frames]
        record = {"center_metrics": {"metric": "core", "positions": positions, "bbox_positions": bbox_positions, "tolerance": 6}}
        before = [frame.tobytes() for frame in frames]
        self.assertEqual(validate_motion_center_metrics(record, frames, settings, "test"), [])
        record["center_metrics"]["tolerance"] = 1000
        self.assertIn("stale_motion_center_metrics", {i.code for i in validate_motion_center_metrics(record, frames, settings, "test")})
        record["center_metrics"]["tolerance"] = 6
        record["center_metrics"]["positions"] = [0, 0]
        shifted = [frames[0], self._transparent_sprite(offset=10)]
        codes = {i.code for i in validate_motion_center_metrics(record, shifted, settings, "test")}
        self.assertIn("stale_motion_center_metrics", codes)
        self.assertIn("motion_core_center_jitter", codes)
        self.assertEqual([frame.tobytes() for frame in frames], before)

    def test_sprite_doctor_must_hash_the_current_staged_locomotion(self) -> None:
        spec, _ = self._fixture()
        self._write_audit_evidence()
        report = json.loads((self.character_root / "sprite-doctor" / "report.json").read_text(encoding="utf-8"))
        self.assertEqual(validate_sprite_doctor_inputs(report, spec, self.project_root, self.character_root), [])
        self.assertIn("missing_sprite_doctor_input_hashes", {issue.code for issue in validate_sprite_doctor_inputs({}, spec, self.project_root, self.character_root)})
        # Installed audit evidence is valid only when it describes identical bytes.
        installed = self.project_root / "assets" / "sprites" / "character-animations" / self.character
        installed.mkdir(parents=True)
        for reference in report["audited_inputs"]:
            destination = installed / f"{reference['action']}.png"
            shutil.copyfile(self.project_root / reference["path"], destination)
            reference["path"] = destination.relative_to(self.project_root).as_posix()
        self.assertEqual(validate_sprite_doctor_inputs(report, spec, self.project_root, self.character_root), [])
        with Image.open(self.runtime_root / "walk.png") as source:
            changed = source.convert("RGBA")
        changed.putpixel((30, 30), (25, 40, 80, 255))
        changed.save(self.runtime_root / "walk.png")
        codes = {issue.code for issue in validate_sprite_doctor_inputs(report, spec, self.project_root, self.character_root)}
        self.assertIn("stale_sprite_doctor_input", codes)

    def test_doctor_framing_must_match_the_current_build_manifest(self) -> None:
        from tools.character_sprite_doctor import SpriteDoctor
        spec, build = self._fixture()
        self._write_audit_evidence()
        build["idle_sets"][0]["outputs"] = ["idle.png"]
        build["framing"] = {"horizontal_anchor": "core"}
        path = self.project_root / "character-motion" / f"{self.character}-build.json"
        path.parent.mkdir()
        path.write_text(json.dumps(build), encoding="utf-8")
        report = json.loads((self.character_root / "sprite-doctor" / "report.json").read_text(encoding="utf-8"))
        report["framing_contract"] = SpriteDoctor(self.project_root, build_manifest=path).framing_contract
        self.assertEqual(validate_sprite_doctor_inputs(report, spec, self.project_root, self.character_root, build), [])
        report["framing_contract"]["actions"]["walk"]["center_x"] = 200
        codes = {issue.code for issue in validate_sprite_doctor_inputs(report, spec, self.project_root, self.character_root, build)}
        self.assertIn("wrong_sprite_doctor_framing_measurements", codes)
        other = {**build, "framing": {"horizontal_anchor": "bbox", "center_x": 200}}
        path.write_text(json.dumps(other), encoding="utf-8")
        report["framing_contract"] = SpriteDoctor(self.project_root, build_manifest=path).framing_contract
        codes = {issue.code for issue in validate_sprite_doctor_inputs(report, spec, self.project_root, self.character_root, build)}
        self.assertIn("wrong_sprite_doctor_framing_contract", codes)


if __name__ == "__main__":
    unittest.main()
