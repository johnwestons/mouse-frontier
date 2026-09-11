from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from tools.build_directional_character_assets import (
    apply_frame_source_overrides,
    build,
    core_horizontal_anchor_x,
    keep_primary_component,
    normalize_strip,
    remove_edge_connected_checker_matte,
    remove_edge_connected_magenta_fringe_pixels,
    reorder_walk_source_frames,
    sha256,
    visible_bbox,
    visible_height_for_resolution_normalization,
)


class DirectionalCharacterAssetBuilderTests(unittest.TestCase):
    @staticmethod
    def _magenta_fringed_subject() -> Image.Image:
        image = Image.new("RGBA", (48, 48), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.rectangle((8, 6, 34, 41), fill=(108, 8, 112, 255))
        draw.rectangle((9, 7, 33, 40), fill=(8, 8, 8, 255))
        draw.rectangle((11, 9, 31, 38), fill=(20, 105, 230, 255))
        draw.rectangle((17, 17, 24, 24), fill=(112, 4, 116, 255))
        draw.rectangle((14, 29, 25, 35), fill=(235, 120, 20, 255))
        return image

    def test_connected_magenta_fringe_removal_preserves_enclosed_art_and_outline(self) -> None:
        image = self._magenta_fringed_subject()
        image.putpixel((27, 14), (255, 0, 255, 255))
        before = image.tobytes()
        cleaned = remove_edge_connected_magenta_fringe_pixels(image)
        self.assertEqual(image.tobytes(), before)
        self.assertEqual(cleaned.getpixel((8, 20)), (0, 0, 0, 0))
        for position in [(9, 20), (12, 20), (20, 20), (20, 32), (27, 14)]:
            self.assertEqual(cleaned.getpixel(position), image.getpixel(position))
        self.assertEqual(cleaned.getpixel((20, 20)), (112, 4, 116, 255))

    def test_magenta_cleanup_cannot_cross_a_diagonal_one_pixel_outline(self) -> None:
        image = Image.new("RGBA", (25, 25), (108, 8, 112, 255))
        ImageDraw.Draw(image).polygon(((12, 2), (22, 12), (12, 22), (2, 12)), outline=(8, 8, 8, 255))
        cleaned = remove_edge_connected_magenta_fringe_pixels(image)
        self.assertEqual(cleaned.getpixel((0, 0)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((12, 12)), image.getpixel((12, 12)))

    def test_magenta_cleanup_is_opt_in_and_reports_removal_counts(self) -> None:
        image = self._magenta_fringed_subject()
        options = dict(frame_size=48, target_height=36, max_width=44, center_x=24, baseline=42)
        default, default_report = normalize_strip([image], **options)
        unchanged, _ = normalize_strip([image], **options, remove_edge_connected_magenta_fringe=False)
        cleaned, report = normalize_strip([image], **options, remove_edge_connected_magenta_fringe=True)
        self.assertEqual(default.tobytes(), unchanged.tobytes())
        self.assertFalse(default_report["remove_edge_connected_magenta_fringe"])
        self.assertNotEqual(default.tobytes(), cleaned.tobytes())
        self.assertTrue(report["remove_edge_connected_magenta_fringe"])
        self.assertEqual(report["magenta_matte_and_fringe_removed_pixels"], [122])
        self.assertEqual(report["edge_connected_magenta_fringe_removed_pixels"], [122])
        rgba = np.asarray(cleaned)
        self.assertTrue(np.any(np.all(rgba == (112, 4, 116, 255), axis=2)), "normalization must also preserve enclosed dark magenta when opted in")
        self.assertEqual(visible_height_for_resolution_normalization(image, remove_edge_connected_magenta_fringe=True), 34)
        with self.assertRaisesRegex(ValueError, "must be a boolean"):
            normalize_strip([image], **options, remove_edge_connected_magenta_fringe="yes")

    def test_build_propagates_magenta_option_and_measures_replacements_consistently(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            sprite = self._magenta_fringed_subject()
            atlas = Image.new("RGBA", (48 * 8, 48))
            for index in range(8):
                atlas.alpha_composite(sprite, (index * 48, 0))
            atlas.save(source / "walk.png")
            idle = Image.new("RGBA", (48, 96))
            idle.alpha_composite(sprite)
            idle.alpha_composite(sprite, (0, 48))
            idle.save(source / "idle.png")
            sprite.resize((96, 96), Image.Resampling.NEAREST).save(source / "replacement.png")
            original_hashes = {path.name: sha256(path) for path in source.glob("*.png")}
            manifest = {
                "version": 1, "character": "test-frog", "source_root": str(source), "runtime_root": str(root / "runtime"),
                "framing": {"frame_size": 48, "target_height": 36, "max_width": 44, "center_x": 24, "baseline": 42, "remove_edge_connected_magenta_fringe": True},
                "idle_sets": [{"source": "idle.png", "outputs": ["idle.png"], "fixed_grid": True, "remove_edge_connected_magenta_fringe": False}],
                "walks": {"walk.png": {"source": "walk.png", "fixed_grid": True, "frame_sources": [None, None, {"source": "replacement.png", "resolution_normalization": "match_base_visible_height"}] + [None] * 5}},
            }
            path = root / "build.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            report = build(path)
            self.assertTrue(report["default_remove_edge_connected_magenta_fringe"])
            self.assertFalse(report["outputs"]["idle.png"]["remove_edge_connected_magenta_fringe"])
            walk = report["outputs"]["walk.png"]
            self.assertTrue(walk["remove_edge_connected_magenta_fringe"])
            normalization = walk["frame_source_overrides"][0]["resolution_normalization"]
            self.assertEqual(normalization["source_visible_height"], 68)
            self.assertEqual(normalization["target_visible_height"], 34)
            self.assertEqual(normalization["uniform_scale"], 0.5)
            self.assertEqual(walk["edge_connected_magenta_fringe_removed_pixels"][2], 488)
            self.assertEqual(original_hashes, {path.name: sha256(path) for path in source.glob("*.png")})

    @staticmethod
    def _checker_backed_subject() -> Image.Image:
        image = Image.new("RGBA", (96, 96), (0, 0, 0, 255))
        draw = ImageDraw.Draw(image)
        for y in range(0, 96, 8):
            for x in range(0, 96, 8):
                color = (252, 253, 252, 255) if (x // 8 + y // 8) % 2 else (207, 208, 210, 255)
                draw.rectangle((x, y, x + 7, y + 7), fill=color)

        # Near-white clothing is deliberately checker-like in color, but its
        # dark outline makes it enclosed subject art rather than background.
        draw.rectangle((24, 14, 60, 78), fill=(22, 18, 16, 255))
        draw.rectangle((28, 18, 56, 74), fill=(248, 247, 244, 255))
        draw.rectangle((35, 38, 49, 70), fill=(170, 75, 40, 255))

        # Detached silver equipment is also bright-neutral and must survive.
        draw.rectangle((68, 32, 87, 57), fill=(18, 17, 16, 255))
        draw.rectangle((72, 36, 83, 53), fill=(220, 221, 219, 255))
        return image

    @staticmethod
    def _tailed_frame(tail_side: str) -> Image.Image:
        image = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        if tail_side == "left":
            draw.rectangle((7, 48, 43, 54), fill=(35, 90, 210, 255))
        else:
            draw.rectangle((57, 48, 92, 54), fill=(35, 90, 210, 255))
        draw.rectangle((42, 20, 58, 65), fill=(220, 45, 35, 255))
        draw.rectangle((44, 12, 56, 24), fill=(220, 45, 35, 255))
        draw.rectangle((43, 65, 48, 80), fill=(220, 45, 35, 255))
        draw.rectangle((52, 65, 57, 80), fill=(220, 45, 35, 255))
        return image

    @staticmethod
    def _color_center_x(image: Image.Image, color: str) -> float:
        rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)
        if color == "red":
            mask = (rgba[:, :, 0] > 180) & (rgba[:, :, 1] < 80)
        else:
            mask = (rgba[:, :, 1] > 180) & (rgba[:, :, 0] < 80)
        _, xs = np.where(mask)
        if len(xs) == 0:
            raise AssertionError(f"No {color} test pixels found")
        return (float(xs.min()) + float(xs.max())) / 2

    @staticmethod
    def _strip_frame(strip: Image.Image, index: int, frame_size: int) -> Image.Image:
        return strip.crop((index * frame_size, 0, (index + 1) * frame_size, frame_size))

    def test_core_anchor_keeps_torso_fixed_while_long_tail_swings(self) -> None:
        frames = [self._tailed_frame("left"), self._tailed_frame("right")]

        bbox_strip, _ = normalize_strip(
            frames,
            frame_size=128,
            target_height=80,
            max_width=110,
            center_x=64,
            baseline=112,
            horizontal_anchor="bbox",
        )
        bbox_centers = [
            self._color_center_x(self._strip_frame(bbox_strip, index, 128), "red")
            for index in range(2)
        ]
        self.assertGreater(abs(bbox_centers[0] - bbox_centers[1]), 20)

        core_strip, report = normalize_strip(
            frames,
            frame_size=128,
            target_height=80,
            max_width=110,
            center_x=64,
            baseline=112,
            horizontal_anchor="core",
        )
        core_frames = [self._strip_frame(core_strip, index, 128) for index in range(2)]
        core_centers = [self._color_center_x(frame, "red") for frame in core_frames]
        self.assertAlmostEqual(core_centers[0], core_centers[1], delta=1.0)
        self.assertAlmostEqual(core_centers[0], 64, delta=1.0)
        self.assertEqual([visible_bbox(frame)[3] for frame in core_frames], [112, 112])
        self.assertEqual(report["horizontal_anchor"], "core")
        for frame_report in report["normalized_frames"]:
            self.assertAlmostEqual(frame_report["output_anchor_x"], 64, delta=0.5)

    def test_core_anchor_is_measured_after_pixel_resampling(self) -> None:
        frame = Image.new("RGBA", (48, 48))
        draw = ImageDraw.Draw(frame)
        draw.rectangle((10, 4, 30, 40), fill=(40, 100, 190, 255))
        draw.rectangle((30, 28, 44, 32), fill=(40, 100, 190, 255))
        original = frame.tobytes()
        for height in (21, 39):
            with self.subTest(height=height):
                strip, report = normalize_strip(
                    [frame], 96, height, 70, 48, 80, horizontal_anchor="core"
                )
                measured = core_horizontal_anchor_x(strip, visible_bbox(strip))
                self.assertEqual(measured, 48)
                self.assertEqual(report["normalized_frames"][0]["output_anchor_x"], measured)
                self.assertEqual(visible_bbox(strip)[3], 80)
        self.assertEqual(frame.tobytes(), original)

    def test_core_anchor_rejects_extensions_that_would_be_clipped(self) -> None:
        frame = self._tailed_frame("left")
        with self.assertRaisesRegex(ValueError, "would clip after core anchoring"):
            normalize_strip(
                [frame],
                frame_size=64,
                target_height=60,
                max_width=64,
                center_x=32,
                baseline=62,
                horizontal_anchor="core",
            )

    def test_deprecated_primary_component_cleanup_rejects_detached_equipment(self) -> None:
        image = Image.new("RGBA", (80, 80), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.rectangle((20, 10, 45, 65), fill=(150, 95, 55, 255))
        draw.rectangle((53, 30, 61, 45), fill=(220, 180, 40, 255))
        before = image.tobytes()

        with self.assertRaisesRegex(ValueError, "deprecated and cannot safely choose"):
            keep_primary_component(image)

        self.assertEqual(image.tobytes(), before, "validation must not alter detached equipment")

    def test_edge_checker_cleanup_preserves_subject_and_detached_equipment(self) -> None:
        image = self._checker_backed_subject()
        before = image.tobytes()

        cleaned = remove_edge_connected_checker_matte(image)

        self.assertEqual(image.tobytes(), before, "background cleanup must not mutate source art")
        self.assertEqual(cleaned.getpixel((4, 4)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((40, 24)), image.getpixel((40, 24)))
        self.assertEqual(cleaned.getpixel((77, 44)), image.getpixel((77, 44)))
        self.assertEqual(cleaned.getpixel((68, 44)), image.getpixel((68, 44)))
        alpha = np.asarray(cleaned.getchannel("A"), dtype=np.uint8)
        self.assertGreater(np.count_nonzero(alpha == 0), image.width * image.height * 0.65)

        _, report = normalize_strip(
            [image],
            frame_size=96,
            target_height=64,
            max_width=88,
            center_x=48,
            baseline=88,
            remove_edge_connected_checker=True,
        )
        self.assertTrue(report["remove_edge_connected_checker"])
        self.assertGreater(report["edge_connected_checker_removed_pixels"][0], 0)

    def test_edge_checker_cleanup_does_not_erase_colored_edge_regions(self) -> None:
        image = Image.new("RGBA", (24, 24), (35, 90, 210, 255))
        cleaned = remove_edge_connected_checker_matte(image)
        self.assertEqual(cleaned.tobytes(), image.tobytes())

    def test_edge_checker_cleanup_cannot_cross_a_one_pixel_diagonal_outline(self) -> None:
        image = Image.new("RGBA", (25, 25), (225, 226, 224, 255))
        draw = ImageDraw.Draw(image)
        draw.polygon(((12, 2), (22, 12), (12, 22), (2, 12)), outline=(10, 10, 10, 255))

        cleaned = remove_edge_connected_checker_matte(image)

        self.assertEqual(cleaned.getpixel((0, 0)), (0, 0, 0, 0))
        self.assertEqual(cleaned.getpixel((12, 12)), (225, 226, 224, 255))

    def test_frame_source_override_replaces_one_pose_and_records_its_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_root = root / "source"
            runtime_root = root / "runtime"
            source_root.mkdir()

            atlas = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
            draw = ImageDraw.Draw(atlas)
            for index in range(8):
                x = (index % 4) * 32
                y = (index // 4) * 32
                draw.rectangle((x + 10, y + 5, x + 21, y + 27), fill=(80 + index, 70, 150, 255))
            atlas_path = source_root / "walk-atlas.png"
            atlas.save(atlas_path)
            atlas_hash_before_build = sha256(atlas_path)

            idle = Image.new("RGBA", (32, 64), (0, 0, 0, 0))
            idle_draw = ImageDraw.Draw(idle)
            idle_draw.rectangle((10, 5, 21, 27), fill=(100, 80, 150, 255))
            idle_draw.rectangle((10, 37, 21, 59), fill=(100, 80, 150, 255))
            idle.save(source_root / "idle-source.png")

            replacement = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
            ImageDraw.Draw(replacement).rectangle((10, 5, 21, 27), fill=(25, 230, 40, 255))
            replacement_path = source_root / "phase-3-reviewed.png"
            replacement.save(replacement_path)

            high_resolution = Image.new("RGBA", (128, 128), (0, 0, 0, 255))
            high_resolution_draw = ImageDraw.Draw(high_resolution)
            for y in range(0, 128, 8):
                for x in range(0, 128, 8):
                    checker = (250, 251, 250, 255) if (x // 8 + y // 8) % 2 else (205, 206, 207, 255)
                    high_resolution_draw.rectangle((x, y, x + 7, y + 7), fill=checker)
            high_resolution_draw.rectangle((40, 20, 80, 111), fill=(220, 45, 35, 255))
            high_resolution_draw.rectangle((92, 50, 110, 70), fill=(25, 210, 230, 255))
            high_resolution_path = source_root / "phase-5-high-resolution-reviewed.png"
            high_resolution.save(high_resolution_path)

            frame_sources: list[object | None] = [None] * 8
            frame_sources[2] = replacement_path.name
            frame_sources[4] = {
                "source": high_resolution_path.name,
                "resolution_normalization": "match_base_visible_height",
            }
            manifest = {
                "version": 1,
                "character": "test-tail-mouse",
                "source_root": str(source_root),
                "runtime_root": str(runtime_root),
                "framing": {
                    "frame_size": 32,
                    "target_height": 23,
                    "max_width": 28,
                    "center_x": 16,
                    "baseline": 29,
                    "remove_edge_connected_checker": True,
                },
                "idle_sets": [{
                    "source": "idle-source.png",
                    "source_columns": 1,
                    "rows": 2,
                    "fixed_grid": True,
                    "outputs": ["idle.png"],
                }],
                "walks": {
                    "walk.png": {
                        "source": "walk-atlas.png",
                        "source_columns": 4,
                        "rows": 2,
                        "fixed_grid": True,
                        "frame_sources": frame_sources,
                    }
                },
            }
            manifest_path = root / "build.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            report = build(manifest_path)

            self.assertEqual(sha256(atlas_path), atlas_hash_before_build)
            self.assertEqual(report["outputs"]["walk.png"]["source_frame_indices"], list(range(8)))
            with Image.open(runtime_root / "walk.png") as strip:
                rgba_strip = strip.convert("RGBA")
                phase_three = self._strip_frame(rgba_strip, 2, 32)
                phase_four = self._strip_frame(rgba_strip, 3, 32)
                phase_five = self._strip_frame(rgba_strip, 4, 32)
            self.assertAlmostEqual(self._color_center_x(phase_three, "green"), 16, delta=1)
            self.assertEqual(report["sources"][replacement_path.name], sha256(replacement_path))
            self.assertEqual(
                visible_bbox(phase_five)[3] - visible_bbox(phase_five)[1],
                visible_bbox(phase_four)[3] - visible_bbox(phase_four)[1],
            )
            phase_five_pixels = np.asarray(phase_five, dtype=np.uint8)
            red_mask = (
                (phase_five_pixels[:, :, 0] > 180)
                & (phase_five_pixels[:, :, 1] < 80)
            )
            self.assertTrue(np.any(red_mask))
            self.assertTrue(np.any(
                (phase_five_pixels[:, :, 0] < 80)
                & (phase_five_pixels[:, :, 1] > 170)
                & (phase_five_pixels[:, :, 2] > 190)
            ))
            red_y, red_x = np.where(red_mask)
            normalized_aspect = (red_x.max() - red_x.min() + 1) / (red_y.max() - red_y.min() + 1)
            self.assertAlmostEqual(normalized_aspect, 41 / 92, delta=0.06)

            overrides = {
                record["frame"]: record
                for record in report["outputs"]["walk.png"]["frame_source_overrides"]
            }
            self.assertEqual(overrides[3]["resolution_normalization"], {
                "mode": "legacy_none",
                "uniform_scale": 1.0,
            })
            self.assertEqual(overrides[5]["source"], high_resolution_path.name)
            self.assertEqual(
                overrides[5]["resolution_normalization"],
                {
                    "mode": "match_base_visible_height",
                    "source_visible_height": 92,
                    "target_visible_height": 23,
                    "uniform_scale": 0.25,
                },
            )
            self.assertEqual(
                report["outputs"]["walk.png"]["normalized_frames"][4]["source_resolution_scale"],
                0.25,
            )

    def test_frame_source_override_requires_one_slot_per_selected_pose(self) -> None:
        cells = [Image.new("RGBA", (8, 8), (0, 0, 0, 0)) for _ in range(8)]
        with self.assertRaisesRegex(ValueError, "8-item list"):
            apply_frame_source_overrides(cells, [None] * 7, Path("unused"))

    def test_source_frame_indices_rejects_invalid_or_duplicate_phases(self) -> None:
        cells = [Image.new("RGBA", (8, 8), (index, 0, 0, 255)) for index in range(8)]
        invalid = [
            None,
            tuple(range(8)),
            list(range(7)),
            list(range(9)),
            [0, 1, 2, 3, 4, 5, 6, 6],
            [-1, 1, 2, 3, 4, 5, 6, 7],
            [0, 1, 2, 3, 4, 5, 6, 8],
            [False, 1, 2, 3, 4, 5, 6, 7],
            [0, True, 2, 3, 4, 5, 6, 7],
            [0.0, 1, 2, 3, 4, 5, 6, 7],
            ["0", 1, 2, 3, 4, 5, 6, 7],
            [[0], 1, 2, 3, 4, 5, 6, 7],
        ]
        for indices in invalid:
            with self.subTest(indices=indices):
                with self.assertRaisesRegex(ValueError, "source_frame_indices.*permutation"):
                    reorder_walk_source_frames(cells, indices)

    def test_source_frame_indices_resequences_after_rows_and_before_overrides(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source_root = root / "source"
            source_root.mkdir()
            atlas = Image.new("RGBA", (128, 96), (0, 0, 0, 0))
            draw = ImageDraw.Draw(atlas)
            for index in range(12):
                x, y = (index % 4) * 32, (index // 4) * 32
                draw.rectangle((x + 10, y + 4, x + 21, y + 15 + index),
                               fill=(80 + index, 70, 150, 255))
            atlas_path = source_root / "walk-atlas.png"
            atlas.save(atlas_path)
            original_hash = sha256(atlas_path)
            idle = atlas.crop((0, 0, 32, 64))
            idle.save(source_root / "idle.png")
            replacement = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
            ImageDraw.Draw(replacement).rectangle((10, 5, 21, 24), fill=(25, 230, 40, 255))
            replacement.save(source_root / "override.png")
            indices = [0, 5, 6, 3, 4, 1, 2, 7]
            overrides = [None] * 8
            overrides[1] = {
                "source": "override.png",
                "resolution_normalization": "match_base_visible_height",
            }
            manifest = {
                "version": 1,
                "character": "phase-order-fixture",
                "source_root": str(source_root),
                "runtime_root": str(root / "runtime"),
                "framing": {
                    "frame_size": 32, "target_height": 23, "max_width": 28,
                    "center_x": 16, "baseline": 30,
                },
                "idle_sets": [{
                    "source": "idle.png", "source_columns": 1,
                    "rows": 2, "fixed_grid": True, "outputs": ["idle.png"],
                }],
                "walks": {"walk.png": {
                    "source": atlas_path.name, "source_columns": 4,
                    "rows": 3, "row_indices": [2, 0], "fixed_grid": True,
                    "source_frame_indices": indices, "frame_sources": overrides,
                }},
            }
            manifest_path = root / "build.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            report = build(manifest_path)

            self.assertEqual(sha256(atlas_path), original_hash)
            details = report["outputs"]["walk.png"]
            self.assertEqual(details["source_frame_indices"], indices)
            # Selected cells are atlas cells 8..11,0..3. The override for output
            # slot 2 must measure mapped atlas cell 1 (13px), not cell 9 (21px).
            self.assertEqual(
                details["frame_source_overrides"][0]["resolution_normalization"]["target_visible_height"],
                13,
            )
            expected_colors = [88, 25, 82, 91, 80, 89, 90, 83]
            with Image.open(root / "runtime" / "walk.png") as strip:
                for index, red in enumerate(expected_colors):
                    frame = self._strip_frame(strip.convert("RGBA"), index, 32)
                    pixels = np.asarray(frame)
                    colors = set(pixels[:, :, 0][pixels[:, :, 3] > 0].tolist())
                    self.assertEqual(colors, {red}, f"Wrong source cell in output slot {index + 1}")
            persisted = json.loads((root / "runtime" / "build-report.json").read_text())
            self.assertEqual(persisted["outputs"]["walk.png"]["source_frame_indices"], indices)

    def test_unit_resolution_scales_are_pixel_identical_to_legacy_normalization(self) -> None:
        frames = [self._tailed_frame("left"), self._tailed_frame("right")]
        legacy, _ = normalize_strip(
            frames, 128, 80, 110, 64, 112, horizontal_anchor="core"
        )
        explicit, _ = normalize_strip(
            frames,
            128,
            80,
            110,
            64,
            112,
            horizontal_anchor="core",
            source_resolution_scales=[1.0, 1.0],
        )
        self.assertEqual(explicit.tobytes(), legacy.tobytes())

    def test_frame_source_override_accepts_reviewed_visible_height_ratio(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source_root = Path(temporary)
            replacement_path = source_root / "reviewed-phase.png"
            replacement = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            ImageDraw.Draw(replacement).rectangle((12, 4, 51, 59), fill=(130, 80, 45, 255))
            replacement.save(replacement_path)
            base = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
            ImageDraw.Draw(base).rectangle((4, 2, 11, 13), fill=(130, 80, 45, 255))

            _, records = apply_frame_source_overrides(
                [base],
                [{
                    "source": replacement_path.name,
                    "resolution_normalization": {
                        "mode": "reviewed_visible_height",
                        "source_visible_height": 48,
                        "target_visible_height": 12,
                    },
                }],
                source_root,
            )

            self.assertEqual(records[0]["resolution_normalization"], {
                "mode": "reviewed_visible_height",
                "source_visible_height": 48.0,
                "target_visible_height": 12.0,
                "uniform_scale": 0.25,
            })


if __name__ == "__main__":
    unittest.main()
