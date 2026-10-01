"""SKS-specific action and reload contracts for the Frontier 7.62 carbine."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


class Frontier762SksCycleSourceTests(unittest.TestCase):
    def test_sks_is_semiautomatic_and_uses_a_stripper_clip_reload_profile(self) -> None:
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")
        automatic = manifest.split("local AUTOMATIC_WEAPONS={", 1)[1].split("}", 1)[0]
        self.assertNotIn('"frontier-762-carbine"', automatic)
        self.assertIn('if id=="frontier-762-carbine" then return "sksStripperClip" end', manifest)
        self.assertIn("sksStripperClip=1.55", manifest)
        self.assertIn('["frontier-762-carbine"]=pair("frontier-762-carbine"', manifest)

        catalog = (ROOT / "game" / "catalog.lua").read_text(encoding="utf-8")
        self.assertIn('["frontier-762-carbine"]={kind="ranged",range=34,ammo="762x39",capacity=10}', catalog)

    def test_empty_sks_uses_the_open_carrier_pose(self) -> None:
        actions = (ROOT / "game" / "first_person_weapon_actions.lua").read_text(encoding="utf-8")
        self.assertIn('if action==nil and state.weapon=="frontier-762-carbine" then', actions)
        self.assertIn("if remaining~=nil and remaining<=0 then return FRAMES.reloadStart end", actions)
        self.assertIn("if progress<.20 then return FRAMES.reloadStart end", actions)
        self.assertIn("if progress<.66 then return FRAMES.reloadWork end", actions)
        self.assertIn("if progress<1 then return FRAMES.reloadFinish end", actions)

    def test_authored_action_atlas_has_six_separate_transparent_poses(self) -> None:
        path = ROOT / "assets" / "sprites" / "weapons" / "first-person" / "actions" / "frontier-762-carbine-actions.png"
        with Image.open(path) as atlas:
            self.assertEqual("RGBA", atlas.mode)
            self.assertEqual((1536, 1024), atlas.size)
            self.assertEqual(0, atlas.getchannel("A").getextrema()[0])
            cells = [
                atlas.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512)).tobytes()
                for row in range(2)
                for column in range(3)
            ]
            self.assertEqual(6, len(set(cells)))
            alpha = atlas.getchannel("A")
            for index in range(6):
                column, row = index % 3, index // 3
                cell = alpha.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512))
                visible = cell.point(lambda value: 255 if value >= 240 else 0)
                bounds = visible.getbbox()
                self.assertIsNotNone(bounds, f"action frame {index + 1} is empty")
                left, top, right, bottom = bounds
                margin = min(left, top, 512 - right, 512 - bottom)
                self.assertGreaterEqual(margin, 48, f"action frame {index + 1} clips at the cell edge")


if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class Frontier762SksCycleRuntimeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(
            "package.path=project_root..'/?.lua;'..package.path; "
            "Manifest=require('game.first_person_weapon_manifest'); "
            "Actions=require('game.first_person_weapon_actions')"
        )

    def test_sks_mode_and_reload_profile(self) -> None:
        self.assertTrue(self.lua.eval("Manifest.fireModesFor('frontier-762-carbine')[1]=='safe'"))
        self.assertTrue(self.lua.eval("Manifest.fireModesFor('frontier-762-carbine')[2]=='single'"))
        self.assertTrue(self.lua.eval("Manifest.fireModesFor('frontier-762-carbine')[3]==nil"))
        profile = self.lua.eval("Manifest.reloadProfileFor('frontier-762-carbine')")
        self.assertEqual("sksStripperClip", profile["style"])
        self.assertEqual(1.55, profile["duration"])

    def test_last_round_holds_carrier_open_until_reload_finishes(self) -> None:
        frame_index = self.lua.eval("Actions.frameIndex")
        self.assertEqual(1, frame_index(self.lua.table_from({"weapon": "frontier-762-carbine", "magazine": 1})))
        self.assertEqual(4, frame_index(self.lua.table_from({"weapon": "frontier-762-carbine", "magazine": 0})))
        self.assertEqual(4, frame_index(self.lua.table_from({"weapon": "frontier-762-carbine", "loaded": 0})))

        state = self.lua.table_from({"weapon": "frontier-762-carbine", "magazine": 0})
        self.lua.eval("Actions.beginReload")(state)
        self.assertEqual(4, frame_index(state))
        self.lua.eval("Actions.update")(state, 0.5)
        self.assertEqual(5, frame_index(state))
        self.lua.eval("Actions.update")(state, 0.6)
        self.assertEqual(6, frame_index(state))
        state["magazine"] = 10
        self.lua.eval("Actions.finish")(state)
        self.assertEqual(1, frame_index(state))


if __name__ == "__main__":
    unittest.main()
