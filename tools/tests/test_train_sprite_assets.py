from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[2]
ANIMATIONS = ROOT / "assets" / "sprites" / "train" / "animations"
TRACKS = ROOT / "assets" / "sprites" / "tracks"
STRONG_ALPHA = 192


class TrainSpriteAssetTests(unittest.TestCase):
    def assert_rgba_asset(
        self, path: Path, expected_size: tuple[int, int], expected_alpha_max: int = 255
    ) -> Image.Image:
        self.assertTrue(path.is_file(), f"missing train sprite: {path.relative_to(ROOT)}")
        with Image.open(path) as source:
            self.assertEqual("RGBA", source.mode, path.name)
            self.assertEqual(expected_size, source.size, path.name)
            image = source.copy()

        alpha = image.getchannel("A")
        self.assertEqual(
            (0, expected_alpha_max),
            alpha.getextrema(),
            f"{path.name} must contain transparency and opaque art",
        )
        self.assertIsNotNone(alpha.getbbox(), f"{path.name} contains no visible art")
        return image

    @staticmethod
    def strong_alpha_bounds(image: Image.Image) -> tuple[int, int, int, int] | None:
        alpha = image.getchannel("A")
        strong = alpha.point(lambda value: 255 if value >= STRONG_ALPHA else 0)
        return strong.getbbox()

    def assert_transparent_vertical_edges(self, image: Image.Image, label: str) -> None:
        alpha = image.getchannel("A")
        width, height = image.size
        self.assertIsNone(alpha.crop((0, 0, 1, height)).getbbox(), f"{label} has pixels on its left edge")
        self.assertIsNone(
            alpha.crop((width - 1, 0, width, height)).getbbox(),
            f"{label} has pixels on its right edge",
        )

    def assert_four_frame_atlas(
        self,
        path: Path,
        *,
        expected_top: int,
        expected_baseline: int,
        expected_left: int,
        expected_right: int,
        horizontal_tolerance: int,
    ) -> None:
        image = self.assert_rgba_asset(path, (2172, 724))
        self.assertEqual(0, image.width % 4, f"{path.name} must divide into four equal cells")
        cell_width = image.width // 4
        self.assertEqual((543, 724), (cell_width, image.height), path.name)
        self.assert_transparent_vertical_edges(image, path.name)

        bounds: list[tuple[int, int, int, int]] = []
        identities: set[str] = set()
        for frame_index in range(4):
            left = frame_index * cell_width
            frame = image.crop((left, 0, left + cell_width, image.height))
            self.assert_transparent_vertical_edges(frame, f"{path.name} frame {frame_index + 1}")
            frame_bounds = self.strong_alpha_bounds(frame)
            self.assertIsNotNone(frame_bounds, f"{path.name} frame {frame_index + 1} has no strong-alpha art")
            assert frame_bounds is not None
            bounds.append(frame_bounds)
            identities.add(hashlib.sha256(frame.tobytes()).hexdigest())

            frame_left, frame_top, frame_right, frame_bottom = frame_bounds
            self.assertLessEqual(abs(frame_top - expected_top), 1, f"{path.name} frame {frame_index + 1} top drift")
            self.assertLessEqual(
                abs(frame_bottom - expected_baseline),
                1,
                f"{path.name} frame {frame_index + 1} contact-baseline drift",
            )
            self.assertLessEqual(
                abs(frame_left - expected_left),
                horizontal_tolerance,
                f"{path.name} frame {frame_index + 1} left-bound drift",
            )
            self.assertLessEqual(
                abs(frame_right - expected_right),
                horizontal_tolerance,
                f"{path.name} frame {frame_index + 1} right-bound drift",
            )

        self.assertEqual(4, len(identities), f"{path.name} must contain four distinct animation frames")
        self.assertLessEqual(max(bound[0] for bound in bounds) - min(bound[0] for bound in bounds), horizontal_tolerance)
        self.assertLessEqual(max(bound[2] for bound in bounds) - min(bound[2] for bound in bounds), horizontal_tolerance)
        self.assertLessEqual(max(bound[1] for bound in bounds) - min(bound[1] for bound in bounds), 2)
        self.assertLessEqual(max(bound[3] for bound in bounds) - min(bound[3] for bound in bounds), 2)

    def test_locomotive_component_canvases_are_stable_rgba(self) -> None:
        body = self.assert_rgba_asset(ANIMATIONS / "locomotive-red-body-v2.png", (1944, 809))
        gear = self.assert_rgba_asset(
            ANIMATIONS / "locomotive-running-gear-components-v1.png", (1536, 1024), 254
        )

        self.assertEqual((61, 103, 1864, 731), self.strong_alpha_bounds(body))
        self.assertEqual((151, 63, 1481, 946), self.strong_alpha_bounds(gear))

    def test_train_car_bogie_atlas_contract(self) -> None:
        self.assert_four_frame_atlas(
            ANIMATIONS / "train-car-bogie-run-4-v1.png",
            expected_top=265,
            expected_baseline=448,
            expected_left=39,
            expected_right=504,
            horizontal_tolerance=2,
        )

    def test_railway_ballast_pocket_mask_contract(self) -> None:
        mask = self.assert_rgba_asset(
            TRACKS / "railway-ballast-pocket-mask-v1.png", (2172, 724)
        )
        self.assertEqual((8, 355, 2149, 464), self.strong_alpha_bounds(mask))
        # The mask is deliberately sparse: it may occupy rock pockets but can
        # never become another continuous foreground ballast band.
        strong = mask.getchannel("A").point(lambda value: 255 if value >= STRONG_ALPHA else 0)
        occupied_columns = [strong.crop((x, 0, x + 1, strong.height)).getbbox() is not None for x in range(strong.width)]
        self.assertGreater(occupied_columns.count(False), 500)

    def test_railway_ballast_frames_are_distinct_but_pixel_anchored(self) -> None:
        atlas = self.assert_rgba_asset(
            TRACKS / "railway-ballast-pocket-run-4-v1.png", (2172, 2896)
        )
        frame_height = atlas.height // 4
        frames = [
            atlas.crop((0, index * frame_height, atlas.width, (index + 1) * frame_height))
            for index in range(4)
        ]
        alpha_payloads = [frame.getchannel("A").tobytes() for frame in frames]
        self.assertTrue(
            all(payload == alpha_payloads[0] for payload in alpha_payloads[1:]),
            "ballast frames must share one immutable anchor/silhouette mask",
        )
        self.assertEqual((8, 355, 2149, 464), self.strong_alpha_bounds(frames[0]))
        identities = {hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames}
        self.assertEqual(4, len(identities), "ballast atlas needs four real sprite poses")

        base = Image.open(TRACKS / "railway-track-v2.png").convert("RGBA")
        anchored_pixels = frames[0].getchannel("A").point(lambda value: 255 if value else 0)
        base_rgb = base.convert("RGB")
        frame_rgb = frames[0].convert("RGB")
        rgb_difference = ImageChops.difference(base_rgb, frame_rgb)
        anchored_difference = Image.composite(
            rgb_difference, Image.new("RGB", base.size), anchored_pixels
        )
        self.assertIsNone(
            anchored_difference.getbbox(),
            "the rest pose must use exact source-track colors inside every pocket",
        )

        visible_count = sum(1 for value in alpha_payloads[0] if value)
        rest_payload = frames[0].tobytes()
        for index, frame in enumerate(frames[1:], start=2):
            frame_payload = frame.tobytes()
            changed = sum(
                1
                for pixel in range(len(alpha_payloads[0]))
                if alpha_payloads[0][pixel]
                and rest_payload[pixel * 4 : pixel * 4 + 3]
                != frame_payload[pixel * 4 : pixel * 4 + 3]
            )
            self.assertGreater(changed, 50, f"frame {index} has no visible internal variation")
            self.assertLess(changed / visible_count, 0.18, f"frame {index} changes too much")

    def test_flat_track_and_runtime_anchor_contract(self) -> None:
        track = self.assert_rgba_asset(TRACKS / "railway-track-v2.png", (2172, 724))
        self.assertEqual((0, 230, 2172, 643), track.getchannel("A").getbbox())
        self.assertEqual((3, 355, 2169, 475), self.strong_alpha_bounds(track))

        train_source = (ROOT / "game" / "train.lua").read_text(encoding="utf-8")
        assets_source = (ROOT / "game" / "assets.lua").read_text(encoding="utf-8")
        for declaration in (
            "trackScale=96/181",
            "trackEdgeCrop=4",
            "engineBodyVisibleLeft=61",
            "engineBodyCouplerX=1864",
            "engineBodyContactY=730",
            "engineDriverSourceCentersX={725,950,1175}",
            "engineDriverSourceY=622",
            "engineDriverSourceRadius=108",
            "engineNoseBaseX=-99",
            "enginePilotSourceCentersX={288,534}",
            "engineCouplingRodThicknessScale=.55",
            "engineConnectingRodThicknessScale=.42",
            "carBogieStrongBottom=448",
            "carBogieScale=32/99",
        ):
            self.assertIn(declaration, train_source)
        self.assertIn("if (pixel.a < 0.125) discard;", assets_source)
        self.assertNotIn("jitterPixels", assets_source)
        self.assertIn("loadVerticalAtlas", assets_source)
        self.assertIn("railway-ballast-pocket-run-4-v1.png", assets_source)


if __name__ == "__main__":
    unittest.main()
