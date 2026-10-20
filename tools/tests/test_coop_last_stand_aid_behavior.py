"""One defender, two helpers, durable host-owned progress and private guest input."""
import unittest
import test_coop_last_stand_progression_behavior as progression
import test_coop_last_stand_movement_behavior as movement
import test_coop_local_play_behavior as local_play


class DefenderAidTests(unittest.TestCase):
    setUp = progression.LastStandProgressionTests.setUp
    stand = progression.LastStandProgressionTests.stand

    def aid(self):
        self.stand()
        self.lua.execute('''
            enter(); assert(Life.move(quest,'backyard')); Life.ensure(data); refresh()
            Aid=require('game.coop_last_stand_aid'); AidState=require('game.coop_last_stand_aid_state')
            Results=require('game.net.last_stand_aid_results'); now=(service.lastNow or 0)+10; service.clock=function() return now end
            states={host={screen='game',scene='stop'},companion={screen='game',scene='stop',movementReady=true,modalDomain=Life.key(data)}}
            Aid.install(service,{actorState=function(id) return states[id] end,lastStandScene=function() return modal end})
            for _,id in ipairs({'host','companion'}) do local p=Life.pose(data,id); p.x,p.y=750,455 end
            quest.positionIntegrity=50; writes=0
            function treatment(action,id,extra)
                id=id or 'companion'; local a=args({action=action})
                if action~='acquire' and action~='inspect' then a.leaseId=lease end
                for k,v in pairs(extra or {}) do a[k]=v end
                local r=run(id,'lastStand.aid',a)
                if r.ok and r.result.leaseId then lease=r.result.leaseId; if id=='host' then modal.treatmentLeaseId=lease end end
                return r
            end
            function phase(index,id) local r=treatment('choose',id,{index=index}); assert(r.ok,r.reason); return r end
        ''')

    def test_guest_treats_during_host_pause_without_story_or_personal_rewards(self):
        self.aid()
        self.lua.execute('''
            modal.paused=true; local ammo=guest.ammo['22lr']; local r=treatment('acquire'); assert(r.ok and r.durable,r.reason)
            for i=1,6 do r=phase(i); assert(r.durable and Results.project(r.result)) end
            assert(not quest.woundedTreated); r=treatment('complete'); assert(r.ok and r.durable,r.reason)
            assert(quest.woundedTreated and quest.positionIntegrity==62 and not quest.residentChecked)
            assert(not quest.conversations['help-wounded'] and guest.ammo['22lr']==ammo)
            assert(not next(service.activityState.resources) and Schema.validate(saved))
            assert(treatment('complete').reason=='lease_expired' and quest.positionIntegrity==62)
            assert(treatment('acquire').result.inspected and quest.positionIntegrity==62)
        ''')

    def test_host_uses_same_rules_and_is_only_actor_to_mark_resident_check(self):
        self.aid()
        self.lua.execute('''
            quest.victory=true; local r=treatment('acquire','host'); assert(r.ok,r.reason)
            modal.paused=true; assert(quest.residentChecked and quest.conversations['help-wounded'])
            for i=1,6 do phase(i,'host') end
            assert(treatment('complete','host').ok and quest.positionIntegrity==62)
            modal.personalPaused=true; assert(treatment('inspect','host').reason=='patient_unavailable')
            modal.personalPaused=false; assert(treatment('inspect','host').ok)
        ''')

    def test_single_patient_lease_prevents_other_actor_and_forged_owner(self):
        self.aid()
        self.lua.execute('''
            assert(treatment('acquire').ok); assert(treatment('acquire','host').reason=='activity_busy')
            modal.treatmentLeaseId=lease
            assert(treatment('choose','host',{index=1}).reason=='lease_owner')
            assert(quest.treatmentProgress.phase==1 and writes==1)
            assert(treatment('pause').ok); assert(treatment('acquire','host').ok)
        ''')

    def test_validation_checks_modal_pose_readiness_health_and_args(self):
        self.aid()
        self.lua.execute('''
            local p=Life.pose(data,'companion'); p.x=480; states.companion.x=750
            assert(treatment('acquire').reason=='patient_distance'); p.x=750
            states.companion.movementReady=false; assert(treatment('acquire').reason=='patient_unavailable'); states.companion.movementReady=true
            states.companion.modalDomain='old'; assert(treatment('acquire').reason=='patient_unavailable'); states.companion.modalDomain=Life.key(data)
            states.companion.activeActivity='sewing'; assert(treatment('acquire').reason=='patient_unavailable'); states.companion.activeActivity=nil
            guest.health=0; assert(treatment('acquire').reason=='patient_unavailable'); guest.health=20
            assert(treatment('acquire',nil,{phase=6}).reason=='invalid_args')
            assert(treatment('acquire',nil,{revision=quest.lifecycle.revision-1}).reason=='stale_phase')
            assert(writes==0 and not quest.treatmentProgress)
        ''')

    def test_gestures_use_host_time_and_require_rubs_ointment_gauze_and_wraps(self):
        self.aid()
        self.lua.execute('''
            assert(treatment('acquire').ok)
            assert(treatment('press',nil,{x=512,y=420}).ok and quest.treatmentProgress.phase==2)
            assert(treatment('move',nil,{x=480,y=370}).ok)
            assert(treatment('tick',nil,{dt=999}).reason=='invalid_args')
            now=now+.4; assert(treatment('tick').ok and quest.treatmentProgress.phase==2)
            now=now+.4; assert(treatment('tick').ok and quest.treatmentProgress.phase==3)
            assert(treatment('press',nil,{x=430,y=370}).ok)
            for _,x in ipairs({530,430,530,430}) do assert(treatment('move',nil,{x=x,y=370}).ok) end
            assert(quest.treatmentProgress.phase==4)
            assert(treatment('press',nil,{x=420,y=370}).ok)
            for i=1,12 do assert(treatment('move',nil,{x=420+i*10,y=370+(i%2)*20}).ok) end
            assert(quest.treatmentProgress.phase==5)
            assert(treatment('press',nil,{x=480,y=370}).ok and quest.treatmentProgress.phase==6)
            assert(treatment('complete').reason=='treatment_incomplete')
            assert(treatment('press',nil,{x=400,y=370}).ok)
            for _,x in ipairs({560,400,560}) do assert(treatment('move',nil,{x=x,y=370}).ok) end
            assert(treatment('complete').ok and quest.positionIntegrity==62 and Schema.validate(saved))
        ''')

    def test_pause_persists_partial_treatment_and_reconnect_has_no_held_gesture(self):
        self.aid()
        self.lua.execute('''
            assert(treatment('acquire').ok); phase(1); phase(2)
            assert(treatment('press',nil,{x=430,y=370}).ok); assert(treatment('move',nil,{x=530,y=370}).ok)
            Life.pose(data,'companion').x=500; guest.health=0
            assert(treatment('pause').ok and saved.lastStand.treatmentProgress.rubDistance==100)
            local loaded=assert(Schema.migrate(saved)); assert(loaded.lastStand.treatmentProgress.phase==3)
            service:disconnect('companion',1); service:admit('companion',2)
            local restored=Authority.new({campaign=loaded,sessionId='aid-restored'}); assert(not next(restored.activityState.resources))
            guest.health=20; Life.pose(data,'companion').x=750; service.bindings.companion=1
            local r=treatment('acquire'); assert(r.ok,r.reason)
            assert(r.result.phase==3 and not r.result.dragging and r.result.session.lastRubDirection==0)
        ''')

    def test_final_gesture_and_completion_checkpoint_failures_retry_once(self):
        self.aid()
        self.lua.execute('''
            assert(treatment('acquire').ok); for i=1,5 do phase(i) end
            failSave=true; local r=phase(6); assert(r.savePending and not r.durable and not quest.woundedTreated)
            assert(treatment('complete').reason=='save_pending'); failSave=false; assert(service:retryCheckpoint())
            failSave=true; local request=assert(service:prepareRequest('companion','lastStand.aid',args({action='complete',leaseId=lease})))
            r=service:execute('companion',1,request); assert(r.ok and r.savePending and quest.positionIntegrity==62)
            assert(service:execute('companion',1,request).savePending and quest.positionIntegrity==62)
            failSave=false; assert(service:retryCheckpoint()); assert(service:execute('companion',1,request).durable)
            assert(saved.lastStand.woundedTreated and saved.lastStand.positionIntegrity==62)
        ''')

    def test_modal_change_expires_lock_without_changing_ordinary_scene_epoch(self):
        self.aid()
        self.lua.execute('''
            assert(treatment('acquire').ok); phase(1); local epoch=data.coop.sceneEpoch
            assert(Life.move(quest,'interior')); Life.ensure(data); refresh(); service:sweepActivities()
            assert(not next(service.activityState.resources) and data.coop.sceneEpoch==epoch)
            assert(quest.treatmentProgress.phase==2 and treatment('tick').reason=='patient_unavailable')
        ''')

    def test_save_and_public_facts_are_checked_without_exposing_progress_or_session(self):
        self.aid()
        self.lua.execute('''
            local r=treatment('acquire'); assert(r.ok,r.reason)
            local facts=assert(Results.project(r.result)); assert(not facts.session and not facts.progress)
            facts.progress={phase=6}; assert(not Results.valid(facts))
            local legacy=assert(Schema.copy(data)); legacy.version=41; legacy.lastStand.treatmentVersion=nil
            legacy.lastStand.treatmentProgress={stage=4,rubDistance=77,ointmentTrail={{x=480,y=370}}}
            local migrated=assert(Schema.migrate(legacy)); assert(migrated.version==Schema.CURRENT_VERSION and migrated.lastStand.treatmentProgress.phase==4)
            assert(migrated.lastStand.treatmentProgress.rubDistance==77 and Schema.validate(migrated))
            migrated.lastStand.treatmentProgress.stage=3; assert(not Schema.validate(migrated) and not Schema.migrate(migrated))
        ''')


class DefenderAidMovementLockTests(unittest.TestCase):
    setUp = local_play.LocalPlayTests.setUp
    tearDown = local_play.LocalPlayTests.tearDown

    def lock(self):
        self.lua.execute('''
            assert(F.enroll(data)); data.scene='stop'; hostRuntime.scene='stop'
            Life=require('game.coop_last_stand_lifecycle'); Leases=require('game.coop_leases')
            data.lastStand={state='backyard',originStop=data.location}; Life.ensure(data)
            commands=require('game.coop_inventory_runtime').new({runtime=hostRuntime,session=hostSession,
                catalog=require('game.catalog'),clock=function() return clock end})
            service=assert(commands.authority()); service:admit('companion',1)
            assert(Leases.acquire(service.activityState,'patient','companion',1,data.coop.sceneEpoch,clock,
                {kind='lastStandAid',modalDomain=Life.key(data)}))
            assert(commands.activityBusy('companion','lastStandAid'))
        ''')

    def test_expired_patient_lock_no_longer_blocks_movement_without_a_command(self):
        self.lock()
        self.lua.execute('''
            clock=clock+31
            assert(not commands.activityBusy('companion','lastStandAid'))
            assert(not next(service.activityState.resources))
        ''')

    def test_host_area_change_releases_movement_lock_without_a_guest_command(self):
        self.lock()
        self.lua.execute('''
            local epoch=data.coop.sceneEpoch
            assert(Life.move(data.lastStand,'interior')); Life.ensure(data)
            assert(data.coop.sceneEpoch==epoch and not commands.activityBusy('companion','lastStandAid'))
            assert(not next(service.activityState.resources))
        ''')


class GuestDefenderAidTests(unittest.TestCase):
    setUp = movement.LastStandGuestMotionTests.setUp
    farm = movement.LastStandGuestMotionTests.farm

    def aid(self):
        self.farm()
        self.lua.execute('''
            assert(Life.move(data.lastStand,'backyard')); Life.ensure(data); controller.replica.revision=3
            controller.motionFrame=modalFrame(2,3); assert(view:update(.05))
            view.runtime.player.x,view.runtime.player.y=750,455
            package.loaded['game.viewport'].toGame=function(x,y) return x,y end
            sent={}; clock=0; view.lastStand.aid.c.clock=function() return clock end
            view.lastStand.aid.art={new=function() return {} end,release=function() end}
            controller.network.submitCommand=function(_,name,args,epoch,expected)
                sent[#sent+1]={name=name,args=args,epoch=epoch,expected=expected}; return #sent
            end
            panel=view.lastStand.aid; assert(view.lastStand:action().id=='help-wounded')
            function ack(phase,ready)
                local p=panel.pending
                controller.network.lastCommandResult={requestId=p.id,ok=true,durable=true,revision=0,details={
                    actorId='companion',questId=panel.questId,revision=view.lastStand:state().revision,action=p.action,
                    leaseId='l1',itemName='house medical supplies',phase=phase,ready=ready==true,dragging=false,
                    pointer={x=480,y=370},expiresIn=30}}
                panel:update(.1)
            end
        ''')

    def test_open_controller_accessibility_uses_commands_while_motion_paused(self):
        self.aid()
        self.lua.execute('''
            view:gamepadpressed(nil,'a'); assert(sent[1].name=='lastStand.aid' and sent[1].args.action=='acquire')
            view:gamepadreleased(nil,'a')
            assert(panel.opened and not view:inputAllowed()); view:gamepadpressed(nil,'a'); assert(#sent==1)
            view:gamepadreleased(nil,'a')
            ack(1); view.paused=true; view:gamepadpressed(nil,'a'); clock=.2; panel:update(.1)
            assert(sent[2].args.action=='choose' and sent[2].args.index==1 and not sent[2].args.phase)
            assert(panel.opened and data.lastStand.treatmentProgress==nil)
        ''')

    def test_acquire_waits_for_durable_save_and_reliable_projection(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); controller.network.lastCommandResult={requestId=1,ok=true,savePending=true}
            panel:update(.1); assert(panel.pending and not panel.session)
            ack(2); assert(panel.session.phase==2)
            view:keypressed('return'); clock=.2; panel:update(.1); local p=panel.pending
            controller.network.lastCommandResult={requestId=p.id,ok=true,revision=999}
            panel:update(.1); assert(panel.pending and panel.session.phase==2)
            assert(not data.lastStand.treatmentProgress and not panel.completed)
        ''')

    def test_pause_after_pending_acquire_releases_the_patient_and_blocks_reopen(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); panel:suspend(); assert(panel.wantPause and not panel.opened)
            assert(not panel:open()); ack(1); clock=.2; panel:update(.1)
            assert(sent[2].args.action=='pause' and sent[2].args.leaseId=='l1')
            controller.network.lastCommandResult={requestId=2,ok=true,revision=0,details={actorId='companion',questId=panel.questId,
                leaseId='l1',phase=1,itemName='house medical supplies',pointer={x=480,y=370},ready=false,dragging=false,outcome='cancelled'}}
            panel:update(.1); assert(not panel:busy() and not view.runtime.guestActivityOpen)
        ''')

    def test_touch_drag_has_one_owner_and_never_reaches_mobile_movement(self):
        self.aid()
        self.lua.execute('''
            view:touchpressed('open',700,600); assert(panel.opened); ack(3)
            panel.point=function(_,x,y) return x,y end
            mobile.touchpressed=function() error('treatment touch became movement') end
            mobile.touchmoved=function() error('treatment touch moved the avatar') end
            mobile.touchreleased=function() error('treatment release reached joystick') end
            view:touchpressed('finger',430,370); view:touchpressed('other',560,370)
            view:touchmoved('other',550,370); view:touchmoved('finger',530,370); view:touchreleased('finger',530,370)
            assert(#panel.queue==3 and panel.queue[1].action=='press' and panel.queue[2].x==530 and panel.queue[3].action=='release')
            assert(panel.touch==nil and data.lastStand.treatmentProgress==nil)
        ''')

    def test_domain_transition_discards_pending_private_treatment(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); ack(1)
            assert(Life.move(view.runtime.saveData.lastStand,'interior')); Life.ensure(view.runtime.saveData)
            panel:update(.1); assert(not panel.opened and not panel.lease and not panel.pending and not panel.wantPause)
            assert(not view.runtime.guestActivityOpen)
        ''')

    def test_focus_and_local_play_menu_cancel_held_gestures_with_pause_command(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); ack(3); panel:enqueue('press',430,370)
            view:focus(false); panel:update(.1); assert(not panel.opened and #panel.queue==0)
            clock=.2; panel:update(.1); assert(sent[2].args.action=='pause')
        ''')

    def test_private_pause_and_controller_cancel_release_without_auto_reacquire(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); ack(3); view:keypressed('p')
            assert(view.lastStand.paused and not panel.opened and panel.wantPause)
            clock=.2; panel:update(.1); assert(sent[2].args.action=='pause')
            assert(#sent==2 and not panel.queue[1])
        ''')

    def test_final_ready_feedback_waits_for_checkpoint_before_complete(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); ack(6); view:keypressed('return'); clock=.2; panel:update(.1)
            assert(sent[2].args.action=='choose')
            controller.network.lastCommandResult={requestId=2,ok=true,savePending=true}
            clock=.4; panel:update(.1); assert(#sent==2 and not panel.completed)
            ack(6,true); assert(sent[3].args.action=='complete' and panel.pending.id==3)
            controller.network.lastCommandResult={requestId=3,ok=true,savePending=true}
            clock=.6; panel:update(.1); assert(not panel.completed and panel.lease)
            controller.network.lastCommandResult={requestId=3,ok=true,durable=true,revision=0,
                details={actorId='companion',questId=panel.questId,action='complete',completed=true,integrity=62}}
            panel:update(.1); assert(panel.completed and not panel.lease and #sent==3)
        ''')

    def test_save_barrier_cleared_lock_reacquires_saved_ready_treatment(self):
        self.aid()
        self.lua.execute('''
            view:keypressed('e'); ack(6); view:keypressed('return'); clock=.2; panel:update(.1)
            clock=.4; ack(6,true); assert(sent[3].args.action=='complete')
            controller.network.lastCommandResult={requestId=3,ok=false,reason='lease_expired'}
            clock=.6; panel:update(.1); assert(panel.resumeAcquire and not panel.completed and not panel.session.dragging)
            clock=.8; panel:update(.1); assert(sent[4].args.action=='acquire' and not sent[4].args.leaseId)
            clock=1; ack(6,true); assert(not panel.resumeAcquire and sent[5].args.action=='complete')
            assert(data.lastStand.treatmentProgress==nil and #panel.queue==0)
        ''')


if __name__ == '__main__':
    unittest.main()
