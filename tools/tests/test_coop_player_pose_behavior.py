"""Personal cosmetic poses use actual Authority transactions."""
import unittest
import test_coop_battles_behavior as tactical
import test_coop_local_play_behavior as local_play
import test_coop_guest_view_behavior as guest_view


class PersonalPoseTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def pose(self):
        self.lua.execute('''
            setup();Pose=require('game.coop_player_pose')
            now=10;service.clock=function() return now end
            states={host={screen='game',scene='train'},companion={screen='game',scene='train',movementReady=true,motionId=4}}
            context={actorState=function(id) return states[id] end};Pose.install(service,context)
            function submit(id,pose,extra)
                local args={pose=pose};if id=='companion' then args.motionId=states.companion.motionId end
                for key,value in pairs(extra or {}) do args[key]=value end
                return run(id,'player.pose',args)
            end
            function invariant(value)
                local copy=assert(Schema.copy(value));copy.coop.revision=0;copy.coop.revisions={}
                local function map(v)
                    if type(v)~='table' then return v end
                    local result={};for k,item in pairs(v) do result[type(k)..':'..tostring(k)]=map(item) end;return result
                end
                return assert(require('game.net.codec').encode(map(copy),
                    {maxBytes=1000000,maxDepth=20,maxEntries=100000,maxStringBytes=2048}))
            end
            original=invariant(data);originalRandom=service.randomSeed;originalWrites=writes
        ''')

    def test_both_actors_independent_noncheckpoint_and_no_owned_campaign_rng_story_changes(self):
        self.pose()
        self.lua.execute('''
            local before=service.activityState
            assert(submit('host','sit').ok);assert(submit('companion','lay').ok)
            assert(Pose.get(service,context,'host').pose=='sit' and Pose.get(service,context,'companion').pose=='lay')
            assert(service.activityState~=before and next(before.resources)==nil and before.personalPoses==nil)
            assert(next(service.activityState.resources)==nil and writes==originalWrites and not service.pendingSave)
            assert(invariant(data)==original and service.randomSeed==originalRandom and Schema.validate(data))
            assert(data.players.host.playerPose==nil and data.players.companion.playerPose==nil and data.personalPoses==nil)
            assert((data.coop.revisions['player:host'] or 0)==1 and (data.coop.revisions['player:companion'] or 0)==1)
            assert(not submit('host','idle').durable)
        ''')

    def test_exact_use_replay_does_not_restart_timer_or_allocate_serial(self):
        self.pose()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','player.pose',{pose='use',motionId=4}))
            local reply=service:execute('companion',1,request);assert(reply.ok and not reply.durable and reply.result.useMs==450)
            local revision=data.coop.revision;local serial=reply.result.serial
            now=10.2;assert(Pose.get(service,context,'companion').useMs==250)
            local replay=service:execute('companion',1,request);assert(replay.ok and replay.result.serial==serial)
            assert(data.coop.revision==revision and Pose.get(service,context,'companion').useMs==250)
            now=10.45;assert(Pose.advance(service,context));assert(Pose.get(service,context,'companion').useMs==0)
            assert(service:execute('companion',1,request).ok and Pose.get(service,context,'companion').useMs==0)
            assert(invariant(data)==original and service.randomSeed==originalRandom and writes==originalWrites)
        ''')

    def test_spoofed_actor_clock_duration_motion_and_unknown_pose_rejected_transactionally(self):
        self.pose()
        self.lua.execute('''
            for key,value in pairs({actorId='host',duration=99,clock=0,scene='train',health=999}) do
                assert(submit('companion','sit',{[key]=value}).reason=='invalid_pose')
            end
            assert(submit('companion','sit',{motionId=3}).reason=='stale_motion')
            assert(submit('host','sit',{motionId=4}).reason=='invalid_pose')
            assert(submit('companion','death').reason=='invalid_pose')
            assert(invariant(data)==original and data.coop.revision==0 and not service.activityState.personalPoses)
        ''')

    def test_ordinary_scene_health_ack_activity_modal_and_external_action_guards(self):
        self.pose()
        self.lua.execute('''
            local s=states.companion
            for _,key in ipairs({'traveling','encounterActive','activityBlocked','changingCar','actionBusy'}) do
                s[key]=true;assert(not submit('companion','sit').ok,key);s[key]=nil
            end
            s.movementReady=false;assert(submit('companion','sit').reason=='scene_not_ready');s.movementReady=true
            s.modalDomain='lastStand';assert(not submit('companion','sit').ok);s.modalDomain=nil
            s.screen='battle';assert(not submit('companion','sit').ok);s.screen='game'
            s.scene='stop';assert(not submit('companion','sit').ok);s.scene='train'
            guest.health=0;assert(not submit('companion','sit').ok);guest.health=guest.maxHealth
            data.tacticalBattle={};assert(not submit('companion','sit').ok);data.tacticalBattle=nil
            local oldAmbush=data.trainAmbush
            data.trainAmbush={active=true,phase='shootout'};assert(not submit('companion','sit').ok);data.trainAmbush=oldAmbush
            s.poseInputReady=false;assert(not submit('companion','sit').ok);s.poseInputReady=true
            s.moving=true;assert(submit('companion','lay').reason=='pose_moving');s.moving=false
            s.intentX=1;assert(submit('companion','sit').ok) -- Authored standing facing is retained.
            s.inputX=1;assert(submit('companion','sit').reason=='pose_moving');s.inputX=0
            assert(submit('companion','sit').ok and writes==originalWrites)
        ''')

    def test_private_pause_is_actor_local_and_trusted_movement_clears_stance_only(self):
        self.pose()
        self.lua.execute('''
            states.host.privatePaused=true
            assert(submit('host','sit').ok and submit('companion','lay').ok)
            states.companion.inputX=1;assert(Pose.get(service,context,'companion').pose=='idle')
            assert(Pose.advance(service,context));local serial=Pose.get(service,context,'companion').serial
            states.companion.inputX=0;assert(Pose.get(service,context,'companion').pose=='idle')
            assert(Pose.get(service,context,'host').pose=='sit')
            assert(submit('companion','use').ok);states.companion.moving=true
            now=10.1;assert(Pose.get(service,context,'companion').useMs==350)
            states.companion.privatePaused=true;assert(Pose.get(service,context,'companion').useMs==350)
            now=10.46;Pose.advance(service,context);assert(Pose.get(service,context,'companion').useMs==0)
            assert(Pose.get(service,context,'host').pose=='sit' and invariant(data)==original)
        ''')

    def test_scene_car_domain_and_motion_generation_changes_discard_old_pose(self):
        self.pose()
        self.lua.execute('''
            assert(submit('companion','sit').ok);data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(not Pose.get(service,context,'companion'));assert(Pose.advance(service,context))
            assert(submit('companion','lay').ok);states.companion.motionId=5
            assert(not Pose.get(service,context,'companion'));Pose.advance(service,context)
            assert(submit('companion','sit').ok);guest.activeCar=2
            assert(not Pose.get(service,context,'companion'));Pose.advance(service,context);guest.activeCar=1
            assert(submit('companion','sit').ok);states.companion.modalDomain='modal'
            assert(not Pose.get(service,context,'companion'));Pose.advance(service,context);states.companion.modalDomain=nil
            assert(submit('companion','sit').ok);data.scene='stop';states.companion.scene='stop'
            assert(not Pose.get(service,context,'companion'));Pose.advance(service,context)
            assert(service.activityState.personalPoses.actors.companion==nil)
        ''')

    def test_disconnect_rejoin_new_authority_and_save_barrier_never_replay_pose(self):
        self.pose()
        self.lua.execute('''
            local req=assert(service:prepareRequest('companion','player.pose',{pose='use',motionId=4}))
            assert(service:execute('companion',1,req).ok)
            service:disconnect('companion',1);assert(not Pose.get(service,context,'companion'));Pose.advance(service,context)
            service:admit('companion',2);assert(service:execute('companion',2,req).ok)
            assert(not Pose.get(service,context,'companion')) -- Cached acceptance cannot manufacture presentation.
            local req2=assert(service:prepareRequest('companion','player.pose',{pose='lay',motionId=4}))
            assert(service:execute('companion',2,req2).ok);assert(Pose.get(service,context,'companion').pose=='lay')
            service.pendingSave={session=true};assert(not Pose.get(service,context,'companion'))
            assert(not Pose.advance(service,context));assert(not service:submitLocal('player.pose',{pose='sit'}).ok)
            service.pendingSave=nil;assert(Pose.get(service,context,'companion').pose=='lay')
            assert(Pose.clear(service,'companion') and not Pose.get(service,context,'companion'))
            local restored=Authority.new({campaign=assert(Schema.copy(data)),sessionId='fresh-pose',randomSeed=service.randomSeed,clock=function() return now end})
            restored:admit('companion',1);Pose.install(restored,context)
            assert(not Pose.get(restored,context,'companion') and not restored.activityState.personalPoses)
            assert(restored:execute('companion',1,req2).reason=='wrong_session')
        ''')

    def test_failed_stale_revision_does_not_commit_ephemeral_pose_or_serial(self):
        self.pose()
        self.lua.execute('''
            local req=assert(service:prepareRequest('companion','player.pose',{pose='lay',motionId=4}))
            assert(not service.activityState.personalPoses) -- Preparation cloned transaction state.
            req.expected['player:companion']=1
            assert(service:execute('companion',1,req).reason=='stale_revision')
            assert(not service.activityState.personalPoses and not Pose.get(service,context,'companion'))
            assert(invariant(data)==original and writes==originalWrites)
            assert(submit('companion','lay').result.serial==1)
        ''')

    def test_actual_personal_car_command_invalidates_only_moving_actor_pose(self):
        self.pose()
        self.lua.execute('''
            data.trainCars={'living-car','storage'}
            require('game.coop_cars').install(service,{actorState=context.actorState,
                carArrival=function() return 300,250 end})
            assert(submit('host','sit').ok and submit('companion','lay').ok)
            local reply=run('companion','player.car',{car=2});assert(reply.ok and reply.durable,reply.reason)
            assert(saved.players.companion.activeCar==2 and data.players.host.activeCar==1)
            assert(not Pose.get(service,context,'companion'))
            assert(not Pose.advance(service,context) and Pose.get(service,context,'host').pose=='sit')
            assert(service.activityState.personalPoses.actors.companion==nil and next(service.activityState.resources)==nil)
            assert(data.players.companion.itemSlots.equipment[2].id==guest.itemSlots.equipment[2].id)
        ''')

    def source_ui(self):
        self.pose()
        self.lua.execute('''
            local noop=function() end
            love.keyboard={isDown=function() return false end}
            sourceRuntime={state='game',scene='train',saveData=data,playerPose='lay',actionTimer=.2,actionKind='melee',poseMenu=true}
            sourceUI={playSfx=noop,poseIdle={x=0,y=0,w=20,h=20},poseSit={x=30,y=0,w=20,h=20},
                poseLay={x=60,y=0,w=20,h=20},poseAction={x=90,y=0,w=20,h=20}}
            local ctx={runtime=sourceRuntime,ui=sourceUI,commands=false,characters={},maintenanceSession={},scenery={},
                inventory=require('game.inventory'),catalog=Catalog,npcRelationships={},merchantTrade={},util=require('game.util'),
                controlBindings=require('game.control_bindings').new({getInfo=function() return nil end}),
                mobileEnabled=function() return false end,engineUpgrades={},trainUpgradeBalance={},
                maintenance={},battleRules=Rules,stops={},settlements={},interiorDoors={},firstAid={},shootingRange={}}
            setmetatable(ctx,{__index=function() return noop end})
            sourceInput=require('game.gameplay_input').new(ctx)
            function clickPose(name)
                sourceRuntime.poseMenu=true;local r=sourceUI[name]
                assert(sourceUI.handlePoseClick(r.x+1,r.y+1))
            end
        ''')

    def test_actual_source_offline_pose_assignments_and_automatic_e_timing_preserved(self):
        self.source_ui()
        self.lua.execute('''
            clickPose('poseIdle');assert(sourceRuntime.playerPose=='idle' and sourceRuntime.actionTimer==.2 and not sourceRuntime.poseMenu)
            clickPose('poseSit');assert(sourceRuntime.playerPose=='sit' and sourceRuntime.actionTimer==.2)
            clickPose('poseLay');assert(sourceRuntime.playerPose=='lay' and sourceRuntime.actionKind=='melee')
            clickPose('poseAction');assert(sourceRuntime.playerPose=='idle' and sourceRuntime.actionKind=='use' and sourceRuntime.actionTimer==.45)
            sourceRuntime.poseMenu=false;sourceInput.keypressed('e')
            assert(sourceRuntime.actionKind=='use' and sourceRuntime.actionTimer==.35)
            assert(not service.activityState.personalPoses and writes==originalWrites)
        ''')

    def test_actual_source_checked_callback_rejection_preserves_pose_without_speculation(self):
        self.source_ui()
        self.lua.execute('''
            local calls=0
            sourceUI.changePose=function(pose) calls=calls+1;assert(pose=='sit');return {ok=false,reason='pose_unavailable'} end
            clickPose('poseSit');assert(calls==1 and sourceRuntime.poseMenu and sourceRuntime.playerPose=='lay' and sourceRuntime.actionTimer==.2)
            sourceUI.changePose=function() return nil end;clickPose('poseIdle');assert(sourceRuntime.poseMenu and sourceRuntime.playerPose=='lay')
            sourceUI.changePose=function(pose) return service:submitLocal('player.pose',{pose=pose}) end
            clickPose('poseSit');assert(not sourceRuntime.poseMenu and sourceRuntime.playerPose=='lay')
            assert(Pose.get(service,context,'host').pose=='sit' and writes==originalWrites)
            sourceUI.changePose=function() return true end;clickPose('poseIdle')
            assert(not sourceRuntime.poseMenu and sourceRuntime.playerPose=='lay' and sourceRuntime.actionTimer==.2)
        ''')

    def test_actual_renderer_uses_manual_pose_below_original_e_use_and_melee_without_runtime_mutation(self):
        self.source_ui()
        self.lua.execute('''
            local noop=function() end;love.graphics={newShader=function() return {} end,setColor=noop,ellipse=noop}
            local image={getHeight=function() return 100 end,getWidth=function() return 100 end}
            sourceRuntime.player={x=200,y=250,facing=1,moving=false};sourceRuntime.animationClock=12
            local ctx={runtime=sourceRuntime,width=960,height=720,ui=sourceUI,backgroundImages={},scenery={},car={},colors={},landscape={},
                characterImages={[data.character]=image},getCharacterAnimations=function() return {[data.character]={}} end,
                characterAnimation={draw=function(_,file,action) rendered=action;return true end},
                catalog=Catalog,train={},family={},settlements={},stops={},util=require('game.util')}
            for _,name in ipairs({'characterWalkImages','characterActionImages','itemIdleImages','npcImages','npcWalkImages',
                'familyImages','mobImages','mobIdleImages','mobWalkImages','mobHitImages','mobDeathImages'}) do ctx[name]={} end
            setmetatable(ctx,{__index=function() return noop end})
            local renderer=require('game.world_renderer').new(ctx)
            sourceRuntime.actionTimer=0;sourceRuntime.actionKind=nil;sourceRuntime.playerPose='lay'
            renderer.drawPlayer(false);assert(rendered=='lay') -- Original offline runtime fallback.
            assert(submit('host','sit').ok)
            sourceUI.coopPlayerPresentation=function() return Pose.presentation(Pose.get(service,context,'host'),sourceRuntime) end
            renderer.drawPlayer(false);assert(rendered=='sit' and sourceRuntime.playerPose=='lay')
            assert(submit('host','use').ok);renderer.drawPlayer(false);assert(rendered=='use' and sourceRuntime.actionTimer==0)
            sourceRuntime.poseMenu=false;sourceInput.keypressed('e');assert(sourceRuntime.actionTimer==.35)
            assert(submit('host','idle').ok);renderer.drawPlayer(false)
            assert(rendered=='use' and sourceRuntime.actionTimer==.35 and sourceRuntime.actionKind=='use')
            sourceRuntime.actionTimer=.2;sourceRuntime.actionKind='melee'
            renderer.drawPlayer(false);assert(rendered=='melee' and sourceRuntime.actionTimer==.2)
            assert(Pose.presentation(nil,{playerPose='lay',actionTimer=.35,actionKind='use'}).playerPose=='lay')
        ''')


class PersonalPoseNetworkTests(unittest.TestCase):
    setUp = local_play.LocalPlayTests.setUp
    tearDown = local_play.LocalPlayTests.tearDown
    enable_cars = local_play.LocalPlayTests.enable_cars

    def test_real_runtime_installs_bound_nondurable_pose_and_strict_both_actor_snapshot(self):
        self.enable_cars()
        self.lua.execute('''
            hostContext.movement.presentation=function(id) return commands.poseState(id) end
            commands.setRemoteActorState(function()
                local m=host.motion
                return {screen=hostRuntime.state,scene=hostRuntime.scene,movementReady=m and m.readyEpoch==m.epoch,
                    motionId=m and m.motionId,moving=m and m.actor and m.actor.moving,
                    inputX=m and m.input and m.input.x or 0,inputY=m and m.input and m.input.y or 0}
            end)
            ready();motionReady();local writesBefore=writes
            assert(commands.submit('player.pose',{pose='sit'}).ok)
            local expected={['player:companion']=guest.replica.data.coop.revisions['player:companion'] or 0}
            assert(guest.network:submitCommand('player.pose',{pose='lay',motionId=host.motion.motionId},data.coop.sceneEpoch,expected))
            step(4);local reply=assert(guest.network.lastCommandResult)
            assert(reply.ok and reply.durable==false and reply.details.pose=='lay' and reply.details.actorId=='companion',reply.reason or 'wrong_pose_result')
            local Results=require('game.net.item_results');assert(Results.valid('player.pose',reply.details))
            assert(not Results.valid('player.pose',{actorId='companion',pose='use',serial=1,useMs=0}))
            assert(not Results.valid('player.pose',{actorId='companion',pose='lay',serial=0,useMs=0}))
            assert(not Results.valid('player.pose',{actorId='companion',pose='lay',serial=1,useMs=0,health=99}))
            assert(writes==writesBefore and next(service.activityState.resources)==nil and not data.players.companion.playerPose)
            local frame=assert(host.motion:snapshot(service.sessionId));local Wire=require('game.net.movement')
            assert(Wire.snapshot(frame) and frame.host.stance=='sit' and frame.companion.stance=='lay')
            assert(frame.companion.poseSerial==reply.details.serial and frame.companion.useRemainingMs==0)
            step(12) -- Reliable result may precede its separate campaign chunks.
            assert(guest.replica.data.coop.revision==data.coop.revision)
            local bad=assert(Schema.copy(frame));bad.companion.stance='death';assert(not Wire.snapshot(bad))
            bad=assert(Schema.copy(frame));bad.host.poseSerial=0;assert(not Wire.snapshot(bad))
            bad=assert(Schema.copy(frame));bad.host.useRemainingMs=451;assert(not Wire.snapshot(bad))
            bad=assert(Schema.copy(frame));bad.companion.duration=3;assert(not Wire.snapshot(bad))
            assert(not Wire.input(require('game.net.protocol').message('movement',{sessionId=service.sessionId,
                sceneEpoch=data.coop.sceneEpoch,motionId=host.motion.motionId,sequence=99,x=0,y=0,sprint=false,stance='sit'})))
        ''')


class PersonalPoseGuestTests(unittest.TestCase):
    setUp = guest_view.GuestViewTests.setUp

    def panel(self):
        self.lua.execute('''
            controller.network.status='ready';controller.network.sessionId='guest-test'
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                command={name=name,args=args,epoch=epoch,expected=expected};return 42
            end
            ready()
            function poseFrame(serial,pose,poseSerial,useMs)
                local f=frame(serial);f.ack=view.sequence;f.sessionId=controller.network.sessionId
                f.companion.stance=pose or 'idle';f.companion.poseSerial=poseSerial or 0;f.companion.useRemainingMs=useMs or 0
                controller.motionFrame=f;assert(view:update(.01));return f
            end
        ''')

    def test_pose_ui_waits_neutral_ack_and_nondurable_result_requires_actual_projected_pose(self):
        self.panel()
        self.lua.execute('''
            assert(view.poses:open());assert(not view:inputAllowed())
            assert(not view.poses:submit('sit') and not command)
            poseFrame(2);assert(view.poses:submit('sit'))
            assert(command.name=='player.pose' and command.args.motionId==view.motionId and not command.args.actorId)
            controller.network.lastCommandResult={requestId=42,sessionId='guest-test',command='player.pose',ok=true,durable=false,revision=data.coop.revision+1,
                details={actorId='companion',pose='sit',serial=7,useMs=0}}
            view.poses:update();assert(view.poses.pending and view.poses.opened and view.runtime.playerPose=='idle')
            view.runtime.saveData.coop.revision=data.coop.revision+1
            poseFrame(3,'sit',7);assert(not view.poses.pending and not view.poses.opened)
            assert(view.runtime.playerPose=='sit' and not data.players.companion.playerPose)
        ''')

    def test_fresh_host_and_owned_use_render_and_checked_melee_has_priority(self):
        self.panel()
        self.lua.execute('''
            local f=poseFrame(2,'lay',4)
            f=frame(3);f.ack=view.sequence;f.host.stance='sit';f.host.poseSerial=6;f.companion.poseSerial=5;f.companion.useRemainingMs=450
            controller.motionFrame=f;assert(view:update(.01))
            assert(view.runtime.playerPose=='idle' and view.runtime.actionKind=='use' and view.runtime.actionTimer==.45)
            assert(view.runtime.player.facing==f.companion.f,'manual USE erased checked facing')
            local _,_,remote=view.ui.coopCompanion();assert(remote.playerPose=='sit')
            view.field.poses.companion={epoch=view.epoch,untilTime=view.elapsed+.3,weapon='frontier-short-sword',facing=-1}
            view.field.poses.host={epoch=view.epoch,untilTime=view.elapsed+.3,weapon='frontier-short-sword',facing=-1}
            assert(view:update(.02));assert(view.runtime.actionKind=='melee' and view.runtime.actionHeldItem=='frontier-short-sword')
            _,_,remote=view.ui.coopCompanion();assert(remote.actionKind=='melee' and remote.playerPose=='sit')
            controller.motionFrame=frame(4);controller.motionFrame.ack=view.sequence;controller.motionFrame.sessionId='old-session';assert(view:update(.01))
            assert(view.poses:presentation('companion').playerPose==nil and view.runtime.playerPose=='idle')
        ''')

    def test_delayed_pose_reply_after_checked_movement_reset_clears_without_replaying_stance(self):
        self.panel()
        self.lua.execute('''
            assert(view.poses:open());poseFrame(2);assert(view.poses:submit('sit'))
            view.poses:close();assert(view.poses.pending)
            -- Accepted serial7 was legitimately replaced by host movement8
            -- before its reliable acknowledgement reached this panel.
            view.runtime.saveData.coop.revision=data.coop.revision+1
            poseFrame(3,'idle',8);controller.network.lastCommandResult={requestId=42,sessionId='guest-test',command='player.pose',ok=true,durable=false,
                revision=view.runtime.saveData.coop.revision,details={actorId='companion',pose='sit',serial=7,useMs=0}}
            view.poses:update();assert(not view.poses.pending and view.runtime.playerPose=='idle')
            assert(view.poses:open());poseFrame(4,'idle',8);assert(view.poses:submit('lay'))
            controller.network.lastCommandResult=nil
            controller.motionFrame=frame(5,true);controller.motionFrame.ack=view.sequence;assert(view:update(.01))
            assert(not view.poses.pending and not view.poses.opened and view.poses.frame==nil)
            assert(data.players.companion.playerPose==nil)
        ''')

    def test_new_motion_or_network_identity_does_not_accept_an_old_pose_result_as_new_pending(self):
        self.panel()
        self.lua.execute('''
            assert(view.poses:open());poseFrame(2);assert(view.poses:submit('sit'))
            controller.network.lastCommandResult={requestId=42,sessionId='guest-test',command='player.pose',ok=true,durable=false,revision=data.coop.revision,
                details={actorId='companion',pose='sit',serial=7,useMs=0}}
            view.motionId=view.motionId+1;view.poses:update();assert(not view.poses.pending and not view.poses.opened)
            view.motionId=controller.motionFrame.motionId
            controller.network.lastCommandResult=nil
            assert(view.poses:open());poseFrame(3);assert(view.poses:submit('lay'))
            local old=controller.network
            controller.network={status='ready',sessionId='replacement',sendMovement=old.sendMovement,
                submitCommand=old.submitCommand,sceneReady=old.sceneReady,lastCommandResult=old.lastCommandResult}
            view.poses:update();assert(not view.poses.pending and not view.poses.opened)
            assert(view.poses:presentation('companion').playerPose==nil and view.runtime.playerPose=='idle')
            controller.motionFrame.sessionId='replacement'
            assert(view.poses:open());poseFrame(4,'idle',9);controller.motionFrame.sessionId='replacement'
            assert(view.poses:submit('lay'))
            view.runtime.saveData.coop.revision=data.coop.revision+1
            controller.network.lastCommandResult={requestId=42,sessionId='guest-test',command='player.pose',ok=true,durable=false,
                revision=view.runtime.saveData.coop.revision,details={actorId='companion',pose='lay',serial=8,useMs=0}}
            view.poses:update();assert(view.poses.pending) -- Old session cannot clear a new request with a reused ID.
            controller.network.lastCommandResult.sessionId='replacement';controller.network.lastCommandResult.revision=view.runtime.saveData.coop.revision+1
            view.poses:update();assert(view.poses.pending) -- Future revision cannot clear before projection.
        ''')


if __name__ == '__main__':
    unittest.main()
