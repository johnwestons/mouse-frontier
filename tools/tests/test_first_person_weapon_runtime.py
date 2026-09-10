from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
FIRST_PERSON_ROOT = ROOT / "assets" / "sprites" / "weapons" / "first-person"
EXPECTED_PRODUCTION_PNGS = 103
REJECTED_BOW_STATES = {
    "hunting-bow-low-ready.png",
    "hunting-bow-arrow-nocked.png",
    "hunting-bow-partial-draw.png",
    "hunting-bow-release-string-return.png",
}
sys.path.insert(0, str(ROOT))

from tools.build_mobile_package import runtime_asset  # noqa: E402


class FirstPersonWeaponRuntimeTests(unittest.TestCase):
    @staticmethod
    def _manifest_entries(source: str) -> dict[str, str]:
        markers = list(re.finditer(r'^    \["([^"]+)"\]=(pair|special)\(', source, re.MULTILINE))
        entries: dict[str, str] = {}
        for index, marker in enumerate(markers):
            end = markers[index + 1].start() if index + 1 < len(markers) else source.index("\n}\n", marker.start())
            entries[marker.group(1)] = source[marker.start():end]
        return entries

    @staticmethod
    def _manifest_entry(source: str, weapon: str) -> str:
        return FirstPersonWeaponRuntimeTests._manifest_entries(source)[weapon]

    def _manifest_production_files(self, source: str) -> set[str]:
        files: set[str] = set()
        pair_rows = re.findall(r'^    \["([^"]+)"\]=pair\("([^"]+)"', source, re.MULTILINE)
        for weapon, asset_id in pair_rows:
            self.assertEqual(weapon, asset_id)
            files.update({f"{asset_id}-hip.png", f"{asset_id}-sights.png"})
        files.update(re.findall(r'^\s+[A-Za-z]\w*="([^"]+\.png)",?$', source, re.MULTILINE))
        return files

    def test_manifest_covers_every_player_ranged_weapon(self) -> None:
        catalog = (ROOT / "game" / "catalog.lua").read_text(encoding="utf-8")
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        ranged = set(re.findall(r'\["([^"]+)"\]=\{kind="ranged"', catalog))
        progression_payload = catalog.split("Catalog.weaponProgression = {", 1)[1].split("}", 1)[0]
        progression = set(re.findall(r'"([^"]+)"', progression_payload))
        player_ranged = ranged & progression
        manifested = set(re.findall(r'\["([^"]+)"\]=(?:pair|special)\(', manifest))
        self.assertEqual(46, len(player_ranged))
        self.assertEqual(player_ranged, manifested)
        self.assertNotIn("mob-spit", manifested)

    def test_manifest_uses_unversioned_production_paths_and_safe_anchors(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        self.assertIn('id.."-hip.png"', manifest)
        self.assertIn('id.."-sights.png"', manifest)
        self.assertNotRegex(manifest, r'views=.*review-batch')
        self.assertIn("DEFAULT_ADS_ANCHOR", manifest)
        self.assertIn("anchor.calibrated==true", manifest)
        self.assertIn("function Manifest.validate()", manifest)
        for state_file in (
            "hunting-bow-full-draw-aim.png",
            "critter-crossbow-bolt-loaded-aim.png",
            "trail-slingshot-release-band-return.png",
            "wrist-braced-slingshot-full-draw-aim.png",
            "metal-scrap-slingshot-loaded.png",
            "long-hunting-slingshot-low-ready.png",
            "scrap-boomerang-return-approach.png",
        ):
            self.assertIn(state_file, manifest)
        for rejected_bow_state in (
            "hunting-bow-low-ready.png",
            "hunting-bow-arrow-nocked.png",
            "hunting-bow-partial-draw.png",
            "hunting-bow-release-string-return.png",
        ):
            self.assertNotIn(rejected_bow_state, manifest)

    def test_promoted_assets_exactly_match_manifest_and_are_transparent_rgba(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        expected = self._manifest_production_files(manifest)
        production = sorted(FIRST_PERSON_ROOT.glob("*.png"))
        actual = {path.name for path in production}

        self.assertEqual(EXPECTED_PRODUCTION_PNGS, len(expected))
        self.assertEqual(EXPECTED_PRODUCTION_PNGS, len(production))
        self.assertEqual(expected, actual)
        self.assertTrue(REJECTED_BOW_STATES.isdisjoint(actual))

        version_pattern = re.compile(r"(?:^|[-_])v\d+(?:[-_.]|$)", re.IGNORECASE)
        for path in production:
            with self.subTest(asset=path.name):
                self.assertTrue(path.is_file())
                self.assertNotRegex(path.name, version_pattern)
                with Image.open(path) as image:
                    self.assertEqual("RGBA", image.mode)
                    alpha_min, alpha_max = image.getchannel("A").getextrema()
                    self.assertEqual(0, alpha_min)
                    self.assertGreaterEqual(alpha_max, 254)

    def test_anchor_calibration_counts_are_explicit(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        entries = self._manifest_entries(manifest)
        calibrated = {name for name, entry in entries.items() if "calibrated=true" in entry}
        provisional = {name for name, entry in entries.items() if "calibrated=false" in entry}
        no_anchor = set(entries) - calibrated - provisional

        self.assertEqual(46, len(entries))
        self.assertEqual(45, len(calibrated))
        self.assertEqual(set(), provisional)
        self.assertEqual({"scrap-boomerang"}, no_anchor)

    def test_runtime_uses_a_releasing_current_weapon_cache(self) -> None:
        cache = (ROOT / "game" / "first_person_weapon_views.lua").read_text(encoding="utf-8")
        shooting_range = (ROOT / "game" / "shooting_range.lua").read_text(encoding="utf-8")
        world_scene = (ROOT / "game" / "world_scene.lua").read_text(encoding="utf-8")
        self.assertIn("if self.weapon~=weapon then", cache)
        self.assertIn("self:release()", cache)
        self.assertIn("function cache:release()", cache)
        self.assertIn("session.weaponViewState or session.aimMode", shooting_range)
        self.assertIn("function Range.setWeaponViewState", shooting_range)
        self.assertIn("ShootingRange.releaseWeaponViews", world_scene)

    def test_special_weapon_shot_sequences_use_only_approved_states(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")

        crossbow = self._manifest_entry(manifest, "critter-crossbow")
        self.assertLess(crossbow.index('state="release"'), crossbow.index('state="uncocked"'))
        self.assertGreaterEqual(crossbow.count('placement="hip"'), 2)

        for weapon in (
            "trail-slingshot",
            "wrist-braced-slingshot",
            "metal-scrap-slingshot",
            "long-hunting-slingshot",
        ):
            entry = self._manifest_entry(manifest, weapon)
            self.assertLess(entry.index('state="release"'), entry.index('state="lowReady"'))
            self.assertGreaterEqual(entry.count('placement="hip"'), 2)

        boomerang = self._manifest_entry(manifest, "scrap-boomerang")
        flight = boomerang.index('state="flight"')
        returning = boomerang.index('state="returning"')
        ready = boomerang.index('state="ready"')
        self.assertLess(flight, returning)
        self.assertLess(returning, ready)
        self.assertIn("restoresLoaded=true", boomerang)

        hunting_bow = self._manifest_entry(manifest, "hunting-bow")
        self.assertIn('fullDraw="hunting-bow-full-draw-aim.png"', hunting_bow)
        self.assertNotIn("steps={", hunting_bow)
        self.assertNotIn('state="release"', hunting_bow)

        self.assertIn("function Manifest.shotSequenceFor", manifest)
        self.assertIn("validateShotSequence(name,entry,issues)", manifest)

    def test_range_advances_and_clears_manifest_driven_view_sequences(self) -> None:
        shooting_range = (ROOT / "game" / "shooting_range.lua").read_text(encoding="utf-8")
        self.assertIn('require("game.first_person_weapon_manifest")', shooting_range)
        self.assertIn("FirstPersonWeaponManifest.shotSequenceFor(session.weapon)", shooting_range)
        self.assertIn("startWeaponViewSequence(session)", shooting_range)
        self.assertIn("updateWeaponViewSequence(session,dt)", shooting_range)
        self.assertIn("session.weaponViewState=step.state", shooting_range)
        self.assertIn("session.weaponViewPlacement=step.placement", shooting_range)
        self.assertIn("if restoresLoaded then", shooting_range)

        load_weapon = shooting_range.split("local function loadWeapon", 1)[1].split("\nend", 1)[0]
        reload_weapon = shooting_range.split("function Range.reload", 1)[1].split("\nend", 1)[0]
        self.assertIn("clearWeaponViewSequence(session)", load_weapon)
        self.assertIn("clearWeaponViewSequence(session)", reload_weapon)

    def test_impacts_are_target_local_and_hip_art_follows_touch_aim(self) -> None:
        shooting_range = (ROOT / "game" / "shooting_range.lua").read_text(encoding="utf-8")
        self.assertIn("offsetX=shotX-best.x,offsetY=shotY-best.y", shooting_range)
        self.assertIn("target.x+impact.offsetX,target.y+impact.offsetY", shooting_range)
        self.assertNotIn("impact.x,impact.y", shooting_range)

        self.assertIn("function Range.weaponViewPlacement", shooting_range)
        self.assertIn('if placement=="sights" then', shooting_range)
        self.assertIn("local HIP_CURSOR_OFFSET_X=472", shooting_range)
        self.assertIn("local HIP_CURSOR_OFFSET_Y=376", shooting_range)
        self.assertIn("local artX=aimX+HIP_CURSOR_OFFSET_X", shooting_range)
        self.assertIn("local artY=aimY+HIP_CURSOR_OFFSET_Y", shooting_range)
        self.assertIn("drawFirstPersonWeapon(assets,ui,session,x,y,sx,sy,placement)", shooting_range)

    def test_mobile_package_keeps_production_and_excludes_every_review_file(self) -> None:
        production = sorted(FIRST_PERSON_ROOT.glob("*.png"))
        review_files = sorted(
            path
            for review_dir in FIRST_PERSON_ROOT.glob("review-batch-*")
            for path in review_dir.rglob("*")
            if path.is_file()
        )

        self.assertEqual(EXPECTED_PRODUCTION_PNGS, len(production))
        self.assertTrue(review_files)
        for path in production:
            with self.subTest(production=path.name):
                self.assertTrue(runtime_asset(path))
        for path in review_files:
            with self.subTest(review=path.relative_to(FIRST_PERSON_ROOT).as_posix()):
                self.assertFalse(runtime_asset(path))


if __name__ == "__main__":
    unittest.main()
