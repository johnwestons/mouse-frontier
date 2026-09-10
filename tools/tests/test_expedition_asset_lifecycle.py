"""Check that scene streaming cannot dispose another runtime's sprite frames."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class ExpeditionAssetLifecycleTests(unittest.TestCase):
    def test_shared_frames_survive_surface_dungeon_battle_and_save_switch_cleanup(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + lua.globals().package.path
        lua.execute(r'''
            local Assets=require('game.assets')
            -- Initialize exactly the normal lazy table registry without loading
            -- the unrelated game's full image collection into this fixture.
            local prepare
            for index=1,100 do
                local name,value=debug.getupvalue(Assets.load,index)
                if not name then break end
                if name=='prepareLazyImages' then prepare=value; break end
            end
            assert(prepare,'asset loader did not expose its lazy-table initializer')
            local idle,attack={},{}
            prepare(idle); prepare(attack)
            local bandit={released=0,release=function(self) self.released=self.released+1 end}
            local boss={released=0,release=function(self) self.released=self.released+1 end}
            local ordinary={released=0,release=function(self) self.released=self.released+1 end}
            Assets.markExternallyOwned(bandit); Assets.markExternallyOwned(boss)
            idle['sludge-bandit.png']=bandit; attack['sludge-bandit.png']=bandit
            idle['sludge-badger-boss.png']=boss; attack['sludge-badger-boss.png']=boss
            idle['ordinary-enemy.png']=ordinary
            for _,keep in ipairs({{['sludge-bandit.png']=true},{['sludge-badger-boss.png']=true},{},{}}) do
                Assets.retainAnimationImages({idle,attack},keep)
                assert(idle['sludge-bandit.png']==bandit and attack['sludge-bandit.png']==bandit)
                assert(idle['sludge-badger-boss.png']==boss and attack['sludge-badger-boss.png']==boss)
                assert(bandit.released==0 and boss.released==0)
            end
            assert(ordinary.released==1 and rawget(idle,'ordinary-enemy.png')==nil)
        ''')


if __name__ == "__main__":
    unittest.main()
