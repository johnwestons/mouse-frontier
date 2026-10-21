"""Guest ownership, input isolation, scene readiness and read-only world views."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestViewTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Wire=require('game.net.movement'); View=require('game.coop_guest_view'); Camera=require('game.camera'); P=require('game.net.protocol')
            data=F.campaign(); assert(F.enroll(data)); data.scene='train'
            data.players.companion.playerX=330; data.players.companion.playerY=400
            controls={}; messages={}; prepared=0; released=0; padX=0; padY=0; padSprint=false
            mobile={enabled=false,cancelAll=function(self) self.x=0; self.y=0 end,
                movement=function(self) return self.x or 0,self.y or 0 end,isSprinting=function() return false end}
            bindingFS=F.filesystem(); bindings=require('game.control_bindings').new(bindingFS)
            bindings.movement=function() return padX,padY end
            bindings.actionDown=function() return padSprint end
            controller={menuOpen=false,replica={data=data,revision=1},network={
                sceneReady=function(_,epoch,motionId) messages[#messages+1]={ready=epoch,motionId=motionId}; return true end,
                sendMovement=function(_,seq,epoch,x,y,sprint,motionId)
                    messages[#messages+1]={sequence=seq,epoch=epoch,x=x,y=y,sprint=sprint,motionId=motionId}; return true
                end}}
            context={ui={propImages={},atlasItems={}},content={},catalog={},colors={},car={},
                move=function(_,_,_,_,x,y) return x,y end,
                bindings=bindings,
                mobileEnabled=function() return false end,mobileFactory={new=function(options) mobile.options=options; return mobile end},
                keyDown=function(...) for _,key in ipairs({...}) do if controls[key] then return true end end; return false end,
                sceneFactory={new=function(c) return {prepare=function() prepared=prepared+1; return true end,
                    release=function() released=released+1 end} end},
                createWorldRenderer=function() return {release=function() released=released+1 end} end}
            view=View.new(context,controller)
            function controller:open() self.menuOpen=true; view:neutralize() end
            function frame(serial,paused,epoch)
                return P.message('motion',{sessionId='guest-test',motionId=epoch or data.coop.sceneEpoch,serial=serial,sceneEpoch=epoch or data.coop.sceneEpoch,
                    paused=paused==true,ready=true,tick=serial,ack=0,ackAge=0,inputActive=false,
                    host=Wire.packActor({x=200,y=250},data.players.host),
                    companion=Wire.packActor({x=350,y=400},data.players.companion)})
            end
            function ready() assert(view:update(.05)); controller.motionFrame=frame(1); assert(view:update(.05)) end
        ''')

    def test_touch_attack_uses_existing_controls_with_or_without_nearby_interaction(self):
        self.lua.execute('''
            ready(); mobile.enabled=true
            view.runtime.scene='stop'; view.runtime.saveData.scene='stop'; view.runtime.saveData.location=2
            local nearby=false; view.interactionAvailable=function() return nearby end
            view.actionLabel=function() return 'TALK' end
            assert(mobile.options.gameplayActive())
            local key,label=mobile.options.primaryAction(); assert(key=='space' and label=='ATTACK')
            assert(mobile.options.secondaryAction()==nil)
            nearby=true; key,label=mobile.options.primaryAction(); assert(key=='e' and label=='TALK')
            key,label=mobile.options.secondaryAction(); assert(key=='space' and label=='ATTACK')
            local attacked=false; view.field.attack=function() attacked=true end
            mobile.options.pressKey(key); assert(attacked)
            view.ui.actionMenuVisible=true; assert(not mobile.options.menuVisible())
            view.ui.actionMenuVisible=false; assert(mobile.options.menuVisible())
            view.runtime.scene='house'; view.runtime.saveData.scene='house'; nearby=false
            assert(not mobile.options.gameplayActive() and mobile.options.secondaryAction()==nil)
        ''')

    def test_scenery_inspection_routes_guest_input_and_blocks_movement(self):
        self.lua.execute('''
            ready()
            local data=view.runtime.saveData
            data.scene='stop';data.location=42;view.runtime.scene='stop'
            local spot=require('game.stop_hotspots').definitions(42)[1]
            view.runtime.player.x,view.runtime.player.y=spot.x,spot.y
            assert(view:interactionAvailable() and view:actionLabel()=='INSPECT')
            view:keypressed('e')
            assert(view.inspection.opened and not view:inputAllowed())
            local scope,panel=view:controllerScope();assert(scope=='menu' and panel==view.inspection)
            view:keypressed('i');assert(not view.runtime.inventoryOpen)
            view:wheelmoved(0,1);assert(view.camera.zoom==1)
            view:keypressed('escape');assert(not view.inspection.opened and view:inputAllowed())
            view:interact();assert(view.inspection.opened)
            view.epoch=view.epoch+1;view.inspection:update();assert(not view.inspection.opened)
        ''')

    def test_home_conductor_is_visible_and_has_no_generic_companion_conversation(self):
        self.lua.execute('''
            local Home=require('game.home_stop')
            data.scene='stop'; data.location=1; data.homeStop=Home.newState()
            data.homeStop.inOffice=true
            require('game.scene_npcs').prepare(data,{})
            ready()
            assert(view.runtime.npcActor and view.runtime.saveData.currentNPC==Home.npc)
            assert(view.runtime.npcActor.x==Home.points.conductor.x)
            assert(view.runtime.npcActor.y==Home.points.conductor.y)
            assert(not view.people:nearest() and not view.people:open({}))
            assert(data.npcStates['stop:1']==nil)
        ''')

    def test_render_state_is_detached_unsavable_and_scoped_to_guest(self):
        self.lua.execute('''
            ready(); local own=view.runtime.saveData
            assert(own~=data and own.inventory==own.players.companion.inventory)
            assert(require('game.replica_ownership').isReplica(require('game.coop_players').campaignOf(own)))
            own.inventory[1]='presentation-only'; own.resources.food=999
            assert(data.resources.food==10 and data.players.companion.inventory[1]~='presentation-only')
            assert(view.runtime.player.x==350 and view.remote.x==200 and data.players.companion.playerX==330)
            assert(view.ui.coopCompanion()==view.remote)
            view.camera:setZoom(2); assert(Camera.zoom==1)
            view:release(); assert(released==2 and not view.ready)
        ''')

    def test_battle_touch_uses_mobile_menu_and_canvas_routes_without_world_interaction(self):
        self.lua.execute('''
            ready(); view.runtime.battle={}; view.runtime.state='battle'; view.paused=true
            package.loaded['game.viewport'].toGame=function(x,y) return x,y end
            local pointer=0; local touch=0
            view.battles.pointer=function(_,x,y) pointer=pointer+1; assert(x==30 and y==40); return true end
            mobile.touchpressed=function(_,id,x,y) touch=touch+1; mobile.options.pressPointer(x,y) end
            view:touchpressed('battle',30,40); assert(touch==1 and pointer==1)
            local fx,fy=view:focusPoint(); assert(fx==480 and fy==250)
            assert(not mobile.options.backpackVisible() and mobile.options.menuVisible())
            mobile.options.menuAction(); assert(controller.menuOpen)
            controller.menuOpen=false; view.runtime.inventoryOpen=true; assert(not mobile.options.menuVisible())
        ''')

    def test_pending_field_or_expedition_receipt_prevents_a_second_interaction(self):
        self.lua.execute('''
            ready(); view.field.pending={id=1}
            assert(view:activityBusy() and not view:inputAllowed() and not view.inventory:toggle())
            local calls=0; view.expedition.interact=function() calls=calls+1 end
            view:keypressed('e'); view:gamepadpressed(nil,'a'); assert(calls==0)
            view.field.pending=nil; view.expedition.pending={id=2}
            assert(view:activityBusy() and not view:inputAllowed() and not view.inventory:toggle())
            view:keypressed('e'); assert(calls==0)
            view.expedition.pending=nil; assert(view:inputAllowed())
        ''')

    def test_field_attack_routes_private_zoomed_aim_and_keyboard_controller_touch(self):
        self.lua.execute('''
            love={graphics={getDimensions=function() return 960,720 end}}
            local Areas=require('game.expedition_areas')
            data.location=6; data.scene='expedition'; data.activeExpeditionArea=Areas.SURFACE_ID; Areas.ensure(data)
            ready(); local requests={}
            view.field.attack=function(_,x,y) requests[#requests+1]={x=x,y=y}; return true end
            package.loaded['game.viewport'].toGame=function(x,y) return x,y end
            view.camera:setZoom(1.5); view.camera.panX=17; view.camera.panY=-9
            local ox,oy=Areas.cameraOffset(view.runtime.saveData,view.runtime.player,960,720)
            local fx,fy=view:focusPoint(); local wx,wy=380,430
            local x,y=(wx-ox-fx)*view.camera.zoom+fx+view.camera.panX,(wy-oy-fy)*view.camera.zoom+fy+view.camera.panY
            view:mousepressed(x,y,1,false)
            assert(#requests==1 and math.abs(requests[1].x-wx)<.001 and math.abs(requests[1].y-wy)<.001)
            view:keypressed('space'); view:gamepadpressed(nil,'x')
            view.ui.guestFieldAttack={x=550,y=202,w=200,h=56}; view:touchpressed('field',600,220)
            assert(#requests==4 and requests[2].x==nil and requests[3].x==nil and requests[4].x==nil)
            assert(data.players.host.playerX==200 and data.players.companion.playerX==330)
        ''')

    def test_controller_routes_battle_actions_and_local_play_menu(self):
        self.lua.execute('''
            ready(); view.runtime.battle={}; local keys={}
            view.battles.keypressed=function(_,key) if key=='escape' then controller:open() else keys[#keys+1]=key end; return true end
            view:gamepadpressed(nil,'x'); view:gamepadpressed(nil,'dpup'); view:gamepadpressed(nil,'a')
            assert(keys[1]=='h' and keys[2]=='1' and keys[3]=='space')
            view:gamepadpressed(nil,'start'); assert(controller.menuOpen and #keys==3)
        ''')

    def test_custom_world_bindings_ignore_old_defaults_and_dpad_does_not_open_stations(self):
        self.lua.execute('''
            ready();local opened=0;local stations=0;local gifts=0
            view.inventory.toggle=function() opened=opened+1 end
            view.activities.open=function() stations=stations+1 end
            view.people.open=function() gifts=gifts+1 end
            assert(bindings:assign('button','inventory','b'))
            view:gamepadpressed(nil,'y');assert(opened==0)
            view:gamepadpressed(nil,'b');view:gamepadreleased(nil,'b');assert(opened==1)
            view:gamepadpressed(nil,'dpleft');view:gamepadpressed(nil,'dpdown');assert(stations==0)
            view:gamepadpressed(nil,'rightshoulder');assert(gifts==1)
            padX=-1;view:update(.05);assert(messages[#messages].x==-1000)
        ''')

    def test_actual_visible_hud_controller_focus_selects_train_actions_and_neutralizes_movement(self):
        self.lua.execute('''
            love={keyboard={isDown=function() return false end}}
            ready();view.ui.guestMaintenance={x=20,y=146,w=168,h=56}
            local selected;view.activities.open=function(_,kind) selected=kind end
            padX=1;view:gamepadpressed(nil,'back');assert(view.controllerFocus and not view:inputAllowed())
            view:update(.05);assert(messages[#messages].x==0)
            view:gamepadpressed(nil,'a');assert(selected=='maintenance' and not view.controllerFocus)
            assert(bindings:assign('button','guest_workshop','b'));local workshop=0
            view.train.open=function() workshop=workshop+1 end
            view:gamepadpressed(nil,'b');assert(workshop==1)
        ''')

    def test_hud_controller_focus_is_discarded_when_scene_changes_or_focus_is_lost(self):
        self.lua.execute('''
            ready();view:gamepadpressed(nil,'back');assert(view.controllerFocus)
            view:focus(false);assert(not view.controllerFocus and not next(view.controllerPressed))
            view:focus(true);view:gamepadpressed(nil,'back');assert(view.controllerFocus)
            local nextData=Schema.copy(data);nextData.coop.sceneEpoch=nextData.coop.sceneEpoch+1;nextData.scene='house'
            controller.replica={data=nextData,revision=2};view:update(.05)
            assert(not view.controllerFocus and not next(view.controllerPressed))
        ''')

    def test_private_menu_remapping_and_held_release_keep_the_original_canonical_action(self):
        self.lua.execute('''
            ready();view.runtime.guestActivityOpen=true;local press,release
            view.activities.keypressed=function(_,key) press=key end
            view.activities.keyreleased=function(_,key) release=key end
            assert(bindings:assign('button','confirm','x'))
            view:gamepadpressed(nil,'a');assert(not press)
            view:gamepadpressed(nil,'x');assert(press=='return')
            assert(bindings:assign('button','confirm','y'))
            view:gamepadreleased(nil,'x');assert(release=='return')
            press=nil;view:gamepadpressed(nil,'x');assert(not press)
        ''')

    def test_tactical_custom_binding_uses_actual_attack_option_and_never_falls_back_to_old_dpad(self):
        self.lua.execute('''
            ready();view.runtime.battle={};local keys={}
            view.battles.keypressed=function(_,key) keys[#keys+1]=key end
            assert(bindings:assign('button','battle_attack_1','guide'))
            view:gamepadpressed(nil,'dpup');assert(#keys==0)
            view:gamepadpressed(nil,'guide');assert(keys[1]=='1')
            view:gamepadreleased(nil,'guide');view.epoch=view.epoch+1
            view:gamepadpressed(nil,'b');assert(keys[2]=='r') -- Denied host-only retreat is not invented as a guest action.
        ''')

    def test_shooter_buttons_translate_once_and_release_after_remap_without_replaying_a_new_action(self):
        self.lua.execute('''
            ready();local keys,releases={},{}
            view.ambush.available=function() return true end
            view.ambush.keypressed=function(_,key) keys[#keys+1]=key end
            view.ambush.keyreleased=function(_,key) releases[#releases+1]=key end
            view.ambush.gamepadpressed=function() error('second button translation') end
            assert(bindings:assign('button','ls_fire','guide'))
            view:gamepadpressed(nil,'rightshoulder');assert(#keys==0)
            view:gamepadpressed(nil,'guide');assert(keys[1]=='space')
            bindings:clear('button','ls_reload');assert(bindings:assign('button','ls_fire','x'))
            view:gamepadreleased(nil,'guide');assert(releases[1]=='space')
            view:gamepadpressed(nil,'x');view:neutralize();view:gamepadreleased(nil,'x');assert(#releases==1)
            assert(bindings:assign('button','ls_pause','guide'))
            view:gamepadpressed(nil,'start');assert(#keys==2)
            view:gamepadpressed(nil,'guide');assert(keys[3]=='p')
        ''')

    def test_last_stand_world_treatment_and_owned_position_selection_use_their_scoped_bindings(self):
        self.lua.execute('''
            ready();local keys={};local readyWindow
            local panel=view.lastStand;panel.available=function() return true end
            panel.state=function() return {mode='interior'} end
            panel.keypressed=function(_,key) keys[#keys+1]=key end
            panel.position=function(_,action) keys[#keys+1]=action end
            assert(bindings:assign('button','ls_scene_action','x'))
            view:gamepadpressed(nil,'a');assert(#keys==0)
            view:gamepadpressed(nil,'x');assert(keys[1]=='e');view:gamepadreleased(nil,'x')
            panel.aid.opened=true;panel.aid.keypressed=function(_,key) keys[#keys+1]=key end
            assert(bindings:assign('button','ls_treatment_confirm','y'))
            view:gamepadpressed(nil,'y');assert(keys[2]=='return');view:gamepadreleased(nil,'y')
            panel.aid.opened=false;panel.shooter.available=function() return true end;panel.shooter.checkedPosition=function() return false end
            panel.shooter.action=function(_,key) readyWindow=key end
            assert(bindings:assign('button','ls_position_right','x'));assert(bindings:assign('button','ls_position_ready','y'))
            view.runtime.saveData.lastStand={positionVersion=1,firingPositions={companion='tall'}}
            view:gamepadpressed(nil,'y');assert(readyWindow=='2');view:gamepadreleased(nil,'y');readyWindow=nil
            view:gamepadpressed(nil,'x');assert(panel.shooter.windowChoice=='tall' and not readyWindow)
            view:gamepadreleased(nil,'x');view:gamepadpressed(nil,'y');assert(readyWindow=='2')
        ''')

    def test_pose_controller_launcher_is_accessible_without_enabling_walking_or_story_actions(self):
        self.lua.execute('''
            ready();local opened=0;view.poses.open=function(self) self.opened=true;opened=opened+1 end
            assert(bindings:assign('button','guest_pose','b'))
            view:gamepadpressed(nil,'b');assert(opened==1 and not view:inputAllowed())
            local key;view.poses.keypressed=function(_,value) key=value end
            view:gamepadreleased(nil,'b');view:gamepadpressed(nil,'a');assert(key=='return')
        ''')

    def test_shooter_phase_and_motion_change_drop_private_controller_holds(self):
        self.lua.execute('''
            ready();local held=false;local released=0
            view.ambush.available=function() return true end
            view.ambush.keypressed=function(_,key) if key=='space' then held=true end end
            view.ambush.keyreleased=function() released=released+1;held=false end
            view.ambush.suspend=function() held=false end
            view:gamepadpressed(nil,'rightshoulder');assert(held)
            view.modalDomain='new-phase';view:update(.01)
            assert(not held and not next(view.controllerPressed))
            view:gamepadreleased(nil,'rightshoulder');assert(released==0)
        ''')

    def test_inputs_are_bounded_rate_limited_and_predict_only_disposable_actor(self):
        self.lua.execute('''
            ready(); messages={}; controls.d=true; controls.w=true; controls.lshift=true; padX=1
            assert(view:update(.001)); assert(#messages==0)
            assert(view:update(.05)); local sent=messages[1]
            assert(sent.x>0 and sent.y<0 and sent.x^2+sent.y^2<=1001500 and sent.sprint)
            assert(view.runtime.player.x>350 and data.players.companion.playerX==330)
            view:update(20); assert(#messages<=3 and messages[#messages].x==0 and not view:inputAllowed())
            controller.motionFrame=frame(2)
            controls={}; padX=0; mobile.x=-.6; mobile.y=.8; view:update(.05)
            assert(messages[#messages].x==-600 and messages[#messages].y==800)
        ''')

    def test_menu_focus_and_host_pause_stop_only_guest_input(self):
        self.lua.execute('''
            ready(); controls.d=true; view:update(.05); assert(messages[#messages].x==1000)
            controller:open(); assert(messages[#messages].x==0); view:update(.05); assert(messages[#messages].x==0)
            controller.menuOpen=false; view:update(.05); assert(messages[#messages].x==1000)
            view:focus(false); assert(messages[#messages].x==0); view:update(.05); assert(messages[#messages].x==0)
            view:focus(true); controller.motionFrame=frame(2,true); view:update(.05); assert(messages[#messages].x==0)
            controller.motionFrame=frame(3,false); view:update(.05); assert(messages[#messages].x==1000)
            assert(data.players.host.playerX==200)
        ''')

    def test_scene_epoch_waits_for_assets_and_fresh_motion_before_moving(self):
        self.lua.execute('''
            ready(); controls.d=true; view:update(.05); local seq=view.sequence
            local nextData=Schema.copy(data); nextData.coop.sceneEpoch=nextData.coop.sceneEpoch+1
            nextData.scene='house'; nextData.players.companion.playerX=700
            controller.replica={data=nextData,revision=2}; assert(view:update(.05))
            assert(prepared==3 and view.runtime.scene=='house' and view.runtime.player.x==700)
            assert(view.sequence>seq and messages[#messages].x==0 and view.paused)
            assert(not view.motionId) -- A new scene also waits for its host motion generation.
            controller.motionFrame=frame(2,false,nextData.coop.sceneEpoch); view:update(.05)
            assert(not view.paused and messages[#messages].x==1000)
            assert(messages[#messages-1].ready==nextData.coop.sceneEpoch and messages[#messages-1].motionId==2)
        ''')

    def test_same_scene_revision_does_not_rewind_actor_or_import_host_preferences(self):
        self.lua.execute('''
            local Preferences=require('game.local_preferences'); local fs=F.filesystem()
            local preferences=Preferences.new(fs); preferences.values.accessibility.reducedMotion=true
            context.preferences=preferences
            ready(); local nextData=Schema.copy(data); nextData.resources.food=14
            controller.replica={data=nextData,revision=2}; view:update(.05)
            assert(view.runtime.player.x==350 and view.runtime.saveData.resources.food==14)
            assert(require('game.accessibility').ensure(view.runtime.saveData).reducedMotion==true)
            local count=0; for _,message in ipairs(messages) do if message.ready then count=count+1 end end
            assert(count==1)
        ''')

    def test_failed_preparation_never_sends_scene_ready(self):
        self.lua.execute('''
            view.scene.prepare=function() return nil,'missing_host_layout' end
            local ok,reason=view:update(.1); assert(not ok and reason=='missing_host_layout')
            assert(not view.ready and #messages==0)
        ''')

    def test_focus_lost_during_connection_remains_neutral_after_view_creation(self):
        self.lua.execute('''
            view:release(); controller.focused=false; controls.d=true
            view=View.new(context,controller); ready()
            assert(view.ready and not view.focused and messages[#messages].x==0)
            view:focus(true); view:update(.05); assert(messages[#messages].x==1000)
        ''')

    def test_sampler_keeps_twenty_hertz_at_thirty_fps_without_bursts(self):
        self.lua.execute('''
            ready(); messages={}
            for index=1,30 do
                controller.motionFrame=frame(index+1); assert(view:update(1/30))
            end
            assert(#messages==20,#messages)
        ''')

    def test_personal_car_controls_wait_for_authority_and_ack_the_new_generation(self):
        self.lua.execute('''
            data.trainCars={'living-car','medical'}; ready()
            local oldEpoch=view.epoch; local submitted
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                submitted={name=name,car=args.car,epoch=epoch,expected=expected}; return 1
            end
            view:keypressed(']')
            assert(submitted.car==2 and submitted.name=='player.car' and submitted.epoch==oldEpoch)
            assert(submitted.expected['player:companion']==0 and view.carRequest and not view:inputAllowed())
            assert(view.runtime.saveData.activeCar==1 and data.players.companion.activeCar==1)
            local nextData=Schema.copy(data); nextData.players.companion.activeCar=2
            controller.replica={data=nextData,revision=2}
            controller.motionFrame=frame(2,true); controller.motionFrame.motionId=2
            controller.motionFrame.companion.car=2; controller.motionFrame.ready=false
            view:update(.05)
            assert(view.runtime.saveData.activeCar==2 and view.carTransition and not view.carRequest)
            local count=0
            for _,m in ipairs(messages) do if m.ready and m.motionId==2 then count=count+1 end end
            assert(count==1 and view.epoch==oldEpoch and data.players.companion.activeCar==1)
            -- A reliable state projection can lag the newer motion stream.
            controller.replica={data=Schema.copy(data),revision=3}; view:update(.05)
            assert(view.runtime.saveData.activeCar==2)
            controller.motionFrame=frame(3); controller.motionFrame.motionId=2; controller.motionFrame.companion.car=2
            for _=1,4 do controller.motionFrame.serial=controller.motionFrame.serial+1; view:update(.25) end
            assert(not view.carTransition and view:inputAllowed())
        ''')

    def test_rejected_car_request_clears_pending_without_local_car_change(self):
        self.lua.execute('''
            data.trainCars={'living-car','medical'}; ready()
            controller.network.submitCommand=function() return 3 end
            assert(view:requestCar(2)); controller.network.lastCommandResult={requestId=3,ok=false,reason='stale_revision'}
            view:update(.05)
            assert(not view.carRequest and view.actionError=='stale_revision' and view.runtime.saveData.activeCar==1)
            controller:open(); assert(not view:requestCar(2))
        ''')

    def test_backpack_captures_only_guest_input_and_scene_or_focus_cancels_drag(self):
        self.lua.execute('''
            ready(); controls.d=true; view:update(.05); local original=data.players.host.playerX
            view:keypressed('i'); assert(view.runtime.inventoryOpen and not view:inputAllowed() and view:actionsAllowed())
            view:update(.05); assert(messages[#messages].x==0 and data.players.host.playerX==original)
            view.runtime.draggedSlot={kind='equipment',index=1}; view.inventory:remember(); view:focus(false)
            assert(not view.runtime.draggedSlot and not view.inventory.selection)
            view:focus(true); view.runtime.draggedSlot={kind='equipment',index=1}; view.inventory:remember()
            local nextData=Schema.copy(data); nextData.coop.sceneEpoch=nextData.coop.sceneEpoch+1
            controller.replica={data=nextData,revision=2}; view:update(.05)
            assert(not view.runtime.inventoryOpen and not view.runtime.draggedSlot and not view.inventory.selection)
        ''')


class SceneViewTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema'); data=F.campaign(8)
            assert(F.enroll(data)); data.scene='stop'; data.currentNPC='test'
            runtime={saveData=require('game.coop_players').forActor(data,'companion'),scene='stop',animationClock=0,player={x=300,y=400}}
            function identical(a,b)
                if type(a)~=type(b) then return false end
                if type(a)~='table' then return a==b end
                for k,v in pairs(a) do if not identical(v,b[k]) then return false end end
                for k in pairs(b) do if a[k]==nil then return false end end
                return true
            end
            function image() return {getDimensions=function() return 512,512 end,getWidth=function() return 512 end,
                getHeight=function() return 512 end,setFilter=function() end,release=function(self) assert(not self.released); self.released=true end} end
            draws=0; love={graphics=setmetatable({newImage=image,newQuad=function() return {} end},
                {__index=function(_,key) return function() if key=='draw' then draws=draws+1 end end end})}
            content={scenery={stopWildlife={},crowCaravanAssets={crowBanner=image()}},mobImages={['sludge-crawler.png']=image()}}
            package.loaded['game.expedition_sprites']={load=function()
                local frames={walkFrames={image(),image()}}
                for i=1,6 do frames[i]=image() end; return frames
            end}
            scene=require('game.coop_scene_view').new({runtime=runtime,ui={playSfx=function() end},content=content,catalog=require('game.catalog')})
        ''')

    def test_stop_draw_does_not_spawn_wildlife_sludges_caravans_or_mail(self):
        self.lua.execute('''
            data.stopLayouts['8']={interior=1}; data.crowCaravans={scheduledStops={8},camps={}}
            data.mailQuests={{destination=8,recipient='test',complete=false}}
            local before=Schema.copy(data)
            for _,name in ipairs({'wildlife','mice'}) do require('game.'..name).spawn=function() error('guest generated wildlife') end end
            require('game.stop_sludges').ensure=function() error('guest generated sludges') end
            require('game.crow_caravans').ensureSchedule=function() error('guest rolled caravan schedule') end
            scene.drawWildlife(scene.ensureStopLayout()); scene.drawStopSludges({}); scene.drawShootingRangeSpot(); scene.drawCaravanGate()
            assert(scene.pendingMailHere()==data.mailQuests[1] and identical(before,data))
            data.stopLayouts['8']=nil; assert(not pcall(scene.prepare)); assert(data.stopLayouts['8']==nil)
        ''')

    def test_house_and_item_visibility_use_guest_car_and_host_selected_door(self):
        self.lua.execute('''
            data.stopLayouts['8']={interior=1,houseDoors={['2']={interior=3}}}; data.activeHouseDoor=2
            runtime.scene='house'; assert(scene.prepare()); assert(scene.ensureStopLayout().interior==3)
            assert(data.stopLayouts['8'].interior==1)
            assert(scene.itemIsHere({scene='house',location=8,houseDoor=2}))
            assert(not scene.itemIsHere({scene='house',location=8,houseDoor=1}))
            runtime.scene='train'; data.players.host.activeCar=1; data.players.companion.activeCar=2
            assert(scene.itemIsHere({scene='train',carIndex=2}) and not scene.itemIsHere({scene='train',carIndex=1}))
        ''')

    def test_expedition_draw_uses_saved_state_without_awarding_gates_or_completions(self):
        self.lua.execute('''
            local Areas=require('game.expedition_areas'); Areas.ensure(data)
            local id; for candidate in pairs(data.expeditions) do id=candidate; break end
            assert(id); data.activeExpeditionArea=id; runtime.scene='expedition'; assert(scene.prepare())
            local before=Schema.copy(data)
            Areas.ensure=function() error('guest generated expedition') end
            Areas.state=function() error('guest normalized expedition') end
            Areas.updateGates=function() error('guest progressed expedition') end
            scene.drawExpedition({drawPlayer=function() end}); assert(identical(before,data))
            scene.release(); assert(not content.mobImages['sludge-crawler.png'].released)
            scene.release() -- idempotent asset ownership
        ''')

    def test_caravan_draw_never_creates_stock_or_marks_a_visit(self):
        self.lua.execute('''
            data.crowCaravans={activeCampId='test-camp',camps={['8']={id='test-camp',stop=8,seed=20,visited=false}}}
            runtime.scene='caravan'; local before=Schema.copy(data); local calls=0
            local Caravan=require('game.crow_caravan_area')
            Caravan.ensure=function() error('guest generated caravan') end
            Caravan.draw=function(session) calls=calls+1; assert(session.state==data.crowCaravans.camps['8'] and #session.actors>0) end
            assert(scene.prepare()); scene.drawCaravanRuntime({}); assert(calls==1 and identical(before,data))
        ''')

    def test_persistently_defeated_expedition_enemies_are_not_drawn_alive_on_join(self):
        self.lua.execute('''
            local Areas=require('game.expedition_areas'); Areas.ensure(data)
            local id; for candidate in pairs(data.expeditions) do id=candidate; break end
            assert(id); data.activeExpeditionArea=id; runtime.scene='expedition'
            for _,mob in pairs(data.expeditions[id].mobs) do mob.dead=true end
            local before=Schema.copy(data); assert(scene.prepare()); draws=0; local players=0
            scene.drawExpedition({drawPlayer=function() players=players+1 end})
            assert(draws==1 and players==1 and identical(before,data)) -- only the background sprite
            scene.release()
        ''')


if __name__ == '__main__':
    unittest.main()
