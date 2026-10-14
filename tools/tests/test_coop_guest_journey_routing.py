"""Production GuestView routes for private maps, journal and pose input."""
import unittest
import test_coop_guest_view_behavior as guest_view


class JourneyRoutingTests(unittest.TestCase):
    setUp = guest_view.GuestViewTests.setUp

    def ready(self):
        self.lua.execute('''
            controller.network.status='ready';controller.network.sessionId='guest-test';ready()
            package.loaded['game.viewport'].toGame=function(x,y) return x,y end
            love=love or {};love.graphics=setmetatable({getColor=function() return 1,1,1,1 end,
                getShader=function() return nil end},{__index=function() return function() end end})
            require('game.typography').drawText=function() end
            view.context.colors={cream={1,1,1},ink={0,0,0},red={1,0,0},green={0,1,0},brass={1,.8,.4},blue={0,0,1}}
            attacks=0;fuel=0
            view.field.attack=function() attacks=attacks+1 end
            view.train.fuel=function() fuel=fuel+1 end
        ''')

    def test_keyboard_map_and_journal_capture_movement_and_attack_until_closed(self):
        self.ready()
        self.lua.execute('''
            view:keypressed('m');assert(view.journey.kind=='map' and not view:inputAllowed())
            assert(not controller.menuOpen);controls.d=true
            local oldFood=data.resources.food;assert(view:update(.05))
            local input=messages[#messages];assert(input.x==0 and input.y==0)
            view:keypressed('space');assert(not view.journey.opened and attacks==0 and fuel==0)
            controls.d=nil;view:keypressed('j');assert(view.journey.kind=='journal')
            view:keypressed('f');assert(attacks==0 and fuel==0 and view.journey.opened)
            view:keypressed('escape');assert(not view.journey.opened and not controller.menuOpen)
            assert(data.resources.food==oldFood and data.coop.sceneEpoch==view.epoch)
        ''')

    def test_actual_map_and_journal_close_rectangles_route_mouse_and_touch(self):
        self.ready()
        self.lua.execute('''
            view.ui.guestMap={x=794,y=392,w=144,h=56};view.ui.guestJournal={x=794,y=454,w=144,h=56}
            view:mousepressed(840,410,1,false);assert(view.journey.kind=='map')
            view.journey:draw();local r=view.journey.controls.map
            view:mousepressed(r.x+r.w/2,r.y+r.h/2,1,false);assert(not view.journey.opened)
            view:touchpressed('journal',840,475);assert(view.journey.kind=='journal')
            view.journey:draw();r=view.journey.controls.journeyLogClose
            view:touchpressed('close',r.x+r.w/2,r.y+r.h/2);assert(not view.journey.opened)
            assert(attacks==0 and fuel==0 and not controller.menuOpen)
        ''')

    def test_controller_source_map_binding_and_hud_journal_target_use_real_overlay(self):
        self.ready()
        self.lua.execute('''
            local fs=F.filesystem();view.context.bindings=require('game.control_bindings').new(fs)
            view.context.bindings:clear('button','sprint');assert(view.context.bindings:assign('button','map','leftstick'))
            view:gamepadpressed({},'leftstick');assert(view.journey.kind=='map')
            view:gamepadreleased({},'leftstick');view:gamepadpressed({},'b');assert(not view.journey.opened)
            view:gamepadreleased({},'b');view.ui.guestJournal={x=794,y=454,w=144,h=56}
            view:controllerActionFocus('guest-actions');assert(view.controllerFocus)
            view:touchpressed('hud',840,475);assert(not view.controllerFocus and view.journey.kind=='journal')
            assert(not controller.menuOpen and not view:inputAllowed() and attacks==0)
        ''')

    def test_wheel_pointer_and_motion_during_overlay_never_pan_or_interact_with_world(self):
        self.ready()
        self.lua.execute('''
            view:keypressed('m');view.journey:draw();local wheel=0
            view.camera.wheel=function() error('map leaked camera wheel') end
            view.camera.movePan=function() error('map leaked camera pan') end
            view.field.pointer=function() error('map leaked world pointer') end
            view:wheelmoved(0,-1);view:mousemoved(700,450);view:touchmoved('map',700,450,30,20)
            view:mousepressed(-100,-100,1,false);view:touchpressed('outside',-100,-100)
            assert(view.journey.opened and attacks==0 and fuel==0)
        ''')

    def test_scene_motion_focus_or_passive_event_invalidates_overlay(self):
        self.ready()
        self.lua.execute('''
            view:keypressed('j');assert(view.journey.opened);view:focus(false);assert(not view.journey.opened)
            view:focus(true);view:keypressed('j');assert(view.journey.opened)
            view.motionId=view.motionId+1;view.journey:update();assert(not view.journey.opened)
            view.motionId=controller.motionFrame.motionId
            data.events.current={id='cold-night-shelter',phase='prompt'}
            view.runtime.saveData.events.current=data.events.current
            view:keypressed('m');assert(not view.journey.opened and not view.poses:open())
        ''')

    def test_open_read_only_map_survives_motion_hitch_without_reenabling_world_input(self):
        self.ready()
        self.lua.execute('''
            local now=view.prediction.lastFrame
            view.prediction.context.clock=function() return now end
            local campaign=assert(require('game.net.game_state').project(data)).encoded
            view:keypressed('m');view.journey:draw();assert(view.journey.opened)
            controls.d=true;now=now+.36;assert(view.prediction:stale())
            assert(view:update(.05));view.journey:draw()
            assert(view.journey.opened and view.journey.controls.map and not view:inputAllowed())
            assert(messages[#messages].x==0 and messages[#messages].y==0)
            view:keypressed('f');assert(attacks==0 and fuel==0 and view.journey.opened)
            view:keypressed('escape');assert(not view.journey.opened and not view:inputAllowed())
            view:keypressed('m');assert(not view.journey.opened)
            view:keypressed('space');assert(attacks==0 and fuel==0)
            local after=assert(require('game.net.game_state').project(data)).encoded
            for id,value in pairs(campaign) do assert(after[id]==value) end
            controls.d=nil;controller.motionFrame=frame(2);assert(view:update(.05))
            view:keypressed('j');assert(view.journey.opened)
            data.scene='stop';data.coop.sceneEpoch=data.coop.sceneEpoch+1
            controller.replica.revision=controller.replica.revision+1
            assert(view:update(.05));assert(not view.journey.opened)
        ''')

    def test_open_read_only_map_survives_replacement_baseline_until_new_scene_is_applied(self):
        self.ready()
        self.lua.execute('''
            view:keypressed('m');view.journey:draw();assert(view.journey.opened)
            controller.network.snapshot=controller.replica.data
            for _,status in ipairs({'snapshot','acknowledging','ready'}) do
                controller.network.status=status;assert(view:update(.05));view.journey:draw()
                assert(view.journey.opened and view.journey.controls.map and not view:inputAllowed())
                view:keypressed('f');assert(attacks==0 and fuel==0)
            end
            controller.network.status='acknowledging'
            local before=messages[#messages].sequence
            view:keypressed('escape');assert(not view.journey.opened)
            view:keypressed('m');assert(not view.journey.opened)
            controller.network.status='ready';view:keypressed('j');assert(view.journey.opened)
            controller.network.status='acknowledging';controller.network.snapshot=nil
            assert(view:update(.05));assert(not view.journey.opened)
            controller.network.snapshot=controller.replica.data;controller.network.status='ready'
            view:keypressed('j');assert(view.journey.opened)
            controller.network.status='acknowledging';controller.network.closed=true
            assert(view:update(.05));assert(not view.journey.opened and attacks==0 and fuel==0)
        ''')

    def test_workshop_hud_and_controller_target_disappear_outside_train(self):
        self.ready()
        self.lua.execute('''
            local noop=function() end
            package.loaded['game.viewport'].transform=function() return 0,0,1,1 end
            view.focusPoint=function() return 480,360,{x=0,y=0,scale=1} end
            view.renderer=setmetatable({}, {__index=function() return noop end})
            view.mobile.draw=noop;view.field.draw=noop;view.train.nearFire=function() return false end
            view.trade.nearest=function() return nil end;view.inventory.nearest=function() return nil end
            view.people.nearest=function() return nil end;view.objects.nearestRadio=function() return nil end
            view.range.nearest=function() return nil end;view.activities.eligible=function() return false end
            view.activities.firstAid.nearest=function() return nil end
            for _,mobile in ipairs({false,true}) do
                view.mobile.enabled=mobile;view.runtime.scene='train';view:draw()
                assert(view.ui.guestWorkshop,'train workshop not offered')
                local has=false;for _,target in ipairs(view:controllerTargets())do if target.id=='workshop' then has=true end end
                assert(has)
                for _,scene in ipairs({'stop','house','expedition','caravan'})do
                    view.runtime.scene=scene;view:draw();assert(not view.ui.guestWorkshop,'off-train workshop still drawn')
                    for _,target in ipairs(view:controllerTargets())do assert(target.id~='workshop')end
                end
            end
        ''')

    def test_pose_input_guard_uses_actual_panel_and_retains_checked_facing(self):
        self.ready()
        self.lua.execute('''
            controller.network.submitCommand=function(_,name,args) command={name=name,args=args};return 7 end
            view.ui.guestPose={x=794,y=330,w=144,h=56}
            view:touchpressed('poses',830,350);assert(view.poses.opened and not view:inputAllowed())
            local f=frame(2);f.ack=view.sequence;controller.motionFrame=f;assert(view:update(.01))
            view:keypressed('2');assert(command.name=='player.pose' and command.args.pose=='sit')
            assert(attacks==0 and fuel==0)
        ''')


if __name__ == '__main__':
    unittest.main()
