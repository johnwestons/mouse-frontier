from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.build_mobile_package import CARAVAN_PACKED_REGIONS, image_bounds, optimize_image, runtime_asset  # noqa: E402


class MobilePackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = json.loads((ROOT / "mobile" / "config.json").read_text(encoding="utf-8"))

    def test_directional_character_animation_sheets_are_runtime_assets(self) -> None:
        character_root = ROOT / "assets" / "sprites" / "character-animations" / "engineer-frog"
        for action in (
            "idle_north", "idle_northeast", "idle_northwest", "idle_south",
            "idle_southeast", "idle_southwest", "idle_west", "walk_north",
            "walk_northeast", "walk_northwest", "walk_south", "walk_southeast",
            "walk_southwest", "walk_west",
        ):
            with self.subTest(action=action):
                self.assertTrue(runtime_asset(character_root / f"{action}.png"))

    def test_future_run_sheets_pass_runtime_asset_filter(self) -> None:
        # Run art remains privately staged; classify synthetic present files
        # without installing test sprites into the game's asset directory.
        character_root = ROOT / "assets/sprites/character-animations/trail-fox"
        with patch.object(Path, "is_file", return_value=True):
            for suffix in ("", "_north", "_northeast", "_east", "_southeast", "_south", "_southwest", "_west", "_northwest"):
                expected = suffix != "_east"  # Canonical east action is run.png.
                self.assertEqual(expected, runtime_asset(character_root / f"run{suffix}.png"))

    def test_typewriter_fonts_and_license_are_runtime_assets(self) -> None:
        font_root = ROOT / "assets" / "fonts"
        for filename in ("CourierPrime-Regular.ttf", "CourierPrime-Bold.ttf"):
            with self.subTest(font=filename):
                path = font_root / filename
                self.assertTrue(runtime_asset(path), "mobile builds must keep the shared game font")
                self.assertEqual(b"\x00\x01\x00\x00", path.read_bytes()[:4], "font must be valid TrueType data")
        license_path = font_root / "OFL.txt"
        self.assertTrue(runtime_asset(license_path), "font license must ship alongside the font binaries")
        self.assertIn("SIL OPEN FONT LICENSE Version 1.1", license_path.read_text(encoding="utf-8"))

    def test_last_stand_mobile_package_excludes_concepts_and_candidates(self) -> None:
        for relative in (
            "assets/concepts/last-stand/last-stand-backyard-concept.png",
            "assets/sprites/quests/last-stand/otter-scout-approach-walk-alpha-candidate-v4.png",
            "assets/sprites/quests/last-stand/ASSET_INTEGRATION_SPEC.md",
        ):
            with self.subTest(relative=relative):
                self.assertFalse(runtime_asset(ROOT / relative))
        self.assertTrue(runtime_asset(ROOT / "assets/sprites/quests/last-stand/runtime/otter-scout-approach-walk.png"))

    def test_last_stand_fixed_atlases_retain_all_eight_authored_cells(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("otter-scout-approach-walk", "distant-dust-loop"):
                relative = f"assets/sprites/quests/last-stand/runtime/{name}.png"
                source, destination = ROOT / relative, directory / f"{name}.png"
                with patch("tools.build_mobile_package.CACHE_ROOT", directory / "cache"):
                    optimize_image(source, destination, relative, self.config)
                with Image.open(destination) as image:
                    self.assertEqual((8 * 320, 512), image.size)
                with self.assertRaisesRegex(ValueError, "dimensions changed"):
                    image_bounds(relative, self.config, (2048, 410))

    def test_character_animation_mobile_cells_keep_one_uniform_size(self) -> None:
        frame_size = self.config["characterAnimationFrameSize"]
        idle_bounds = image_bounds(
            "assets/sprites/character-animations/engineer-frog/idle.png",
            self.config,
            (1024, 512),
        )
        walk_bounds = image_bounds(
            "assets/sprites/character-animations/engineer-frog/walk_north.png",
            self.config,
            (4096, 512),
        )
        self.assertEqual((frame_size * 2, frame_size), idle_bounds)
        self.assertEqual((frame_size * 8, frame_size), walk_bounds)
        run_bounds = image_bounds(
            "assets/sprites/character-animations/trail-fox/run_northwest.png",
            self.config, (4096, 512))
        self.assertEqual((frame_size * 8, frame_size), run_bounds)

    def test_caravan_animation_mobile_bounds_preserve_both_grids(self) -> None:
        root = "assets/sprites/caravans/rookery/animations/"
        self.assertEqual((768, 512), image_bounds(root + "merchant-stall-breeze-4-v1.png", self.config, (1536, 1024)))
        self.assertEqual((768, 256), image_bounds(root + "campfire-idle-4-v1.png", self.config, (2172, 724)))
        self.assertEqual((384, 256), image_bounds(root + "merchant-stall-breeze-4-v1.png", self.config, (384, 256)))
        with self.assertRaisesRegex(ValueError, "2x2 grid"):
            image_bounds(root + "merchant-stall-breeze-4-v1.png", self.config, (1535, 1024))
        with self.assertRaisesRegex(ValueError, "aspect ratio"):
            image_bounds(root + "merchant-stall-breeze-4-v1.png", self.config, (1540, 1028))

    def test_caravan_optimizer_never_samples_neighbouring_frames(self) -> None:
        relative = "assets/sprites/caravans/rookery/animations/campfire-idle-4-v1.png"
        colors = ((255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (0, 0, 0, 0))
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source, destination = directory / "source.png", directory / "mobile.png"
            with Image.new("RGBA", (1536, 512)) as image:
                for index, color in enumerate(colors):
                    image.paste(color, (index * 384, 0, (index + 1) * 384, 512))
                image.save(source)
            with patch("tools.build_mobile_package.CACHE_ROOT", directory / "cache"):
                optimize_image(source, destination, relative, self.config)
            with Image.open(destination) as packed:
                image = packed.convert("RGBA")
            self.assertEqual((768, 256), image.size)
            for index, color in enumerate(colors):
                with image.crop((index * 192, 0, (index + 1) * 192, 256)) as cell:
                    self.assertEqual([(192 * 256, color)], cell.getcolors(), "frame edge was blended with its neighbour")
            image.close()

    def test_packed_cloth_regions_preserve_extended_canopy_without_bleeding(self) -> None:
        relative = "assets/sprites/caravans/rookery/animations/merchant-stall-breeze-4-v1.png"
        regions = ((0, 0, 768, 344), (768, 0, 768, 344), (0, 512, 816, 344), (816, 512, 720, 344),
                   (0, 344, 768, 168), (768, 344, 768, 168), (0, 856, 768, 168), (768, 856, 768, 168))
        colors = ((255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (255, 255, 0, 255),
                  (0, 255, 255, 255), (255, 0, 255, 255), (255, 255, 255, 255), (0, 0, 0, 0))
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source, destination = directory / "source.png", directory / "mobile.png"
            with Image.new("RGBA", (1536, 1024)) as image:
                for (x, y, width, height), color in zip(regions, colors):
                    image.paste(color, (x, y, x + width, y + height))
                self.assertEqual(colors[2], image.getpixel((790, 815)))
                self.assertEqual(colors[3], image.getpixel((830, 815)))
                image.save(source)
            with patch("tools.build_mobile_package.CACHE_ROOT", directory / "cache"):
                optimize_image(source, destination, relative, self.config)
            with Image.open(destination) as packed:
                image = packed.convert("RGBA")
            self.assertEqual((768, 512), image.size)
            self.assertEqual(colors[2], image.getpixel((395, 407)), "extended pose-3 feather was reassigned")
            self.assertEqual(colors[3], image.getpixel((415, 407)), "pose-4 artwork was mixed with pose 3")
            for (x, y, width, height), color in zip(regions, colors):
                with image.crop((x // 2, y // 2, (x + width) // 2, (y + height) // 2)) as region:
                    self.assertEqual([(width * height // 4, color)], region.getcolors(), "packed region edge sampled a neighbour")
            image.close()

    def test_packed_cloth_regions_match_runtime_manifest(self) -> None:
        manifest = (ROOT / "game" / "crow_caravan_art.lua").read_text(encoding="utf-8")
        source = re.search(r"sourceWidth\s*=\s*(\d+)\s*,\s*sourceHeight\s*=\s*(\d+)", manifest)
        self.assertIsNotNone(source, "runtime cloth manifest must declare its authored canvas")
        parts = re.findall(
            r"(canopy|drape)\s*=\s*\{\s*x\s*=\s*(\d+)\s*,\s*y\s*=\s*(\d+)\s*,\s*w\s*=\s*(\d+)\s*,\s*h\s*=\s*(\d+)",
            manifest,
        )
        self.assertEqual(8, len(parts), "runtime cloth manifest must contain four canopies and four drapes")
        regions = tuple(tuple(map(int, part[1:])) for name in ("canopy", "drape") for part in parts if part[0] == name)
        expected = CARAVAN_PACKED_REGIONS["assets/sprites/caravans/rookery/animations/merchant-stall-breeze-4-v1.png"]
        self.assertEqual(expected, (tuple(map(int, source.groups())), regions))

    def test_intro_train_anchors_follow_resized_mobile_scenery(self) -> None:
        intro = (ROOT / "game" / "intro_cinematic.lua").read_text(encoding="utf-8")
        self.assertIn("local backgroundRailRatio = 750/1086", intro)
        self.assertIn("backgroundHeight*backgroundRailRatio-backgroundHeight/2", intro)
        self.assertIn("cars:getHeight()*consistBaselineRatio", intro)
        self.assertNotIn("750-background:getHeight()/2", intro)


if __name__ == "__main__":
    unittest.main()
