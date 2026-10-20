"""Farmhouse pose ownership, motion barriers, geometry and guest routing."""
import unittest
import test_coop_last_stand_progression_behavior as progression
import test_coop_guest_view_behavior as views


class LastStandMovementTests(unittest.TestCase):
    setUp = progression.LastStandProgressionTests.setUp
    stand = progression.LastStandProgressionTests.stand

    def walking(self):
        self.stand()
        self.lua.execute('''
            enter(); Geometry=require('game.last_stand_geometry'); Wire=require('game.net.movement'); P=require('game.net.protocol')
            clock=0; paused=false; ordinaryX=guest.playerX; ordinaryY=guest.playerY
            local context={campaign=data,clock=function() return clock end,
                domain=function() return Life.key(data) end,
                position=function(id) local p=Life.pose(data,id); return p and {playerX=p.x,playerY=p.y,playerFacing=p.facing} or data.players[id] end,
                hostActor=function() return Life.pose(data,'host') end,
                allowed=function() return not paused and Life.walking(data) end,
                store=function(actor) local p=Life.pose(data,'companion'); p.x,p.y,p.facing=actor.x,actor.y,actor.facing end,
                move=function(_,_,ox,oy,x,y) return Geometry.move(quest.lifecycle.mode,ox,oy,x,y) end}
            sim=require('game.coop_movement').host(context); sim:admit(7)
            function input(seq,x,y,sprint)
                return P.message('movement',{sessionId='farm',sceneEpoch=data.coop.sceneEpoch,motionId=sim.motionId,
                    sequence=seq,x=x or 0,y=y or -1000,sprint=sprint==true})
            end
            function tick() clock=clock+Wire.STEP; assert(sim:update()) end
            function ready() assert(sim:ready(7,data.coop.sceneEpoch,sim.motionId)) end
        ''')

    def test_movement_changes_only_companion_modal_pose_and_keeps_ordinary_position(self):
        self.walking()
        self.lua.execute('''
            ready(); local hp=quest.lifecycle.positions.host; local hx,hy=hp.x,hp.y
            for i=1,15 do assert(sim:receive(7,input(i))); tick() end
            local p=quest.lifecycle.positions.companion
            assert(p.y<590 and p.y>450 and p.x==505 and hp.x==hx and hp.y==hy)
            assert(guest.playerX==ordinaryX and guest.playerY==ordinaryY and sim.actor.animationDistance>0)
            local frame=assert(sim:snapshot('farm')); assert(Wire.snapshot(frame) and frame.domain==Life.key(data))
            assert(frame.companion.y==math.floor(p.y*1000+.5) and Schema.validate(data))
        ''')

    def test_modal_revision_discards_old_direction_and_requires_fresh_ready(self):
        self.walking()
        self.lua.execute('''
            ready(); assert(sim:receive(7,input(1))); tick(); local old=input(2); local oldId=sim.motionId
            local epoch=data.coop.sceneEpoch; assert(Life.move(quest,'backyard')); Life.ensure(data); tick()
            assert(sim.motionId==oldId+1 and not sim.readyEpoch and not sim.input and not sim.simInput)
            assert(not sim:receive(7,old) and not sim:ready(7,epoch,oldId))
            assert(sim.actor.x==505 and sim.actor.y==610 and data.coop.sceneEpoch==epoch)
            ready(); assert(sim:receive(7,input(2))); tick(); assert(sim.actor.y<610 and Schema.validate(data))
        ''')

    def test_stale_input_and_private_guest_pause_stop_movement_without_story_change(self):
        self.walking()
        self.lua.execute('''
            ready(); assert(sim:receive(7,input(1))); tick(); local rev=quest.lifecycle.revision
            clock=clock+.5; assert(sim:update()); local y=sim.actor.y; tick(); assert(sim.actor.y==y and not sim.input)
            paused=true; assert(sim:receive(7,input(2))); tick(); assert(sim.actor.y==y)
            assert(quest.lifecycle.revision==rev and quest.state=='interior' and Schema.validate(data))
        ''')

    def test_collision_sweeps_furniture_and_rejects_closed_corridor(self):
        self.walking()
        self.lua.execute('''
            local x,y=Geometry.move('interior',400,400,100,400); assert(x>=340 and y==400)
            x,y=Geometry.move('backyard',480,580,700,580); assert(x<=590 and y==580)
            assert(not Geometry.walkable('interior',200,400) and not Geometry.walkable('backyard',600,450))
            assert(not Geometry.walkable('interior',0/0,400))
        ''')

    def test_runtime_binding_saves_only_position_and_facing_and_not_gait(self):
        self.walking()
        self.lua.execute('''
            local player={x=400,y=320,facing=-1}; assert(Life.bind(player,data,'host',true))
            player.x=450; player.y=350; player.facing=1; player.animationDistance=30; player.velocityX=18
            assert(quest.lifecycle.positions.host.x==450 and quest.lifecycle.positions.host.y==350)
            assert(not quest.lifecycle.positions.host.animationDistance and not quest.lifecycle.positions.host.velocityX)
            local copy=assert(Schema.copy(data)); assert(Schema.validate(copy) and not getmetatable(copy.lastStand.lifecycle.positions.host))
        ''')

    def test_marked_pose_rejects_wrong_owner_aliases_unknown_fields_and_obstacles(self):
        self.walking()
        self.lua.execute('''
            for _,change in ipairs({function(r) r.positions.other={x=480,y=590,facing=1} end,
                function(r) r.positions.companion=r.positions.host end,
                function(r) r.positions.host.velocityX=9 end,
                function(r) r.positions.host.x=200; r.positions.host.y=400 end,
                function(r) r.positions.host.facing=0 end,
                function(r) r.positions=nil end}) do
                local broken=assert(Schema.copy(data)); change(broken.lastStand.lifecycle)
                assert(not Schema.validate(broken) and not Schema.migrate(broken))
            end
        ''')

    def test_version_one_lifecycle_migrates_without_changing_identity_or_phase(self):
        self.walking()
        self.lua.execute('''
            local old=assert(Schema.copy(data)); old.version=40
            old.lastStand.lifecycle.version=1; old.lastStand.lifecycle.positions=nil
            local identity,rev=old.lastStand.lifecycle.entityId,old.lastStand.lifecycle.revision
            local loaded=assert(Schema.migrate(old)); local record=loaded.lastStand.lifecycle
            assert(record.version==2 and record.entityId==identity and record.revision==rev and loaded.version==Schema.CURRENT_VERSION)
            assert(record.positions.host.y==590 and record.positions.companion.x==505 and Schema.validate(loaded))
        ''')

    def test_outdoor_commands_cannot_use_farmhouse_coordinates(self):
        self.walking()
        self.lua.execute('''
            for _,name in ipairs({'loot.pickup','storage.transfer','npc.gift','quest.deliver','merchant.buy','scene.returnTrain'}) do
                local r=run('host',name,{}); assert(r.reason=='modal_scene',name..':'..tostring(r.reason))
            end
            assert(run('companion','scene.returnTrain',{}).reason=='host_only')
            assert(sim:relocate(690,515)==false and guest.playerX==ordinaryX)
        ''')

    def test_reconnect_preserves_saved_modal_position_without_moving_host(self):
        self.walking()
        self.lua.execute('''
            ready(); assert(sim:receive(7,input(1))); tick(); local p=quest.lifecycle.positions.companion
            local x,y=p.x,p.y; local hostY=quest.lifecycle.positions.host.y; sim:disconnect(7); sim:admit(8)
            assert(sim.actor.x==x and sim.actor.y==y and not sim.readyEpoch and not sim.input)
            assert(not sim:receive(7,input(2)) and quest.lifecycle.positions.host.y==hostY)
            local loaded=assert(Schema.migrate(assert(Schema.copy(data)))); assert(loaded.lastStand.lifecycle.positions.companion.y==y)
        ''')


class LastStandGuestMotionTests(unittest.TestCase):
    setUp = views.GuestViewTests.setUp

    def farm(self):
        self.lua.execute('''
            Life=require('game.coop_last_stand_lifecycle'); data.scene='stop'; data.location=12
            context.catalog=require('game.catalog')
            data.lastStand={state='interior',originStop=12}; Life.ensure(data)
            context.move=function(d,_,ox,oy,x,y) return require('game.last_stand_geometry').move(d.lastStand.lifecycle.mode,ox,oy,x,y) end
            controller.replica.revision=2
            function modalFrame(serial,id)
                local f=frame(serial); f.domain=Life.key(data); f.motionId=id or 2
                local own,other=data.players.companion,data.players.host
                f.companion=Wire.packActor(Life.pose(data,'companion') or {x=own.playerX,y=own.playerY},own)
                f.host=Wire.packActor(Life.pose(data,'host') or {x=other.playerX,y=other.playerY},other); return f
            end
            controller.motionFrame=modalFrame(1); assert(view:update(.05))
        ''')

    def test_actual_guest_view_routes_modal_keyboard_without_host_progression(self):
        self.farm()
        self.lua.execute('''
            assert(view.lastStand:available() and view.lastStand.scene and view:inputAllowed())
            local rev=data.lastStand.lifecycle.revision; local before=Schema.copy(data)
            view:keypressed('e'); view:keypressed('return'); assert(view.lastStand.notice=='The host controls scene progression.')
            assert(data.lastStand.lifecycle.revision==rev and data.lastStand.state=='interior')
            assert(not view:interactionAvailable() and not mobile.options.backpackVisible())
            controls.w=true; assert(view:update(.1)); assert(messages[#messages].y<0)
            assert(data.lastStand.lifecycle.positions.companion.y==before.lastStand.lifecycle.positions.companion.y)
        ''')

    def test_modal_transition_waits_for_matching_frame_and_new_motion_generation(self):
        self.farm()
        self.lua.execute('''
            local old=controller.motionFrame; assert(Life.move(data.lastStand,'backyard')); Life.ensure(data)
            controller.replica.revision=3; controls.w=true; assert(view:update(.05))
            assert(view.paused and view.motionId==nil and not view:inputAllowed())
            assert(view.runtime.player.y==610 and view.lastStand.scene.mode=='backyard')
            controller.motionFrame=modalFrame(2,3); assert(view:update(.05)); assert(view.motionId==3 and view:inputAllowed())
            assert(messages[#messages].motionId==3 and old.domain~=Life.key(data))
        ''')

    def test_guest_pause_is_private_and_controller_movement_uses_the_same_intent(self):
        self.farm()
        self.lua.execute('''
            padY=-1; assert(view:update(.1)); assert(messages[#messages].y==-1000)
            view:gamepadpressed(nil,'start'); assert(view.lastStand.paused and not view:inputAllowed())
            assert(data.lastStand.state=='interior' and data.lastStand.lifecycle.positions.companion.y==590)
            view:gamepadpressed(nil,'start'); assert(not view.lastStand.paused and view:inputAllowed())
        ''')

    def test_waiting_modal_modes_block_ordinary_world_input(self):
        self.farm()
        self.lua.execute('''
            for index,mode in ipairs({'escort','shootout','aftermath','returning'}) do
                assert(Life.move(data.lastStand,mode)); Life.ensure(data); controller.replica.revision=3+index
                controller.motionFrame=modalFrame(2+index,2+index); assert(view:update(.05))
                assert(view.lastStand:available() and not view:inputAllowed() and not view:interactionAvailable())
                view:keypressed('e'); assert(not view.runtime.inventoryOpen)
            end
        ''')

    def test_farmhouse_does_not_prepare_the_outdoor_stop_scene(self):
        self.farm()
        self.lua.execute('''
            assert(prepared==0)
            view.scene.prepare=function() error('outdoor preparation in a farmhouse') end
            assert(Life.move(data.lastStand,'backyard')); Life.ensure(data); controller.replica.revision=3
            controller.motionFrame=modalFrame(2,3); assert(view:update(.05))
            assert(view.lastStand.scene.mode=='backyard' and view:inputAllowed())
        ''')

    def test_click_destination_sends_intent_and_keyboard_override_cancels_it(self):
        self.farm()
        self.lua.execute('''
            require('game.world_view').configure({width=960,height=720,getScene=function() return 'lastStand' end})
            view.lastStand:pointer(505,470,1); assert(view.lastStand.destination)
            assert(view:update(.05)); assert(messages[#messages].y==-1000)
            assert(data.lastStand.lifecycle.positions.companion.y==590)
            controls.d=true; assert(view:update(.05)); assert(view.lastStand.destination==nil and messages[#messages].x==1000)
        ''')

    def test_touch_axes_use_motion_intent_without_an_outdoor_action(self):
        self.farm()
        self.lua.execute('''
            mobile.x=0; mobile.y=-1; assert(view:update(.1)); assert(messages[#messages].y==-1000)
            assert(not mobile.options.gameplayActive() and not mobile.options.cameraGesturesActive())
            assert(view.lastStand:pointer(116,600,1,true)==false and not view.lastStand.destination)
        ''')


if __name__ == '__main__':
    unittest.main()
