"""Actual guest settings/device stores through the production application router."""
import unittest
import test_coop_guest_settings_behavior as settings_tests


class GuestSettingsRoutingTests(unittest.TestCase):
    setUp = settings_tests.GuestSettingsTests.setUp

    def wrap(self):
        self.lua.execute('''
            view.settings=s; callbacks={}; fallback=0; panelDraws=0; checkpoint=false
            function controller:isClient() return true end
            function controller:captures() return self.menuOpen end
            function controller:update() end
            controller.clientView=view
            function controller:stop() end
            for _,name in ipairs({'keypressed','keyreleased','mousepressed','mousereleased','touchpressed',
                'touchreleased','touchmoved','mousemoved','wheelmoved','gamepadpressed','gamepadreleased','gamepadaxis'}) do
                local label=name; view[name]=function(_,...) callbacks[#callbacks+1]={name=label,args={...}}; return true end
            end
            view.draw=function() callbacks[#callbacks+1]={name='draw'} end
            view.focus=function(_,focused) s:focus(focused) end
            local app={}
            for _,name in ipairs({'update','draw','keypressed','keyreleased','textinput','mousepressed','mousereleased',
                'mousemoved','touchpressed','touchreleased','touchmoved','gamepadpressed','gamepadreleased','gamepadaxis',
                'wheelmoved','focus','quit'}) do app[name]=function() fallback=fallback+1 end end
            package.loaded['game.local_play_panel']={new=function() return {
                draw=function() panelDraws=panelDraws+1 end,stopTextInput=function() end,
                key=function() return true end,click=function() return true end,textinput=function() return true end} end}
            router=require('game.local_play_host').wrap(app,{controller=controller,ui={},runtime=runtime,
                commands={checkpointStatus=function() return {pending=checkpoint} end},bindings=bindings,
                screenToGame=function(x,y) return (x-20)/2,(y-10)/2 end,idleUpdate=function() end})
            function point(id)
                router.draw()
                for _,t in ipairs(s:targets()) do if t.id==id then
                    return (t.rect.x+t.rect.w/2)*2+20,(t.rect.y+t.rect.h/2)*2+10
                end end
                error('actual settings control missing '..id)
            end
        ''')

    def test_settings_draw_and_mouse_action_precede_local_play_capture(self):
        self.wrap()
        self.lua.execute('''
            s:open();local x,y=point('musicVolume+')
            assert(panelDraws==0 and #texts>0)
            router.mousepressed(x,y,1,false);router.mousereleased(x,y,1,false)
            assert(math.abs(Prefs.new(fs).values.audio.musicVolume-.15)<1e-9)
            assert(fallback==0 and #callbacks==0);unchanged()
        ''')

    def test_touch_close_release_cannot_leak_into_gameplay(self):
        self.wrap()
        self.lua.execute('''
            s:open();local x,y=point('close');router.touchpressed('close',x,y)
            assert(not s:isOpen() and controller.menuOpen)
            controller.menuOpen=false;router.touchreleased('close',x,y)
            assert(#callbacks==0 and fallback==0)
            router.touchreleased('other',x,y);assert(callbacks[1].name=='touchreleased');unchanged()
        ''')

    def test_raw_keyboard_and_controller_capture_reach_settings_once(self):
        self.wrap()
        self.lua.execute('''
            s:open();s:beginCapture('key','inventory');router.keypressed('z');router.keyreleased('z')
            assert(B.new(fs).keyboard.inventory=='z')
            bindings:clear('button','radio')
            s:beginCapture('button','inventory');router.gamepadpressed({},'rightstick');router.gamepadreleased({},'rightstick')
            assert(B.new(fs).buttons.inventory=='rightstick')
            s:beginCapture('axis','move_x');router.gamepadaxis({},'rightx',.9)
            assert(B.new(fs).axes.move_x=='rightx')
            assert(#callbacks==0 and fallback==0);unchanged()
        ''')

    def test_gameplay_press_release_retains_token_after_remap(self):
        self.wrap()
        self.lua.execute('''
            assert(bindings:assign('key','interact','z'));router.keypressed('e');assert(#callbacks==0)
            router.keypressed('z');assert(callbacks[1].args[1]=='e')
            bindings:assign('key','interact','k');router.keyreleased('z');assert(callbacks[2].args[1]=='e')
            router.keypressed('f8');assert(callbacks[3].args[1]=='f8')
            assert(fallback==0);unchanged()
        ''')

    def test_settings_wheel_and_drag_use_device_coordinates_and_owner(self):
        self.wrap()
        self.lua.execute('''
            s:open();s.page='controls';router.wheelmoved(0,-1);assert(s.scroll==8)
            s.device='touch';router.draw();local p=s:touchLayout().joystick
            local x,y=(70+p.x*820)*2+20,(230+p.y*300)*2+10
            router.touchpressed('owner',x,y);assert(s.drag=='joystick')
            router.touchpressed('other',x,y);router.touchmoved('other',1700,900)
            assert(p.x<.5);router.touchmoved('owner',1700,900)
            router.touchreleased('owner');assert(not s.drag and layoutApplies==1 and not s.layoutDirty)
            assert(#callbacks==0 and fallback==0);unchanged()
        ''')

    def test_save_barrier_retains_original_draw_and_key_priority(self):
        self.wrap()
        self.lua.execute('''
            s:open();s:beginCapture('key','inventory');checkpoint=true
            router.draw();router.keypressed('z')
            assert(fallback==2 and bindings:isCapturing() and bindings.keyboard.inventory=='i')
            assert(#callbacks==0 and panelDraws==0);unchanged()
        ''')

    def test_focus_loss_cancels_capture_and_neutralizes_held_settings_input(self):
        self.wrap()
        self.lua.execute('''
            s:open();s:beginCapture('key','interact');s.pressedKeys.z='e'
            router.focus(false);assert(not bindings:isCapturing() and next(s.pressedKeys)==nil)
            assert(controller.focused==false and neutral>0 and fallback==0);unchanged()
        ''')


if __name__ == '__main__':
    unittest.main()
