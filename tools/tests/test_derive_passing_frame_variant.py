from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from tools.derive_passing_frame_variant import (
    build_selector,
    derive_passing_frame_variant,
    main,
    region_mask,
)


class PassingFrameVariantTests(unittest.TestCase):
    @staticmethod
    def _frame() -> Image.Image:
        image = Image.new("RGBA", (24, 20), (255, 0, 255, 255))
        draw = ImageDraw.Draw(image)
        draw.rectangle((7, 2, 16, 11), fill=(62, 92, 54, 255))  # coat/core
        draw.rectangle((3, 5, 5, 7), fill=(230, 180, 35, 255))  # detached equipment
        draw.rectangle((7, 10, 10, 17), fill=(200, 160, 120, 255))  # near leg
        draw.rectangle((14, 10, 16, 17), fill=(160, 128, 96, 192))  # far leg
        draw.point((9, 14), fill=(100, 80, 60, 255))  # retained near texture
        draw.point((15, 14), fill=(80, 64, 48, 192))  # retained far texture
        return image

    @staticmethod
    def _leg_masks() -> tuple[np.ndarray, np.ndarray]:
        near = np.zeros((20, 24), dtype=bool)
        far = np.zeros((20, 24), dtype=bool)
        near[10:18, 7:11] = True
        far[10:18, 14:17] = True
        return near, far

    def test_depth_swap_preserves_alpha_silhouette_and_all_unselected_pixels(self) -> None:
        source = self._frame()
        source_rgba = np.asarray(source, dtype=np.uint8).copy()
        near, far = self._leg_masks()

        result, report = derive_passing_frame_variant(
            source, near, far, depth_ratio=0.8
        )
        output = np.asarray(result, dtype=np.uint8)

        self.assertTrue(np.array_equal(output[:, :, 3], source_rgba[:, :, 3]))
        self.assertTrue(np.array_equal(output[~(near | far)], source_rgba[~(near | far)]))
        self.assertEqual(tuple(output[11, 8]), (160, 128, 96, 255))
        self.assertEqual(tuple(output[11, 15]), (200, 160, 120, 192))
        self.assertEqual(tuple(output[14, 9]), (80, 64, 48, 255))
        self.assertEqual(tuple(output[14, 15]), (100, 80, 60, 192))
        self.assertEqual(tuple(output[6, 4]), (230, 180, 35, 255))
        self.assertTrue(report["alpha_preserved"])
        self.assertTrue(report["silhouette_preserved"])
        self.assertTrue(report["outside_selectors_preserved"])
        self.assertEqual(report["source_alpha_sha256"], report["output_alpha_sha256"])

        repeated, repeated_report = derive_passing_frame_variant(
            source, near, far, depth_ratio=0.8
        )
        self.assertEqual(repeated.tobytes(), result.tobytes())
        self.assertEqual(repeated_report["output_rgba_sha256"], report["output_rgba_sha256"])

    def test_default_magenta_protection_keeps_opaque_matte_inside_regions_exact(self) -> None:
        source = self._frame()
        near = region_mask(source.size, rectangles=[(6, 9, 12, 19)])
        far = region_mask(source.size, rectangles=[(13, 9, 18, 19)])

        result, _ = derive_passing_frame_variant(source, near, far, depth_ratio=0.8)

        self.assertEqual(result.getpixel((6, 9)), (255, 0, 255, 255))
        self.assertEqual(result.getpixel((17, 18)), (255, 0, 255, 255))
        self.assertEqual(result.getpixel((8, 11)), (160, 128, 96, 255))

    def test_selector_intersects_binary_mask_with_explicit_region(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mask_path = root / "mask.png"
            mask = Image.new("L", (12, 10), 0)
            ImageDraw.Draw(mask).rectangle((2, 2, 9, 7), fill=255)
            mask.save(mask_path)

            selected = build_selector(
                (12, 10),
                mask_path,
                rectangles=[(5, 0, 12, 5)],
            )

            expected = np.zeros((10, 12), dtype=bool)
            expected[2:5, 5:10] = True
            self.assertTrue(np.array_equal(selected, expected))

    def test_rejects_overlapping_or_wrong_size_masks(self) -> None:
        source = self._frame()
        near, far = self._leg_masks()
        far[10, 7] = True
        with self.assertRaisesRegex(ValueError, "overlap"):
            derive_passing_frame_variant(source, near, far)

        with self.assertRaisesRegex(ValueError, "shape"):
            derive_passing_frame_variant(
                source,
                np.zeros((3, 4), dtype=bool),
                np.zeros((3, 4), dtype=bool),
            )

    def test_polygon_regions_are_explicit_and_do_not_expand(self) -> None:
        selected = region_mask(
            (12, 10),
            polygons=[((2, 2), (8, 2), (5, 7))],
        )

        self.assertTrue(selected[3, 5])
        self.assertFalse(selected[1, 5])
        self.assertFalse(selected[8, 5])
        self.assertFalse(selected[3, 9])

    def test_cli_writes_lossless_output_and_auditable_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            input_path = root / "frame.png"
            near_path = root / "near.png"
            far_path = root / "far.png"
            output_path = root / "opposite.png"
            source = self._frame()
            source.save(input_path)
            near, far = self._leg_masks()
            Image.fromarray(np.where(near, 255, 0).astype(np.uint8), "L").save(near_path)
            Image.fromarray(np.where(far, 255, 0).astype(np.uint8), "L").save(far_path)

            status = main(
                [
                    str(input_path),
                    str(output_path),
                    "--near-mask",
                    str(near_path),
                    "--far-mask",
                    str(far_path),
                    "--depth-ratio",
                    "0.8",
                ]
            )

            self.assertEqual(status, 0)
            report_path = output_path.with_suffix(".audit.json")
            report = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertTrue(report["alpha_preserved"])
            self.assertTrue(report["outside_selectors_preserved"])
            self.assertEqual(report["near_to_far"]["bounds"], [7, 10, 11, 18])
            self.assertEqual(report["far_to_near"]["bounds"], [14, 10, 17, 18])
            self.assertEqual(len(report["input_file_sha256"]), 64)
            self.assertEqual(len(report["output_file_sha256"]), 64)
            with Image.open(output_path) as saved:
                self.assertEqual(saved.convert("RGBA").getchannel("A").tobytes(), source.getchannel("A").tobytes())


if __name__ == "__main__":
    unittest.main()
