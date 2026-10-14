"""Actual application event ordering must host before an offline world tick."""
import unittest
import test_coop_local_play_behavior as local_play


class HostingEntryWrapperTests(unittest.TestCase):
    setUp = local_play.LocalPlayWrapperTests.setUp

    def entry(self, name, state='game'):
        # Wrap a new application so each test exercises the real outer adapter.
        self.lua.globals().callbackName=name
        self.lua.globals().enteredState=state
        self.lua.execute('''
            modal=false; runtime.state='slots'; controller.hostingIntent='selecting'
            controller.finishHostingEntry=function(self)
                assert(runtime.state==enteredState); assert(#log==1 and log[1]=='entry')
                log[#log+1]='host'; self.hostingIntent=nil
            end
            originalApp={}; for _,key in ipairs({'update','draw','keypressed','textinput','mousepressed',
                'touchpressed','touchreleased','touchmoved','mousereleased','gamepadpressed','mousemoved',
                'wheelmoved','keyreleased','gamepadreleased','gamepadaxis','focus','quit'}) do
                originalApp[key]=function() end
            end
            originalApp[callbackName]=function() log[#log+1]='entry'; runtime.state=enteredState; return 'forwarded' end
            originalApp.update=function() log[#log+1]='world' end
            wrapped=require('game.local_play_host').wrap(originalApp,{controller=controller,ui=ui,runtime=runtime,
                commands={checkpointStatus=function() return {pending=pending} end},
                screenToGame=function(x,y) return x,y end,bindings={isCapturing=function() return false end},
                idleUpdate=function() log[#log+1]='idle' end})
        ''')

    def test_key_slot_entry_hosts_synchronously_before_world_update(self):
        self.entry('keypressed')
        self.lua.execute("assert(wrapped.keypressed('return')=='forwarded'); assert(table.concat(log,',')=='entry,host')")

    def test_mouse_and_touch_slots_use_same_immediate_host_boundary(self):
        self.entry('mousepressed')
        self.lua.execute("assert(wrapped.mousepressed(200,200,1,false)=='forwarded'); assert(table.concat(log,',')=='entry,host')")
        self.lua.execute('log={}')
        self.entry('touchpressed')
        self.lua.execute("assert(wrapped.touchpressed('slot',200,200)=='forwarded'); assert(table.concat(log,',')=='entry,host')")

    def test_controller_battle_slot_entry_preserves_original_result(self):
        self.entry('gamepadpressed','battle')
        self.lua.execute("assert(wrapped.gamepadpressed({},'a')=='forwarded'); assert(table.concat(log,',')=='entry,host')")

    def test_mobile_slot_activation_on_release_hosts_before_next_world_tick(self):
        self.entry('touchreleased')
        self.lua.execute('''
            wrapped.touchpressed('slot',200,200)
            assert(runtime.state=='slots' and controller.hostingIntent=='selecting' and #log==0)
            assert(wrapped.touchreleased('slot',200,200)=='forwarded')
            assert(table.concat(log,',')=='entry,host')
        ''')

    def test_mouse_release_activation_uses_same_host_boundary(self):
        self.entry('mousereleased')
        self.lua.execute('''
            wrapped.mousepressed(200,200,1,false)
            assert(runtime.state=='slots' and controller.hostingIntent=='selecting' and #log==0)
            assert(wrapped.mousereleased(200,200,1,false)=='forwarded')
            assert(table.concat(log,',')=='entry,host')
        ''')

    def test_invalid_slot_or_character_selection_cannot_start_host(self):
        self.entry('keypressed','characters')
        self.lua.execute("wrapped.keypressed('return'); assert(table.concat(log,',')=='entry' and controller.hostingIntent=='selecting')")

    def test_failed_hosting_blocks_world_even_when_shared_host_menu_exception_applies(self):
        self.lua.execute('''
            runtime.session={networkMode='host'}; controller.hostingIntent='failed'; modal=true
            app.update(.1); assert(table.concat(log,',')=='network,idle'); log={}
            pending=true; app.update(.1); assert(table.concat(log,',')=='network,update')
        ''')


if __name__=='__main__':
    unittest.main()
