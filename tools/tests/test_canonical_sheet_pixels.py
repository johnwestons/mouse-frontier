"""Prove reference provenance and installed cleanup failures with isolated art."""
from __future__ import annotations

from contextlib import redirect_stdout
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

from tools import update_canonical_sheet_pixels as generator
from tools.build_directional_character_assets import remove_edge_connected_magenta_fringe_pixels
from tools.tests import test_character_animation_behavior as renderer_tests


class CanonicalSheetPixelTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.character = "fixture"
        self.manifest_path = self.root / "character-motion/canonical_sheet_pixels.json"
        self.manifest_path.parent.mkdir(parents=True)
        tool_path = self.root / generator.NORMALIZATION_TOOL
        tool_path.parent.mkdir(parents=True)
        tool_path.write_bytes((generator.ROOT / generator.NORMALIZATION_TOOL).read_bytes())
        self.tool_path = tool_path
        review_path = self.root / generator.REVIEW_EVIDENCE
        review_path.parent.mkdir(parents=True)
        review_path.write_text("Reviewed isolated cleanup fixture.\n", encoding="utf-8")
        self.review_path = review_path
        self.reference_paths = []
        self.original_files = {}
        self.spec = {
            "character": self.character,
            "gait": {"pixels_per_frame": 3},
            "run_gait": {"pixels_per_frame": 6},
            "directions": {},
            "animations": {},
        }
        sheets = {}
        for direction in sorted(generator.DIRECTIONS):
            mapping = {"mirror_x": False}
            for mode, field in zip(("walk", "idle", "run"), generator.ACTION_FIELDS):
                action = mode + "_" + direction
                relative = f"output/character-motion/{self.character}/normalized/{action}.png"
                path = self.root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                image = self.source_image()
                image.save(path)
                self.reference_paths.append(path)
                self.original_files[path] = path.read_bytes()
                mapping[field] = action
                self.spec["animations"][action] = {
                    "path": relative, "frame_width": 9, "frame_height": 9, "frame_count": 1,
                }
                sheets[action] = {
                    "source_path": relative, "source_filename": path.name,
                    "width": 9, "height": 9,
                    "rgba_sha256": hashlib.sha256(image.tobytes()).hexdigest(),
                }
            self.spec["directions"][direction] = mapping
        self.previous = {"version": 1, "pixel_mode": "RGBA", "hash_algorithm": "sha256",
                         "characters": {self.character: sheets}}
        self.build = {"character": self.character,
                      "framing": {"remove_edge_connected_magenta_fringe": True}}
        self.spec_path = self.root / f"character-motion/{self.character}.json"
        self.build_path = self.root / f"character-motion/{self.character}-build.json"
        self.write_json(self.spec_path, self.spec)
        self.write_json(self.build_path, self.build)
        self.write_json(self.manifest_path, self.previous)
        self.enterContext(patch.object(generator, "ROOT", self.root))
        self.enterContext(patch.object(generator, "MANIFEST", self.manifest_path))
        self.enterContext(patch.object(generator, "calibrated_characters", return_value=[self.character]))
        self.enterContext(patch.object(renderer_tests, "ROOT", self.root))

    @staticmethod
    def write_json(path, value):
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

    @staticmethod
    def source_image():
        image = Image.new("RGBA", (9, 9), (0, 0, 0, 0))
        ImageDraw.Draw(image).rectangle((2, 2, 6, 6), fill=(8, 8, 8, 255))
        image.putpixel((1, 1), (205, 18, 104, 255))  # Expanded hard-magenta rule, background connected.
        image.putpixel((4, 4), (112, 4, 116, 255))   # Enclosed dark-magenta art must survive.
        return image

    def call_main(self, *args):
        with redirect_stdout(io.StringIO()):
            return generator.main(list(args))

    def install_fixture(self, candidate):
        directory = self.root / f"assets/sprites/character-animations/{self.character}"
        directory.mkdir(parents=True)
        for record in candidate["characters"][self.character].values():
            with Image.open(self.root / record["source_path"]) as image:
                remove_edge_connected_magenta_fringe_pixels(image).save(directory / record["source_filename"])
        return directory

    def check_installed_fixture(self):
        case = renderer_tests.CharacterAnimationBehaviorTests("test_installed_calibrated_profiles_match_canonical_motion_specs")
        profile = {"pixelsPerFrame": 3, "runPixelsPerFrame": 6}
        globals_table = SimpleNamespace(Motion=SimpleNamespace(profiles={self.character + ".png": profile}))
        case.lua = SimpleNamespace(globals=lambda: globals_table)
        case.test_installed_calibrated_profiles_match_canonical_motion_specs()

    def test_derivation_preserves_original_hashes_pixels_and_files(self):
        candidate = generator.build_manifest()
        self.assertEqual(candidate["version"], 2)
        self.assertEqual(candidate["normalization"], generator.normalization_record())
        for action, record in candidate["characters"][self.character].items():
            original = self.previous["characters"][self.character][action]
            self.assertEqual({key: record[key] for key in generator.SOURCE_FIELDS}, original)
            self.assertEqual(record["removed_pixels"], 1)
            self.assertNotEqual(record["installed_rgba_sha256"], record["rgba_sha256"])
            with Image.open(self.root / record["source_path"]) as image:
                cleaned = remove_edge_connected_magenta_fringe_pixels(image)
                self.assertEqual(cleaned.getpixel((1, 1)), (0, 0, 0, 0))
                self.assertEqual(cleaned.getpixel((4, 4)), image.getpixel((4, 4)))
                self.assertEqual(record["installed_rgba_sha256"], hashlib.sha256(cleaned.tobytes()).hexdigest())
        for path, before in self.original_files.items():
            self.assertEqual(path.read_bytes(), before)

    def test_generator_never_reads_installed_images(self):
        directory = self.root / f"assets/sprites/character-animations/{self.character}"
        directory.mkdir(parents=True)
        (directory / "idle_east.png").write_bytes(b"invalid image: installed art cannot be an input")
        real_open = Image.open
        paths = []
        def track_open(path, *args, **kwargs):
            paths.append(Path(path))
            return real_open(path, *args, **kwargs)
        with patch.object(generator.Image, "open", side_effect=track_open):
            candidate = generator.build_manifest()
        self.assertEqual(len(candidate["characters"][self.character]), 24)
        self.assertEqual(set(paths), set(self.reference_paths))

    def test_default_is_read_only_and_explicit_write_retains_sources(self):
        before = self.manifest_path.read_bytes()
        self.assertEqual(self.call_main(), 1)
        self.assertEqual(self.manifest_path.read_bytes(), before)
        self.assertEqual(self.call_main("--write-reviewed-references"), 0)
        candidate = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(candidate["version"], 2)
        self.assertEqual(self.call_main(), 0)
        for path, original in self.original_files.items():
            self.assertEqual(path.read_bytes(), original)

    def test_source_pixel_changes_cannot_be_blessed_by_write_flag(self):
        path = self.reference_paths[0]
        with Image.open(path) as image:
            altered = image.convert("RGBA")
        altered.putpixel((3, 3), (200, 120, 30, 255))
        altered.save(path)
        before = self.manifest_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "original fingerprints are immutable"):
            generator.build_manifest()
        self.assertEqual(self.call_main("--write-reviewed-references"), 2)
        self.assertEqual(self.manifest_path.read_bytes(), before)

    def test_source_path_and_dimensions_remain_bound(self):
        action = sorted(self.spec["animations"])[0]
        for field, value in (("path", "output/copied-original.png"), ("frame_width", 8)):
            with self.subTest(field=field):
                altered = copy.deepcopy(self.spec)
                altered["animations"][action][field] = value
                if field == "path":
                    duplicate = self.root / value
                    duplicate.parent.mkdir(parents=True, exist_ok=True)
                    duplicate.write_bytes((self.root / self.spec["animations"][action]["path"]).read_bytes())
                self.write_json(self.spec_path, altered)
                with self.assertRaises(ValueError):
                    generator.build_manifest()
        self.write_json(self.spec_path, self.spec)

    def test_policy_drift_is_rejected_even_with_write_flag(self):
        self.tool_path.write_bytes(self.tool_path.read_bytes() + b"\n# unreviewed policy modification\n")
        before = self.manifest_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Cleanup policy changed"):
            generator.build_manifest()
        self.assertEqual(self.call_main("--write-reviewed-references"), 2)
        self.assertEqual(self.manifest_path.read_bytes(), before)

    def test_policy_identity_is_stable_for_crlf_and_lf_checkouts(self):
        expected = generator.normalization_record()
        source = self.tool_path.read_bytes().replace(b"\r\n", b"\n")
        self.tool_path.write_bytes(source.replace(b"\n", b"\r\n"))
        self.assertEqual(generator.normalization_record(), expected)
        self.tool_path.write_bytes(source)
        self.assertEqual(generator.normalization_record(), expected)

    def test_existing_normalization_provenance_cannot_be_replaced(self):
        candidate = generator.build_manifest()
        for field in ("policy_sha256", "id", "source_commit", "review_evidence"):
            with self.subTest(field=field):
                altered = copy.deepcopy(candidate)
                altered["normalization"][field] = "changed"
                with self.assertRaisesRegex(ValueError, "cleanup policy/provenance changed"):
                    generator.build_manifest(altered)

    def test_missing_baseline_and_review_evidence_fail_without_writing(self):
        before = self.manifest_path.read_bytes()
        self.review_path.unlink()
        self.assertEqual(self.call_main("--write-reviewed-references"), 2)
        self.assertEqual(self.manifest_path.read_bytes(), before)
        self.manifest_path.unlink()
        self.assertEqual(self.call_main("--write-reviewed-references"), 2)
        self.assertFalse(self.manifest_path.exists())

    def test_build_requires_global_and_per_action_cleanup_opt_in(self):
        for build in ({"character": self.character, "framing": {}},
                      {"character": self.character, "framing": {"remove_edge_connected_magenta_fringe": False}},
                      {**self.build, "walks": {"walk.png": {"remove_edge_connected_magenta_fringe": False}}},
                      {**self.build, "runs": {"run.png": {"remove_edge_connected_magenta_fringe": False}}},
                      {**self.build, "idle_sets": [{"remove_edge_connected_magenta_fringe": False}]}):
            with self.subTest(build=build):
                self.write_json(self.build_path, build)
                with self.assertRaisesRegex(ValueError, "magenta cleanup"):
                    generator.build_manifest()

    def test_source_paths_cannot_escape_or_point_at_installed_assets(self):
        for path in ("../outside.png", "C:/outside.png", "/outside.png", "output\\reference.png",
                     "assets/sprites/character-animations/fixture/idle.png"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                generator.canonical_source_path(path)

    def test_mode_and_direction_swaps_fail_both_contracts_without_image_reads(self):
        candidate = generator.build_manifest()
        self.write_json(self.manifest_path, candidate)
        self.install_fixture(candidate)
        for path in self.reference_paths:
            path.unlink()
        swaps = (("east", "walk_animation", "east", "idle_animation"),
                 ("north", "walk_animation", "south", "walk_animation"),
                 ("east", "run_animation", "west", "run_animation"))
        for first_direction, first_field, second_direction, second_field in swaps:
            with self.subTest(swap=(first_direction, first_field, second_direction, second_field)):
                altered = copy.deepcopy(self.spec)
                directions = altered["directions"]
                directions[first_direction][first_field], directions[second_direction][second_field] = (
                    directions[second_direction][second_field], directions[first_direction][first_field])
                self.write_json(self.spec_path, altered)
                with patch.object(generator.Image, "open") as image_open:
                    with self.assertRaisesRegex(ValueError, "must map to"):
                        generator.build_manifest()
                    with self.assertRaisesRegex(AssertionError, "must retain its mode and direction"):
                        self.check_installed_fixture()
                    image_open.assert_not_called()

    def test_installed_contract_rejects_pixel_mutations_without_reference_pngs(self):
        candidate = generator.build_manifest()
        self.write_json(self.manifest_path, candidate)
        directory = self.install_fixture(candidate)
        for path in self.reference_paths:
            path.unlink()
        self.check_installed_fixture()  # Clean checkout needs no ignored canonical PNGs.
        path = directory / "idle_east.png"
        with Image.open(path) as image:
            original = image.convert("RGBA")
        for point, pixel in (((1, 1), (205, 18, 104, 255)),   # Restore removed opaque matte.
                             ((3, 3), (8, 8, 8, 0)),       # Remove legitimate subject art.
                             ((4, 4), (113, 4, 116, 255))): # Alter surviving subject RGB.
            with self.subTest(point=point):
                altered = original.copy()
                altered.putpixel(point, pixel)
                altered.save(path)
                with self.assertRaisesRegex(AssertionError, "canonical sheet pixel mismatches"):
                    self.check_installed_fixture()
        original.save(path)
        self.check_installed_fixture()


if __name__ == "__main__":
    unittest.main()
