from __future__ import annotations

import struct
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"not a PNG: {path}")
    return struct.unpack(">II", data[16:24])


class ExpeditionFrameworkTests(unittest.TestCase):
    def test_first_area_has_large_surface_dungeon_and_production_art(self) -> None:
        areas = (ROOT / "game" / "expedition_areas.lua").read_text(encoding="utf-8")
        self.assertIn('Areas.FIRST_STOP = 6', areas)
        self.assertIn('Areas.SURFACE_ID = "stop06-outskirts"', areas)
        self.assertIn('Areas.DUNGEON_ID = "stop06-buried-waystation"', areas)
        self.assertIn('kind="returnStop"', areas)
        self.assertIn('kind="chest"', areas)
        self.assertIn('boss=true', areas)
        self.assertIn('requires="bossDefeated"', areas)

        expected_maps = {
            "outskirts-background.png": (1672, 941),
            "buried-waystation-background.png": (1672, 941),
        }
        for name, dimensions in expected_maps.items():
            self.assertEqual(png_size(ROOT / "assets" / "sprites" / "expeditions" / "stop06" / name), dimensions)

    def test_corrupted_mob_action_atlases_are_consistent(self) -> None:
        atlas_dir = ROOT / "assets" / "sprites" / "Mobs" / "expedition"
        for name in ("sludge-bandit-action-atlas.png", "sludge-badger-boss-action-atlas.png"):
            width, height = png_size(atlas_dir / name)
            self.assertEqual((width, height), (1536, 1024))
            self.assertEqual((width // 3, height // 2), (512, 512))

        runtime = (ROOT / "game" / "expedition_runtime.lua").read_text(encoding="utf-8")
        for table in ("mobImages", "mobIdleImages", "mobWalkImages", "mobAttackImages", "mobHitImages", "mobDeathImages"):
            self.assertIn(f"{table}[file]", runtime)
        self.assertIn('Sprites.load(spec)', runtime)
        self.assertIn('Assets.markExternallyOwned(image)', runtime)

    def test_field_damage_and_battle_handoff_contract(self) -> None:
        roaming = (ROOT / "game" / "roaming_mobs.lua").read_text(encoding="utf-8")
        battle = (ROOT / "game" / "battle_runtime.lua").read_text(encoding="utf-8")
        controller = (ROOT / "game" / "battle_controller.lua").read_text(encoding="utf-8")

        self.assertIn('hp=saved.hp,maxHp=saved.maxHp', roaming)
        self.assertIn('returnContext={scene="expedition",areaId=ctx.area.id,x=ctx.player.x,y=ctx.player.y}', roaming)
        self.assertIn('transient.state="windup"', roaming)
        self.assertIn('if hitDistance<=reach', roaming)
        self.assertIn('local carried=encounter.enemyStates and encounter.enemyStates[i]', controller)
        self.assertIn('hp=unitHP,maxHP=unitMaxHP', controller)
        self.assertIn('runtime.player.x,runtime.player.y=destination.x,destination.y', battle)
        self.assertIn('runtime.saveData.activeExpeditionArea=nil; returnToTrain(false)', battle)
        self.assertIn('syncExpeditionEnemies(battle)', battle)

    def test_expedition_state_is_saved_and_area_drops_are_scoped(self) -> None:
        schema = (ROOT / "game" / "save_schema.lua").read_text(encoding="utf-8")
        bootstrap = (ROOT / "game" / "session_bootstrap.lua").read_text(encoding="utf-8")
        inventory = (ROOT / "game" / "inventory_actions.lua").read_text(encoding="utf-8")
        world = (ROOT / "game" / "world_scene.lua").read_text(encoding="utf-8")
        presentation = (ROOT / "game" / "presentation_runtime.lua").read_text(encoding="utf-8")
        startup = (ROOT / "game" / "startup_composition.lua").read_text(encoding="utf-8")
        input_composition = (ROOT / "game" / "input_composition.lua").read_text(encoding="utf-8")
        mobile = (ROOT / "game" / "mobile_runtime.lua").read_text(encoding="utf-8")

        match = re.search(r"CURRENT_VERSION\s*=\s*(\d+)", schema)
        self.assertIsNotNone(match)
        self.assertGreaterEqual(int(match.group(1)), 31)
        self.assertIn('"expeditions"', schema)
        self.assertIn('data.scene~="expedition"', schema)
        self.assertIn('expeditions={}', bootstrap)
        self.assertIn('ExpeditionAreas.ensure(data)', bootstrap)
        self.assertIn('dropped.expeditionAreaId=runtime.saveData.activeExpeditionArea', inventory)
        self.assertIn('item.expeditionAreaId==runtime.saveData.activeExpeditionArea', world)
        self.assertIn('local function screenToWorld(x,y)', presentation)
        self.assertIn('screenToGame=platform.presentationRuntime.screenToWorld', startup)
        self.assertIn('worldCoordinates=platform.presentationRuntime.worldCoordinates', input_composition)
        self.assertIn('kind=="expedition"', mobile)
        self.assertIn('runtime.scene=="expedition" then return "f","ATTACK"', mobile)


if __name__ == "__main__":
    unittest.main()
