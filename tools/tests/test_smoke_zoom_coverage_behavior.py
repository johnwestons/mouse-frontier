"""Exercise zoom smoke's evidence checks against missing and moved HUD output."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class SmokeZoomCoverageBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            Hud=assert(loadfile(root..'/tools/zoom-smoke/hud_checks.lua'))()
            function expect(value,message) assert(value,message) end
            function rangeHud() return {['TIME  60']={28,18,1.15,1.15},['AMMO  12']={28,56,.84,.84}} end
        ''')

    def test_empty_render_evidence_is_rejected(self):
        self.lua.execute('''
            for scene in pairs(Hud.required) do
                local ok,err=pcall(Hud.compare,scene,{},{},expect)
                assert(not ok and err:find('required HUD label',1,true))
            end
        ''')

    def test_missing_label_at_both_zooms_is_rejected(self):
        self.lua.execute('''
            local before,after=rangeHud(),rangeHud()
            before['AMMO  12']=nil; after['AMMO  12']=nil
            assert(not pcall(Hud.compare,'range',before,after,expect))
        ''')

    def test_disappearing_or_new_labels_are_rejected(self):
        self.lua.execute('''
            local before,after=rangeHud(),rangeHud()
            after['AMMO  12']=nil
            assert(not pcall(Hud.compare,'range',before,after,expect))
            after=rangeHud(); after['PAUSE']={0,0,1,1}
            assert(not pcall(Hud.compare,'range',before,after,expect))
        ''')

    def test_position_and_text_scale_drift_are_rejected(self):
        self.lua.execute('''
            for index=1,4 do
                local before,after=rangeHud(),rangeHud()
                after['TIME  60'][index]=after['TIME  60'][index]+.1
                assert(not pcall(Hud.compare,'range',before,after,expect))
            end
        ''')

    def test_positive_matching_coverage_passes(self):
        self.lua.execute('''
            assert(Hud.compare('range',rangeHud(),rangeHud(),expect)==2)
        ''')

    def test_collector_tracks_actual_mobile_and_special_scene_labels(self):
        self.lua.execute('''
            for _,label in ipairs({'STOP 1','HEALTH','LV 1 / AB 1','AMMUNITION',
                'TACTICAL ENCOUNTER  ROUND 1','OBJECTIVE  Defeat all threats',
                'JOYSTICK  MOVE  TAP ACTION TO INTERACT','PAUSE','HOLD  03:00','ROUNDS  48'}) do
                assert(Hud.captures(label),'collector omits '..label)
            end
            assert(not Hud.captures('ordinary world text') and not Hud.captures(nil))
        ''')


if __name__ == '__main__':
    unittest.main()
