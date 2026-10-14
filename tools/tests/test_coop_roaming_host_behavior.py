"""Host-only keyboard/controller/touch encounter decisions, with no automatic close."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class RoamingHostTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Host=require('game.coop_roaming_host'); calls={}; delegated=0; neutralized=0; updates=0; boards=0; succeed=false
            pending={id='p:1:e1',leadId='e1',enemyIds={'e1'}}
            runtime={state='game',saveData={roamingEncounter=pending},inventoryOpen=true,firstAid={},outfitCraftingOpen=true}
            context={runtime=runtime,ui={},screenToGame=function(x,y) return x/2,y/2 end,
                neutralize=function() neutralized=neutralized+1 end,commands={submit=function(name,args)
                    calls[#calls+1]={name=name,args=args}; return {ok=succeed,reason=not succeed and 'save_pending' or nil}
                end},battleEntered=function() boards=boards+1 end}
            local base={update=function() updates=updates+1 end}
            for _,event in ipairs({'keypressed','gamepadpressed','mousepressed','touchpressed','textinput','wheelmoved'}) do
                base[event]=function() delegated=delegated+1 end
            end
            app=Host.wrap(base,context)
        ''')

    def test_wait_and_cancel_never_progress_and_pause_closes_only_local_workbench(self):
        self.lua.execute('''
            app.update(.1); app.keypressed('escape'); app.gamepadpressed(nil,'b'); app.textinput('ignored'); app.wheelmoved(1,1)
            assert(#calls==0 and delegated==0 and updates==1 and neutralized==1)
            assert(not runtime.inventoryOpen and not runtime.firstAid and not runtime.outfitCraftingOpen)
            assert(runtime.saveData.roamingEncounter==pending)
        ''')

    def test_keyboard_and_controller_send_exact_host_decisions_and_failed_choice_stays_open(self):
        self.lua.execute('''
            app.keypressed('return'); assert(calls[1].name=='battle.begin' and calls[1].args.enemyIds[1]=='e1')
            app.keypressed('right'); app.gamepadpressed(nil,'a'); assert(calls[2].name=='scene.returnTrain')
            assert(runtime.saveData.roamingEncounter==pending and delegated==0)
            assert(boards==0); succeed=true; app.keypressed('left'); app.keypressed('return'); assert(boards==1)
        ''')

    def test_mouse_touch_use_viewport_coordinates_and_never_fall_into_world_controls(self):
        self.lua.execute('''
            app.mousepressed(690,820,1); assert(calls[1].name=='battle.begin')
            app.touchpressed('t',1230,820); assert(calls[2].name=='scene.returnTrain')
            app.mousepressed(0,0,1); assert(#calls==2 and delegated==0)
            runtime.saveData.roamingEncounter=nil; app.keypressed('space'); app.touchpressed('t',0,0)
            assert(delegated==2)
        ''')


if __name__ == '__main__':
    unittest.main()
