"""Production host polling and ambush controls use persisted physical bindings.

No native renderer is involved. Ambush shots/reloads use actual command
authority, owned weapons, ammunition and original cooldown updates.
"""
import unittest
import test_coop_last_stand_source_behavior as last_stand
import test_coop_guns_behavior as guns


class LastStandControllerRemapTests(unittest.TestCase):
    setUp = last_stand.LastStandSourceTests.setUp

    def controls(self):
        self.lua.execute('''
            bindings=require('game.control_bindings').new(F.filesystem())
            context.controlBindings=bindings; Source=require('game.last_stand_quest').new(context)
            buttons={}; presses={}; releases={}
            love.joystick={getJoysticks=function() return {{isGamepad=function() return true end,
                isGamepadDown=function(_,button) return buttons[button]==true end,
                getGamepadAxis=function() return 0 end}} end}
            Source.keypressed=function(_,key) presses[#presses+1]=key;return true end
            Source.keyreleased=function(_,key) releases[#releases+1]=key;return true end
        ''')

    def test_every_assignable_button_is_polled_once_per_edge(self):
        self.controls()
        self.lua.execute('''
            for _,button in ipairs({'a','b','x','y','start','back','guide','leftshoulder','rightshoulder',
                'leftstick','rightstick','dpup','dpdown','dpleft','dpright'}) do
                for _,entry in ipairs(bindings:buttonActions()) do bindings.buttons[entry.id]=nil end
                assert(bindings:assign('button','ls_reload',button)); local count=#presses
                buttons[button]=true;sourceTick(.01);sourceTick(.01)
                assert(#presses==count+1 and presses[#presses]=='r',button..' did not reach Source reload')
                buttons[button]=false;sourceTick(.01);assert(releases[#releases]=='r')
            end
        ''')

    def test_release_uses_pressed_token_after_binding_change_and_cannot_cross_scope(self):
        self.controls()
        self.lua.execute('''
            assert(bindings:assign('button','ls_fire','guide'))
            buttons.guide=true;sourceTick(.01);assert(presses[1]=='space')
            assert(bindings:assign('button','ls_fire','dpup'))
            assert(bindings:assign('button','ls_reload','guide'))
            buttons.guide=false;sourceTick(.01);assert(releases[1]=='space' and #presses==1)
            buttons.guide=true;sourceTick(.01);assert(presses[2]=='r')
            runtime.lastStand.treatment={};buttons.guide=false;sourceTick(.01)
            assert(#releases==1,'shootout release leaked into treatment scope')
        ''')

    def test_menu_neutralization_does_not_replay_old_fire_release(self):
        self.controls()
        self.lua.execute('''
            assert(bindings:assign('button','ls_fire','guide'))
            buttons.guide=true;sourceTick(.01);assert(presses[1]=='space')
            privatePaused=true;sourceTick(.01);buttons.guide=false
            privatePaused=false;sourceTick(.01);assert(#releases==0 and #presses==1)
        ''')


class AmbushControllerRemapTests(unittest.TestCase):
    setUp = guns.AmbushCommandTests.setUp
    ambush = guns.AmbushCommandTests.ambush

    def source(self):
        self.ambush()
        self.lua.execute('''
            require('game.coop_ambush_progression').install(service,ctx)
            Items.write(host,nil,{kind='equipment',index=2},'compact-carbine')
            host.ammo[Catalog.weaponCombat['compact-carbine'].ammo]=60
            convoy.weaponSession=nil;hgun=Shooting.new(host,Catalog,convoy,960,720)
            local scene=require('game.train_ambush_scene');scene.pointOpen=ctx.ambushOpen;scene.target=ctx.ambushTarget
            bindings=require('game.control_bindings').new(F.filesystem())
            runtime={state='game',saveData=data,session={networkMode='host'}}
            calls={};menuPaused=false
            input=require('game.train_ambush').new({runtime=runtime,catalog=Catalog,width=960,height=720,
                controlBindings=bindings,writeSave=function() end,enterStop=function() error('direct progression') end,
                participants=function() return {'host','companion'} end,inputPaused=function() return menuPaused end,
                submit=function(name,args) calls[#calls+1]=name;return service:submitLocal(name,args) end})
            ctx.ambushState=function(id) return input:commandState(id) end
            input:mousemoved(250,250,0,0,false)
            function count(name) local n=0;for _,value in ipairs(calls) do if value==name then n=n+1 end end;return n end
            function automatic()
                for _=1,3 do if convoy.weaponSession.fireMode=='auto' then return end;input:keypressed('v') end
                assert(convoy.weaponSession.fireMode=='auto')
            end
            function advance(dt) for _=1,math.ceil(dt/.1) do input:update(dt/math.ceil(dt/.1)) end end
        ''')

    def test_custom_pause_disables_old_start_and_preserves_held_edge_through_pause(self):
        self.source()
        self.lua.execute('''
            assert(bindings:assign('button','ls_pause','guide'))
            input:gamepadpressed(nil,'start');assert(not input:commandState('host').paused)
            input:gamepadpressed(nil,'guide');assert(input:commandState('host').paused)
            advance(.2);input:gamepadpressed(nil,'guide');assert(input:commandState('host').paused)
            input:gamepadreleased(nil,'guide');input:gamepadpressed(nil,'guide')
            assert(not input:commandState('host').paused)
        ''')

    def test_result_uses_custom_menu_confirmation_and_one_actual_host_progression(self):
        self.source()
        self.lua.execute('''
            assert(bindings:assign('button','confirm','guide'))
            input:keypressed('x');advance(2.2);assert(convoy.phase=='result')
            local epoch=data.coop.sceneEpoch;input:gamepadpressed(nil,'a')
            assert(data.scene=='train' and count('ambush.continue')==0)
            input:gamepadpressed(nil,'guide')
            assert(data.scene=='stop' and data.coop.sceneEpoch==epoch+1 and count('ambush.continue')==1)
            input:gamepadpressed(nil,'guide');assert(count('ambush.continue')==1)
        ''')

    def test_original_fire_release_after_remapping_spends_no_extra_round_and_preserves_keyboard_hold(self):
        self.source()
        self.lua.execute('''
            automatic();assert(bindings:assign('button','ls_fire','guide'))
            input:gamepadpressed(nil,'guide');local ammo=host.ammo[Catalog.weaponCombat['compact-carbine'].ammo]
            assert(count('gun.fire')==1)
            assert(bindings:assign('button','ls_fire','dpup'))
            assert(bindings:assign('button','ls_reload','guide'))
            input:gamepadreleased(nil,'guide');advance(.4)
            assert(count('gun.fire')==1 and host.ammo[Catalog.weaponCombat['compact-carbine'].ammo]==ammo)
            input:keypressed('space');input:gamepadpressed(nil,'dpup');input:gamepadreleased(nil,'dpup')
            local before=count('gun.fire');advance(.4);assert(count('gun.fire')>before,'controller release cleared keyboard fire')
            input:keyreleased('space');before=count('gun.fire');advance(.4);assert(count('gun.fire')==before)
        ''')

    def test_focus_menu_and_encounter_phase_neutralize_controller_fire(self):
        self.source()
        self.lua.execute('''
            automatic();assert(bindings:assign('button','ls_fire','guide'))
            for _,kind in ipairs({'menu','focus','phase'}) do
                if input:commandState('host').paused then input:keypressed('p') end
                input:gamepadpressed(nil,'guide');local before=count('gun.fire')
                if kind=='menu' then menuPaused=true;input:update(.1);menuPaused=false
                elseif kind=='focus' then input:focus(false);input:focus(true);input:keypressed('p')
                else convoy.phase='approach';input:mousemoved(250,250,0,0,false);convoy.phase='combat' end
                advance(.4);input:gamepadreleased(nil,'guide')
                assert(count('gun.fire')==before,kind..' replayed a held controller shot')
            end
            assert(Schema.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
