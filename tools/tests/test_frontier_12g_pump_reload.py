"""Behavioral contracts for the Frontier 12g pump shotgun tube reload."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


class Frontier12gPumpReloadSourceTests(unittest.TestCase):
    def test_pump_tube_uses_staged_shell_timing_without_changing_other_tube_reload(self) -> None:
        actions = (ROOT / "game" / "first_person_weapon_actions.lua").read_text(encoding="utf-8")
        shooting = (ROOT / "game" / "first_person_shooting.lua").read_text(encoding="utf-8")
        manifest = (ROOT / "game" / "first_person_weapon_manifest.lua").read_text(encoding="utf-8")

        self.assertIn('if profile.style=="pumpTube" then', actions)
        self.assertIn("local PUMP_TUBE_RELOAD_TIMING={startSeconds=.28,roundSeconds=.42,finishSeconds=.28}", actions)
        self.assertIn("while state.tubeReloadRoundTimer<=0", actions)
        self.assertIn('if profile.style=="pumpTube" then', shooting)
        self.assertIn('if profile and profile.style=="tubeLever" and rounds then state.magazine=0 end', shooting)
        self.assertIn('if id=="frontier-12g-pump-shotgun" then return "pumpTube" end', manifest)


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class Frontier12gPumpReloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(
            "package.path=project_root..'/?.lua;'..package.path; "
            "Shooting=require('game.first_person_shooting'); "
            "Actions=require('game.first_person_weapon_actions')"
        )

    def test_shells_insert_individually_and_reload_preserves_loaded_rounds(self) -> None:
        state = self.lua.table_from(
            {
                "weapon": "frontier-12g-pump-shotgun",
                "ammoType": "12-gauge",
                "capacity": 6,
                "magazine": 2,
                "reloadTimer": 0,
                "cooldown": 0,
                "borrowed": False,
            }
        )
        data = self.lua.table_from({"ammo": self.lua.table_from({"12-gauge": 4})})
        quest = self.lua.table_from({})

        self.assertTrue(self.lua.eval("Shooting.reload")(state, data, quest))
        self.assertEqual(2, state["magazine"], "starting shells stay loaded during a tube reload")
        self.assertEqual(2, state["tubeReloadTotalRounds"], "only the two missing shells are scheduled")
        self.assertAlmostEqual(1.40, state["reloadTimer"], places=6)
        self.assertEqual(4, self.lua.eval("Actions.frameIndex")(state))
        self.assertEqual((False, "busy"), self.lua.eval("Shooting.fire")(state, data, quest))

        update = self.lua.eval("Shooting.update")
        update(state, 0.69, data, quest)
        self.assertEqual(2, state["magazine"], "no shell is inserted before the first shell interval")
        self.assertEqual(5, self.lua.eval("Actions.frameIndex")(state))

        update(state, 0.02, data, quest)
        self.assertEqual(3, state["magazine"], "the first shell arrives after start plus one interval")
        update(state, 0.40, data, quest)
        self.assertEqual(3, state["magazine"], "the next shell waits for its own interval")
        update(state, 0.02, data, quest)
        self.assertEqual(4, state["magazine"])
        self.assertEqual(6, self.lua.eval("Actions.frameIndex")(state))

        update(state, 0.28, data, quest)
        self.assertEqual(4, state["magazine"])
        self.assertEqual(1, self.lua.eval("Actions.frameIndex")(state))
        self.assertEqual(0, state["reloadTimer"])


if __name__ == "__main__":
    unittest.main()
