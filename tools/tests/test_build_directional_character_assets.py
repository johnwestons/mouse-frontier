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
    keep_primary_component,
    normalize_strip,
    remove_edge_connected_checker_matte,
    sha256,
    visible_bbox,
)


class DirectionalCharacterAssetBuilderTests(unittest.TestCase):
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
