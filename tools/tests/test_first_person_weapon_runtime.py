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
    def test_repaired_rifle_and_shotgun_frames_have_clear_backdrops(self) -> None:
        # Transparent corners alone did not catch the previous opaque halos.
        # These slim weapon silhouettes occupy less than 30% of a cell, even
        # during reload; the rejected black backdrops exceeded that envelope.
        repaired = (
            "frontier-556-carbine", "improvised-556-rifle", "compact-carbine",
            "frontier-762-carbine", "frontier-12g-pump-shotgun",
            "frontier-22-lever-rifle", "weathered-lever-rifle",
            "frontier-lever-rifle", "frontier-lever-carbine", "sawed-off-shotgun",
            "frontier-9mm-smg", "frontier-9mm-service-pistol",
        )
        for weapon in repaired:
            with Image.open(FIRST_PERSON_ROOT / "actions" / f"{weapon}-actions.png") as image:
                for index in range(6):
                    with self.subTest(weapon=weapon, frame=index + 1):
                        x, y = index % 3 * 512, index // 3 * 512
                        alpha = image.getchannel("A").crop((x, y, x + 512, y + 512))
                        self.assertLess(sum(alpha.histogram()[32:]) / (512 * 512), .30,
                                        "broad opaque backdrop surrounds the weapon")
                        bounds = alpha.point(lambda value: 255 if value >= 32 else 0).getbbox()
                        self.assertIsNotNone(bounds)
                        left, top, right, bottom = bounds
                        self.assertGreaterEqual(min(left, top, 512 - right, 512 - bottom), 16,
                                                "partially transparent art reaches the atlas gutter")

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

    def test_every_firearm_uses_six_authored_action_sprite_frames(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        weapon_ids = re.findall(r'^    \["([^"]+)"\]=pair\("([^"]+)"', manifest, re.MULTILINE)
        self.assertEqual(39, len(weapon_ids))
        self.assertTrue(all(weapon == asset_id for weapon, asset_id in weapon_ids))

        action_root = FIRST_PERSON_ROOT / "actions"
        expected = {f"{weapon}-actions.png" for weapon, _ in weapon_ids}
        actual = {path.name for path in action_root.glob("*-actions.png")}
        self.assertEqual(expected, actual)

        actions = (ROOT / "game" / "first_person_weapon_actions.lua").read_text(encoding="utf-8")
        pivots = {
            name: tuple(map(float, (grip_x, grip_y, bore_x, bore_y, muzzle_x, muzzle_y)))
            for name, grip_x, grip_y, bore_x, bore_y, muzzle_x, muzzle_y in re.findall(
                r'^    \["([^"]+)"\]=\{grip=\{x=([.\d]+),y=([.\d]+),aspect=1\},'
                r'bore=\{x=([.\d]+),y=([.\d]+)\},muzzle=\{x=([.\d]+),y=([.\d]+)\}\}',
                actions,
                re.MULTILINE,
            )
        }
        self.assertEqual({weapon for weapon, _ in weapon_ids}, set(pivots))

        for path in sorted(action_root.glob("*-actions.png")):
            with self.subTest(atlas=path.name):
                with Image.open(path) as image:
                    self.assertEqual("RGBA", image.mode)
                    self.assertEqual((1536, 1024), image.size)
                    self.assertEqual(0, image.getchannel("A").getextrema()[0])
                    cells = [
                        image.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512)).tobytes()
                        for row in range(2)
                        for column in range(3)
                    ]
                    self.assertEqual(6, len(set(cells)), "all authored action poses must be distinct")
                    minimum_margins = {
                        "frontier-lever-carbine-actions": 80,
                        "frontier-380-pocket-pistol-actions": 40,
                        "frontier-22-pocket-pistol-actions": 40,
                        "compact-carbine-actions": 48,
                        "frontier-45-1911-actions": 64,
                        "frontier-762-carbine-actions": 48,
                        "frontier-12g-pump-shotgun-actions": 40,
                        "frontier-556-carbine-actions": 30,
                        "frontier-9mm-glock-actions": 20,
                        "frontier-9mm-smg-actions": 24,
                        "frontier-compact-9mm-actions": 48,
                        "frontier-compact-9mm-pistol-actions": 31,
                        "frontier-9mm-service-pistol-actions": 24,
                        "frontier-pearl-pocket-pistol-actions": 19,
                        "wood-stock-survival-carbine-actions": 20,
                        "frontier-22-target-pistol-actions": 64,
                        "weathered-lever-rifle-actions": 32,
                        "machine-pistol-actions": 20,
                        "frontier-32-pocket-pistol-actions": 32,
                        "frontier-lever-rifle-actions": 40,
                        "frontier-long-22-target-pistol-actions": 64,
                        "frontier-single-shot-hunter-actions": 32,
                        "frontier-long-barrel-revolver-actions": 24,
                        "frontier-ak-compact-actions": 24,
                        "sawed-off-shotgun-actions": 24,
                        "compact-scrap-pistol-actions": 48,
                        "vintage-bolt-action-rifle-actions": 30,
                        "improvised-556-rifle-actions": 32,
                    }
                    alpha = image.getchannel("A")
                    minimum_margin = minimum_margins.get(path.stem, 20)
                    for index in range(6):
                        column, row = index % 3, index // 3
                        cell = alpha.crop((column * 512, row * 512,
                                           (column + 1) * 512, (row + 1) * 512))
                        visible = cell.point(lambda value: 255 if value >= 240 else 0)
                        bounds = visible.getbbox()
                        self.assertIsNotNone(bounds, f"action frame {index + 1} is empty")
                        left, top, right, bottom = bounds
                        margin = min(left, top, 512 - right, 512 - bottom)
                        self.assertGreaterEqual(margin, minimum_margin,
                            f"action frame {index + 1} remains too close to its atlas edge")
                    grip_x, grip_y, bore_x, bore_y, muzzle_x, muzzle_y = pivots[path.stem.removesuffix("-actions")]
                    self.assertGreater(abs(muzzle_x - bore_x) + abs(muzzle_y - bore_y), 0.08)
                    hip_flash = image.crop((512, 0, 1024, 512))
                    muzzle_px, muzzle_py = round(muzzle_x * 512), round(muzzle_y * 512)
                    flash_neighborhood = hip_flash.crop((max(0, muzzle_px - 96), max(0, muzzle_py - 96),
                                                          min(512, muzzle_px + 97), min(512, muzzle_py + 97)))
                    warm_flash_pixels = sum(
                        1 for red, green, blue, alpha in flash_neighborhood.get_flattened_data()
                        if alpha >= 160 and red >= 170 and green >= 75
                        and red > green * 1.15 and blue < green
                    )
                    self.assertGreaterEqual(warm_flash_pixels, 500,
                        "hip-fire sprite has no clear muzzle flash near its muzzle anchor")
                    ready_alpha = image.getchannel("A").crop((0, 0, 512, 512))
                    for pivot_name, x, y in (("bore", bore_x, bore_y), ("muzzle", muzzle_x, muzzle_y)):
                        px, py = round(x * 512), round(y * 512)
                        neighborhood = ready_alpha.crop((max(0, px - 12), max(0, py - 12),
                                                         min(512, px + 13), min(512, py + 13)))
                        visible = neighborhood.point(lambda alpha: 255 if alpha >= 160 else 0)
                        self.assertIsNotNone(visible.getbbox(), f"{pivot_name} pivot misses sprite pixels")

        shooting = (ROOT / "game" / "first_person_shooting.lua").read_text(encoding="utf-8")
        shooting_range = (ROOT / "game" / "shooting_range.lua").read_text(encoding="utf-8")
        action_pivots = set(re.findall(r'^    \["([^"]+)"\]=\{grip=', actions, re.MULTILINE))
        self.assertEqual({weapon for weapon, _ in weapon_ids}, action_pivots)
        self.assertNotIn("love.graphics", actions)
        self.assertNotIn("state.recoil", shooting)
        self.assertNotIn("recoil=", shooting)
        self.assertNotIn("recoil=", shooting_range)

    def test_every_firearm_has_four_transparent_ads_firing_sprite_frames(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        weapon_ids = re.findall(r'^    \["([^"]+)"\]=pair\("([^"]+)"', manifest, re.MULTILINE)
        self.assertEqual(39, len(weapon_ids))

        action_root = FIRST_PERSON_ROOT / "actions"
        expected = {f"{weapon}-ads-fire.png" for weapon, _ in weapon_ids}
        actual = {path.name for path in action_root.glob("*-ads-fire.png")}
        self.assertEqual(expected, actual)

        for path in sorted(action_root.glob("*-ads-fire.png")):
            with self.subTest(atlas=path.name):
                with Image.open(path) as image:
                    self.assertEqual("RGBA", image.mode)
                    # ADS uses a 2x2 grid; cell aspect follows each weapon's
                    # authored view. The runtime derives both cell dimensions.
                    self.assertEqual(0, image.width % 2)
                    self.assertEqual(0, image.height % 2)
                    frame_width, frame_height = image.width // 2, image.height // 2
                    self.assertGreaterEqual(frame_width, 512)
                    self.assertGreaterEqual(frame_height, 512)
                    alpha = image.getchannel("A")
                    self.assertEqual(0, alpha.getextrema()[0])
                    self.assertGreaterEqual(alpha.getextrema()[1], 254)
                    frames = [
                        image.crop((column * frame_width, row * frame_height,
                                    (column + 1) * frame_width, (row + 1) * frame_height))
                        for row in range(2)
                        for column in range(2)
                    ]
                    self.assertEqual(4, len(set(frame.tobytes() for frame in frames)),
                                     "all ADS ready/fire/recoil/settle poses must be distinct")
                    ads_flash_pixels = sum(
                        1 for red, green, blue, alpha in frames[1].get_flattened_data()
                        if alpha >= 160 and red >= 170 and green >= 75
                        and red > green * 1.15 and blue < green
                    )
                    self.assertGreaterEqual(ads_flash_pixels, 500,
                        "ADS firing sprite frame has no clear muzzle flash")
                    for index, frame in enumerate(frames, start=1):
                        visible = frame.getchannel("A").point(lambda value: 255 if value >= 160 else 0)
                        bounds = visible.getbbox()
                        self.assertIsNotNone(bounds, f"ADS frame {index} has no visible sprite")
                        left, top, right, bottom = bounds
                        margin = min(left, top, frame.width - right, frame.height - bottom)
                        self.assertGreaterEqual(margin, 32,
                            f"ADS frame {index} is still clipped by the atlas edge")

        anchor_block = manifest.split("local ADS_ACTION_ANCHORS={", 1)[1].split(
            "local ADS_ACTION_FRAME_ANCHORS={", 1)[0]
        anchor_overrides = {
            name: (float(x), float(y))
            for name, x, y in re.findall(
                r'^\s*\["([^"]+)"\]=\{x=([.\d]+),y=([.\d]+),calibrated=true\},?$',
                anchor_block,
                re.MULTILINE,
            )
        }
        base_anchors = {
            name: (float(x), float(y))
            for name, x, y in re.findall(
                r'^    \["([^"]+)"\]=pair\("[^"]+",\{x=([.\d]+),y=([.\d]+),calibrated=true\}\)',
                manifest,
                re.MULTILINE,
            )
        }
        all_anchors = {**base_anchors, **anchor_overrides}
        self.assertEqual({weapon for weapon, _ in weapon_ids}, set(all_anchors))
        frame_anchor_block = manifest.split("local ADS_ACTION_FRAME_ANCHORS={", 1)[1].split(
            "local AUTOMATIC_WEAPONS={", 1)[0]
        frame_two_overrides = {
            name: (float(x), float(y))
            for name, x, y in re.findall(
                r'^\s*\["([^"]+)"\]=\{\[2\]=\{x=([.\d]+),y=([.\d]+),calibrated=true\}\},?$',
                frame_anchor_block,
                re.MULTILINE,
            )
        }
        self.assertEqual({"frontier-45-1911", "vintage-bolt-action-rifle", "frontier-sr22-pistol",
                          "frontier-compact-9mm", "frontier-380-pocket-pistol",
                          "frontier-pearl-pocket-pistol", "frontier-22-target-pistol",
                          "heavy-frontier-pistol", "frontier-long-barrel-revolver",
                          "frontier-lever-rifle", "wood-stock-survival-carbine",
                          "frontier-lever-carbine", "rugged-submachine-gun",
                          "sawed-off-shotgun", "machine-pistol", "frontier-9mm-service-pistol",
                          "frontier-9mm-glock", "frontier-762-carbine", "patched-22-survival-rifle",
                          "compact-carbine", "improvised-556-rifle", "improvised-service-rifle"},
                         set(anchor_overrides))
        for name, (x, y) in all_anchors.items():
            with self.subTest(sight_anchor=name):
                with Image.open(action_root / f"{name}-ads-fire.png") as image:
                    frame_width, frame_height = image.width // 2, image.height // 2
                    ready = image.getchannel("A").crop((0, 0, frame_width, frame_height))
                    px, py = round(x * (frame_width - 1)), round(y * (frame_height - 1))
                    neighborhood = ready.crop((max(0, px - 24), max(0, py - 24),
                                               min(frame_width, px + 25), min(frame_height, py + 25)))
                    visible = neighborhood.point(lambda value: 255 if value >= 160 else 0)
                    self.assertIsNotNone(visible.getbbox(),
                        "ADS ready anchor is detached from the rifle's sight line")
        self.assertEqual({"frontier-45-1911", "sawed-off-shotgun"}, set(frame_two_overrides))
        with Image.open(action_root / "frontier-45-1911-ads-fire.png") as image:
            flash = image.getchannel("A").crop((512, 0, 1024, 768))
            x, y = frame_two_overrides["frontier-45-1911"]
            px, py = round(x * 511), round(y * 767)
            neighborhood = flash.crop((max(0, px - 24), max(0, py - 24),
                                       min(512, px + 25), min(768, py + 25)))
            visible = neighborhood.point(lambda value: 255 if value >= 160 else 0)
            self.assertIsNotNone(visible.getbbox(),
                "1911 ADS flash frame anchor missed its iron sight")

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
        self.assertIn("offsetX=pelletX-best.x,offsetY=pelletY-best.y", shooting_range)
        self.assertIn("target.x+impact.offsetX,target.y+impact.offsetY", shooting_range)
        self.assertNotIn("impact.x,impact.y", shooting_range)

        self.assertIn("function Range.weaponViewPlacement", shooting_range)
        self.assertIn('if placement=="sights" then', shooting_range)
        self.assertIn("MobileAim.placement(session.weapon,state,session.aimMode,aimX,aimY,960,720)", shooting_range)
        self.assertNotIn("HIP_CURSOR_OFFSET_", shooting_range)
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
