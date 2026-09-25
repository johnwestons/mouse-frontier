"""Keep painted stop paths inside the visible playfield."""
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


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class StopWalkMaskBoundsTests(unittest.TestCase):
    def test_white_edge_does_not_allow_player_offscreen(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + lua.globals().package.path
        lua.execute(r'''
            local Settlements=require('game.settlements')
            Settlements.walkMasks={[10]={
                getDimensions=function() return 240,135 end,
                getPixel=function(_,x,y)
                    assert(x>=0 and x<240 and y>=0 and y<135)
                    return 1,1,1,1
                end,
            }}
            assert(Settlements.isWalkable(10,820,610),'caravan gate should remain accessible')
            for _,point in ipairs({{820,720},{820,740},{960,610},{-1,610},{820,-1}}) do
                assert(not Settlements.isWalkable(10,point[1],point[2]),
                    'painted edge allowed walking outside the stop')
            end
            local x,y=Settlements.move(10,820,700,820,740)
            assert(x==820 and y==700,'movement crossed the bottom of the playfield')
        ''')
