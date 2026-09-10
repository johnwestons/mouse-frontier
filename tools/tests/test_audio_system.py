from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILDER_PATH = ROOT / "tools" / "build_mobile_package.py"


def load_builder():
    spec = importlib.util.spec_from_file_location("mouse_frontier_mobile_builder", BUILDER_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AudioSystemTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.builder = load_builder()

    def test_music_normalization_handles_nested_copy_suffixes(self) -> None:
        normalize = self.builder.normalized_music_stem
        self.assertEqual(normalize("Pixel Homecoming2 (1)"), "pixel homecoming")
        self.assertEqual(normalize("Pixel Homecoming2"), "pixel homecoming")
        self.assertEqual(normalize("Pixel Homecoming"), "pixel homecoming")

    def test_mobile_audio_selection_is_canonical_and_runtime_only(self) -> None:
        selected = self.builder.select_audio_sources()
        relatives = [path.relative_to(ROOT).as_posix() for path in selected]
        folded = [relative.casefold() for relative in relatives]

        music_keys: set[tuple[str, str]] = set()
        for source, relative in zip(selected, relatives):
            self.assertTrue(source.is_file())
            self.assertTrue(self.builder.runtime_audio(relative))
            if relative.startswith("sounds/music/"):
                key = (source.parent.as_posix(), self.builder.normalized_music_stem(source.stem))
                self.assertNotIn(key, music_keys, f"duplicate canonical music group: {relative}")
                music_keys.add(key)

        self.assertIn("sounds/music/chill/rainlit shelter.mp3", folded)
        self.assertNotIn("sounds/soundeffects/rain/rainlit shelter.mp3", folded)
        self.assertFalse(any("/train/traintraveling/" in relative for relative in folded))
        self.assertFalse(any("/nature/" in relative for relative in folded))
        self.assertFalse(any("/hurtmale/" in relative or "/hurtmob/" in relative for relative in folded))

    def test_lua_audio_contract_contains_lifecycle_and_priority_boundaries(self) -> None:
        audio = (ROOT / "game" / "audio.lua").read_text(encoding="utf-8")
        catalog = (ROOT / "game" / "audio_catalog.lua").read_text(encoding="utf-8")
        runtime = (ROOT / "game" / "audio_runtime.lua").read_text(encoding="utf-8")
        persistence = (ROOT / "game" / "persistence_runtime.lua").read_text(encoding="utf-8")
        weapon_catalog = (ROOT / "game" / "catalog.lua").read_text(encoding="utf-8")
        sound_profiles = (ROOT / "game" / "weapon_sound_profiles.lua").read_text(encoding="utf-8")

        self.assertIn("stopAndRelease(previous)", audio)
        self.assertIn("self.failedMusic[path]=true", audio)
        self.assertIn("self:refillShuffleBag(category)", audio)
        self.assertIn("function Audio:suspend", audio)
        self.assertIn("function Audio:resume", audio)
        self.assertIn('local WeaponSoundProfiles=require("game.weapon_sound_profiles")', runtime)
        self.assertIn("return WeaponSoundProfiles.forWeapon(weaponName,Catalog)", runtime)
        self.assertIn('file:find("eagle",1,true)', runtime)
        self.assertIn("gameplayOverrides={battle=true,bossFight=true,endingHappy=true}", catalog)
        self.assertIn('runtime.state~="game" and runtime.state~="event"', runtime)
        self.assertIn("focusAudio(focused)", persistence)

        ranged = set(re.findall(r'\["([^"]+)"\]=\{kind="ranged"', weapon_catalog))
        progression_payload = weapon_catalog.split("Catalog.weaponProgression = {", 1)[1].split("}", 1)[0]
        player_ranged = ranged & set(re.findall(r'"([^"]+)"', progression_payload))
        order_payload = sound_profiles.split("local rangedOrder={", 1)[1].split("}", 1)[0]
        assigned = re.findall(r'"([^"]+)"', order_payload)
        self.assertEqual(len(assigned), len(set(assigned)), "weapon sound assignments must be unique")
        self.assertEqual(player_ranged, set(assigned))
        self.assertNotIn("mob-spit", assigned)
        self.assertIn("local index=order[name] or (hash(name)%97+1)", sound_profiles)
        self.assertNotIn("love.math.random", sound_profiles)


if __name__ == "__main__":
    unittest.main()
