"""The outer checkpoint barrier blocks every inner gameplay wrapper."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CheckpointHostTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            calls={}; pending=true; canSave=false; retryCount=0; neutralized=0; serviced=0
            app={}; for _,name in ipairs({'update','draw','keypressed','keyreleased','mousepressed','mousereleased',
                'mousemoved','touchpressed','touchmoved','touchreleased','wheelmoved','gamepadpressed',
                'gamepadreleased','gamepadaxis','textinput','focus','quit'}) do
                local callback=name
                app[callback]=function() calls[callback]=(calls[callback] or 0)+1 end
            end
            runtime={state='game',saveData={},player={moving=true,velocityX=20,velocityY=3}}
            ui={handleOptionsMousePressed=function(x,y)
                optionsClicked=true
                if x<100 then ui.optionsOpen=false; ui.escMenuOpen=true end
            end,handleOptionsKey=function(value) optionsKey=value end}
            local commands={checkpointStatus=function() return {pending=pending} end,
                retryCheckpoint=function() retryCount=retryCount+1; if canSave then pending=false end; return not pending end,
                suspendActivities=function() suspended=true end}
            app=require('game.coop_checkpoint_host').wrap(app,{runtime=runtime,ui=ui,commands=commands,
                audio={update=function() audioUpdated=true end,focus=function() audioFocused=true end,shutdown=function() audioClosed=true end},
                neutralize=function() neutralized=neutralized+1 end,
                serviceSession=function() serviced=serviced+1 end,
                screenToGame=function(x,y) return x,y end,requestQuit=function() quitRequested=true end})
        ''')

    def test_blocked_update_services_connection_and_audio_without_advancing_world(self):
        self.lua.execute('''
            for index=1,20 do app.update(.1) end
            assert(not calls.update and serviced==20 and audioUpdated and neutralized==1 and suspended)
            assert(ui.checkpointBlocked and not runtime.player.moving and runtime.player.velocityX==0)
            canSave=true; app.keypressed('r')
            assert(not pending and not ui.checkpointBlocked and retryCount==1)
            app.update(.1); assert(calls.update==1 and serviced==21)
        ''')

    def test_keyboard_mouse_touch_controller_and_debug_inputs_cannot_bypass_barrier(self):
        self.lua.execute('''
            app.keypressed('f12'); app.keypressed('y'); app.keyreleased('e')
            app.mousepressed(0,0,1); app.mousereleased(300,300,1); app.mousemoved(400,400,20,20)
            app.touchpressed('finger',0,0); app.touchmoved('finger',400,400); app.touchreleased('finger',400,400)
            app.gamepadpressed({},'x'); app.gamepadreleased({},'a'); app.gamepadaxis({},'leftx',1)
            app.wheelmoved(0,1); app.textinput('cheat')
            assert(next(calls)==nil and pending and retryCount==0)
        ''')

    def test_local_settings_are_available_while_world_and_story_stay_blocked(self):
        self.lua.execute('''
            app.touchpressed('settings',480,460); assert(ui.optionsOpen)
            app.keypressed('2'); assert(optionsKey=='2' and not calls.keypressed)
            app.mousepressed(300,300,1); assert(optionsClicked)
            app.mousepressed(50,50,1); assert(not ui.optionsOpen and not ui.escMenuOpen)
            assert(pending and not calls.mousepressed)
            local Progression=require('game.coop_progression')
            runtime.session={networkMode='host',checkpointPending=true}
            assert(not Progression.allowed(runtime,'travel.depart'))
            assert(require('game.world_pause').isPaused(runtime,{},{}))
        ''')

    def test_controller_can_retry_without_resending_the_action(self):
        self.lua.execute('''
            app.gamepadpressed({},'a'); assert(pending and retryCount==1)
            canSave=true; app.gamepadpressed({},'a')
            assert(not pending and retryCount==2 and not calls.gamepadpressed)
            app.keypressed('e'); assert(calls.keypressed==1)
        ''')

    def test_native_quit_waits_for_explicit_unsaved_confirmation(self):
        self.lua.execute('''
            assert(app.quit()==true and not calls.quit and not audioClosed)
            app.mousepressed(480,460,1); assert(not quitRequested)
            app.mousepressed(680,460,1); assert(not quitRequested)
            app.mousepressed(680,460,1); assert(quitRequested)
            assert(app.quit()==false and audioClosed and not calls.quit)
        ''')

    def test_focus_return_can_resolve_a_transient_error_without_inner_gameplay_callbacks(self):
        self.lua.execute('''
            app.focus(false); assert(audioFocused and not calls.focus and retryCount==0)
            canSave=true; app.focus(true)
            assert(not pending and retryCount==1 and not calls.focus)
            app.focus(false); assert(calls.focus==1)
        ''')


if __name__ == '__main__':
    unittest.main()
