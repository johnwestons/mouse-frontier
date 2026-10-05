"""Title-screen scenes play in random order without repeats within a round."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class TitleSnapshotBehaviorTests(unittest.TestCase):
    def test_randomized_scene_round_has_no_repeats_until_every_scene_is_shown(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().project_root = ROOT.as_posix()
        lua.execute(r'''
            package.path=project_root..'/?.lua;'..package.path

            local function shuffledOrder(randomResult)
                love={math={random=function(low,high)
                    if randomResult=="first" then return low end
                    return high
                end}}
                package.loaded["game.title_snapshots"]=nil
                local snapshots=require("game.title_snapshots")
                local count=#snapshots.presets
                local order={snapshots.playback(0,0).id,snapshots.playback(0,1).id}
                for event=2,count-1 do
                    local side=event%2==0 and 1 or 0
                    order[#order+1]=snapshots.playback((event-1)*18,side).id
                end

                local seen,seenCount={},0
                for _,id in ipairs(order) do
                    assert(not seen[id],"scene repeated before the full round: "..id)
                    seen[id]=true; seenCount=seenCount+1
                end
                assert(#order==count and seenCount==count,"every title scene appears once per round")
                for second=0,count*18+36,3 do
                    assert(snapshots.playback(second,0).id~=snapshots.playback(second,1).id,
                        "the two bays must not show the same scene together")
                end
                assert(snapshots.playback((count-1)*18,0).id==order[1],"next round begins after all scenes appeared")
                return order
            end

            local first=shuffledOrder("first")
            local last=shuffledOrder("last")
            assert(first[1]~=last[1],"scene order must respond to the random shuffle")
        ''')


if __name__ == "__main__":
    unittest.main()
