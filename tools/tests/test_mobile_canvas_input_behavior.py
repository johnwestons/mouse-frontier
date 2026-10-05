"""Modal touch controls and canvas drags preserve the player's intended action."""
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
class MobileCanvasInputBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(r'''
            love={system={getOS=function() return 'Android' end}}
            Controls=require('game.mobile_controls')
            function canvasHarness()
                local h={presses=0,releases=0,moves={}}
                h.controls=Controls.new({enabled=true,toGame=function(x,y) return x,y end,
                    pressKey=function() end,releaseKey=function() end,
                    pressPointer=function() h.presses=h.presses+1 end,
                    releasePointer=function() h.releases=h.releases+1 end,
                    movePointer=function(x,y) h.moves[#h.moves+1]={x=x,y=y} end})
                return h
            end
        ''')

    def test_started_drag_forwards_return_to_start_and_small_movements(self) -> None:
        self.lua.execute(r'''
            local h=canvasHarness()
            h.controls:touchpressed('rag',500,300)
            h.controls:touchmoved('rag',540,300,40,0)
            h.controls:touchmoved('rag',510,300,-30,0)
            h.controls:touchmoved('rag',500,300,-10,0)
            h.controls:touchmoved('rag',498,300,-2,0)
            h.controls:touchreleased('rag',498,300)
            assert(h.presses==1 and h.releases==1,'a drag must press and release once')
            assert(#h.moves==4,'movement inside the initial drag threshold was swallowed')
            for i,x in ipairs({540,510,500,498}) do assert(h.moves[i].x==x) end
            assert(next(h.controls.touches)==nil,'released drag leaked a touch')
        ''')

    def test_subthreshold_gesture_remains_one_tap(self) -> None:
        self.lua.execute(r'''
            local h=canvasHarness()
            h.controls:touchpressed('tap',500,300)
            h.controls:touchmoved('tap',508,300,8,0)
            h.controls:touchmoved('tap',500,300,-8,0)
            assert(h.presses==0 and #h.moves==0,'small jitter incorrectly started dragging')
            h.controls:touchreleased('tap',500,300)
            assert(h.presses==1 and h.releases==1 and #h.moves==0)
            assert(next(h.controls.touches)==nil,'released tap leaked a touch')
        ''')

    def test_dialogue_blocks_joystick_but_keeps_context_action_at_scaled_coordinates(self) -> None:
        self.lua.execute(r'''
            local runtime={state='game',scene='stop',dialogue={choice=true},questOffer={kind='aid'}}
            local keys,pointers={},0
            local input={keypressed=function(key) keys[#keys+1]=key end,keyreleased=function() end,
                mousepressed=function() pointers=pointers+1 end,mousemoved=function() end,mousereleased=function() end,
                beginTouchPickup=function() return false end}
            local mobile=require('game.mobile_runtime').new({runtime=runtime,ui={},maintenanceSession={open=false},
                mobileControls=Controls,width=960,height=720,
                viewportToGame=function(x,y) return (x-100)/2,(y-20)/2 end,
                getCameraZoom=function() return 1 end,setCameraZoom=function() end,
                beginCameraPan=function() end,moveCameraPan=function() end,endCameraPan=function() end,
                getGameplayInput=function() return input end})
            local controls=mobile.initialize()
            assert(controls:isGameplayActive() and not controls:isMovementActive(),
                'dialogue contextual actions and movement must have distinct availability')
            mobile.touchpressed('accept-panel',600,1020)
            assert(controls.touches['accept-panel'].kind=='canvasPointer','dialogue panel was captured as joystick')
            mobile.touchreleased('accept-panel',600,1020)
            assert(pointers==1 and controls.axisX==0 and controls.axisY==0)
            local x,y=100+controls.primary.x*2,20+controls.primary.y*2
            mobile.touchpressed('context-accept',x,y)
            mobile.touchreleased('context-accept',x,y)
            assert(#keys==1 and keys[1]=='e','contextual Accept action became unavailable')
            assert(next(controls.touches)==nil)
        ''')


if __name__ == "__main__":
    unittest.main()
