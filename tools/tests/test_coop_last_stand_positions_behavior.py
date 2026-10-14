"""Personal window selection foundation, distinct from future live occupancy."""
import unittest
import test_coop_last_stand_progression_behavior as progression


class LastStandPositionTests(unittest.TestCase):
    setUp = progression.LastStandProgressionTests.setUp
    stand = progression.LastStandProgressionTests.stand

    def positions(self):
        self.stand()
        self.lua.execute('''
            enter(); PositionState=require('game.coop_last_stand_position_state')
            Positions=require('game.coop_last_stand_positions'); PositionResults=require('game.net.last_stand_position_results')
            states={host={screen='game',scene='stop'},companion={screen='game',scene='stop',movementReady=true,modalDomain=Life.key(data)}}
            positionContext={catalog=Catalog,actorState=function(id) return states[id] end,lastStandScene=function() return modal end,
                lastStandPhase=function(id) return quest.combat and {active=true,paused=false,encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision} end}
            Positions.install(service,positionContext)
            for _,id in ipairs({'host','companion'}) do local p=Life.pose(data,id); p.x,p.y=350,310 end
            function pick(id,window,extra)
                local a=args({action='select',window=window or 'wide'})
                for k,v in pairs(extra or {}) do a[k]=v end
                return run(id or 'companion','lastStand.position',a)
            end
            function unpick(id) return run(id or 'companion','lastStand.position',args({action='release'})) end
            writes=0
        ''')

    def firing(self, reserve=True):
        self.positions()
        self.lua.globals().reserve = reserve
        self.lua.execute('''
            if reserve then Life.pose(data,'companion').x=660; assert(pick(nil,'tall').ok) end
            Life.pose(data,'host').x,Life.pose(data,'host').y=350,310
            modal.x,modal.y=350,310; modal.action='window-wide'; modal.handoffWindow='wide'; modal.handoffElapsed=1
            assert(step('start',{window='wide'}).ok)
            states.companion.modalDomain=Life.key(data)
            positionContext.lastStandState=positionContext.lastStandPhase
            require('game.coop_guns').install(service,positionContext)
            Window=require('game.window_scene'); Window.pointOpen=function() return true end
            function readyPosition(id,window,extra)
                local a=args({action='ready',window=window or 'tall',phaseRevision=quest.combat.phaseRevision})
                for k,v in pairs(extra or {}) do a[k]=v end
                return run(id or 'companion','lastStand.position',a)
            end
            function occupied(id)
                return Positions.occupied(data,service.activityState,service.bindings,service:sweepActivities(),id)
            end
            function gunCover(id,cover)
                return run(id,'gun.cover',{mode='lastStand',encounterId=quest.combat.entityId,
                    phaseRevision=quest.combat.phaseRevision,cover=cover})
            end
            writes=0
        ''')

    def test_selection_is_personal_durable_and_does_not_progress_story(self):
        self.positions()
        self.lua.execute('''
            local revision,epoch=quest.lifecycle.revision,data.coop.sceneEpoch
            local ammo=guest.ammo['22lr']; modal.paused=true
            local r=pick(); assert(r.ok and r.durable,r.reason)
            assert(PositionState.selected(data,'companion')=='wide' and not PositionState.selected(data,'host'))
            assert(PositionResults.valid(r.result) and saved.lastStand.firingPositions.companion=='wide')
            assert(quest.state=='interior' and quest.lifecycle.revision==revision and data.coop.sceneEpoch==epoch)
            assert(not quest.combat and not quest.residentChecked and not quest.rewardClaimed and not quest.conversations['window-wide'])
            assert(guest.ammo['22lr']==ammo and next(service.activityState.resources)==nil)
            assert(pick('host').reason=='position_unavailable'); modal.paused=false
            assert(pick('host').reason=='position_occupied' and writes==1)
            local p=Life.pose(data,'host'); p.x=660
            assert(pick('host','tall').ok and PositionState.selected(data,'host')=='tall')
            assert(PositionState.validate(data) and Schema.validate(saved))
        ''')

    def test_saved_pose_controls_selection_and_client_coordinates_are_rejected(self):
        self.positions()
        self.lua.execute('''
            Life.pose(data,'companion').x=480; states.companion.x=350; states.companion.y=280
            guest.playerX=350; guest.playerY=280
            assert(pick().reason=='position_distance')
            assert(pick(nil,nil,{x=350,y=280}).reason=='invalid_args')
            assert(pick(nil,nil,{actorId='host'}).reason=='invalid_args' and writes==0)
        ''')

    def test_current_readiness_life_and_personal_health_are_required(self):
        self.positions()
        self.lua.execute('''
            states.companion.movementReady=false; assert(pick().reason=='position_unavailable'); states.companion.movementReady=true
            states.companion.modalDomain='old'; assert(pick().reason=='position_unavailable'); states.companion.modalDomain=Life.key(data)
            states.companion.activeActivity='lastStandAid'; assert(pick().reason=='position_unavailable'); states.companion.activeActivity=nil
            guest.health=0; assert(pick().reason=='position_unavailable'); guest.health=20
            assert(pick(nil,nil,{revision=quest.lifecycle.revision-1}).reason=='stale_phase')
            assert(pick(nil,nil,{questId='e999999'}).reason=='position_unavailable')
            modal.blocked=true; assert(pick().reason=='position_unavailable' and writes==0)
        ''')

    def test_switch_and_release_never_take_other_actors_window(self):
        self.positions()
        self.lua.execute('''
            assert(pick().ok); Life.pose(data,'companion').x=660
            local r=pick(nil,'tall'); assert(r.ok and r.result.previousWindowId=='wide' and r.result.windowId=='tall')
            assert(PositionState.owner(data,'wide')==nil and PositionState.owner(data,'tall')=='companion')
            assert(pick('host').ok); assert(unpick().ok)
            assert(PositionState.selected(data,'host')=='wide' and not PositionState.selected(data,'companion'))
            local r=unpick(); assert(r.ok and r.result.previousWindowId==nil and r.result.windowId==nil)
            assert(PositionResults.valid(r.result))
        ''')

    def test_saved_choice_survives_modal_transition_without_activity_lease(self):
        self.positions()
        self.lua.execute('''
            assert(pick().ok); assert(Life.move(quest,'backyard')); Life.ensure(data); refresh()
            assert(PositionState.selected(data,'companion')=='wide' and next(service.activityState.resources)==nil)
            assert(pick().reason=='position_unavailable')
            assert(Life.move(quest,'interior')); Life.ensure(data); refresh()
            states.companion.modalDomain=Life.key(data)
            local restored=assert(Schema.copy(data)); PositionState.prepare(restored)
            assert(PositionState.validate(restored) and PositionState.selected(restored,'companion')=='wide')
        ''')

    def test_failed_save_replay_and_rejoin_preserve_one_selection(self):
        self.positions()
        self.lua.execute('''
            failSave=true; local request=assert(service:prepareRequest('companion','lastStand.position',args({action='select',window='wide'})))
            local r=service:execute('companion',1,request)
            assert(r.ok and r.savePending and not r.durable and writes==1)
            assert(service:execute('companion',1,request).savePending and writes==1)
            failSave=false; assert(service:retryCheckpoint()); assert(service:execute('companion',1,request).durable and writes==2)
            service:disconnect('companion',1); service:admit('companion',2)
            assert(PositionState.selected(data,'companion')=='wide' and next(service.activityState.resources)==nil)
            local restored=assert(Schema.copy(saved)); PositionState.prepare(restored)
            assert(PositionState.validate(restored) and PositionState.selected(restored,'companion')=='wide')
            local next=Authority.new({campaign=restored,sessionId='positions-restored'}); next:admit('companion',3)
            local fingerprint=assert(require('game.net.codec').encode(request,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            assert(next:receipt('companion',3,request.sessionId,request.requestId,fingerprint).durable)
        ''')

    def test_state_migration_uses_existing_choices_without_inventing_a_guest(self):
        self.positions()
        self.lua.execute('''
            PositionState.prepare(data); assert(PositionState.validate(data) and next(quest.firingPositions)==nil)
            PositionState.reset(quest); quest.lastWindow='tall'; PositionState.prepare(data)
            assert(quest.firingPositions.host=='tall' and quest.firingPositions.companion==nil)
            PositionState.reset(quest); quest.combat={defenders={host={windowId='wide'},companion={windowId='tall'}}}
            PositionState.prepare(data); assert(quest.firingPositions.host=='wide' and quest.firingPositions.companion=='tall')
            PositionState.reset(quest); quest.combat.defenders.companion.windowId='wide'; PositionState.prepare(data)
            assert(quest.firingPositions.host=='wide' and quest.firingPositions.companion==nil)
        ''')

    def test_marked_corruption_is_rejected_instead_of_normalized(self):
        self.positions()
        self.lua.execute('''
            PositionState.ensure(data); quest.firingPositions={host='wide',companion='wide'}
            assert(not PositionState.validate(data)); PositionState.prepare(data)
            assert(quest.firingPositions.companion=='wide' and pick().reason=='position_unavailable')
            quest.firingPositions={host='roof'}; assert(not PositionState.validate(data))
            quest.firingPositions={host='wide',leaseId='l1'}; assert(not PositionState.validate(data))
            quest.firingPositions={companion='tall'}; data.players.companion=nil; assert(not PositionState.validate(data))
            quest.firingPositions={}; quest.positionVersion=2; assert(not PositionState.validate(data))
        ''')

    def test_wire_facts_are_bounded_and_strip_private_tables(self):
        self.positions()
        self.lua.execute('''
            local r=pick(); assert(r.ok,r.reason); local v=r.result
            v.quest=quest; v.privateProgress={held=true}; assert(not PositionResults.valid(v))
            local public=assert(PositionResults.project(v)); assert(not public.quest and not public.privateProgress)
            local leaseId=public.leaseId; public.leaseId='l1'; assert(not PositionResults.valid(public)); public.leaseId=leaseId
            public.actorId='enemy'; assert(not PositionResults.valid(public)); public.actorId='companion'
            public.windowId='roof'; assert(not PositionResults.valid(public)); public.windowId='wide'
            public.action='start'; assert(not PositionResults.valid(public)); public.action='select'
            public.revision=0; assert(not PositionResults.valid(public)); public.revision=1
            public.previousWindowId='backdoor'; assert(not PositionResults.valid(public))
            assert(not PositionResults.valid(false))
        ''')

    def test_host_cannot_start_from_guest_occupied_window_or_forged_saved_pose(self):
        self.positions()
        self.lua.execute('''
            assert(pick().ok); modal.x,modal.y=350,310; modal.action='window-wide'; modal.handoffWindow='wide'; modal.handoffElapsed=1
            Life.pose(data,'host').x=480; assert(action('start',{window='wide'}).reason=='window_unavailable')
            Life.pose(data,'host').x,Life.pose(data,'host').y=350,310
            assert(action('start',{window='wide'}).reason=='position_occupied')
            assert(quest.state=='interior' and not quest.combat and PositionState.selected(data,'companion')=='wide')
        ''')

    def test_carried_choice_does_not_authorize_shooting_until_current_ready(self):
        self.firing()
        self.lua.execute('''
            local o=service.activityState.positionOccupancy; local reserve=o.windows.tall
            assert(reserve.actorId=='companion' and reserve.shootingReady~=true and occupied('companion')==nil)
            assert(not quest.combat.defenders.companion and not quest.shooterSessions)
            assert(gunCover('companion',true).reason=='shooter_unavailable')
            local r=readyPosition(); assert(r.ok and r.durable,r.reason)
            assert(PositionResults.valid(r.result) and r.result.phaseRevision==quest.combat.phaseRevision)
            assert(occupied('companion').shootingReady and quest.combat.defenders.companion.windowId=='tall')
            assert(quest.shooterSessions.companion.weaponSession.actorId=='companion')
            local cover=gunCover('companion',true); assert(cover.ok,cover.reason); assert(quest.combat.defenders.companion.ducking)
            assert(quest.state=='shootout' and not quest.rewardClaimed and Schema.validate(saved))
        ''')

    def test_late_join_can_ready_free_window_without_an_interior_selection(self):
        self.firing(False)
        self.lua.execute('''
            assert(not PositionState.selected(data,'companion') and not quest.combat.defenders.companion)
            local hostAmmo,guestAmmo=host.ammo['22lr'],guest.ammo['22lr']
            local r=readyPosition(); assert(r.ok,r.reason)
            assert(PositionState.selected(data,'companion')=='tall' and occupied('companion'))
            assert(host.ammo['22lr']==hostAmmo and guest.ammo['22lr']==guestAmmo)
            assert(readyPosition(nil,'wide').reason=='position_occupied')
            assert(quest.combat.defenders.companion.windowId=='tall')
        ''')

    def test_ready_requires_live_raw_phase_and_current_acknowledged_modal(self):
        self.firing()
        self.lua.execute('''
            states.companion.movementReady=false; assert(readyPosition().reason=='position_unavailable'); states.companion.movementReady=true
            states.companion.modalDomain='old'; assert(readyPosition().reason=='position_unavailable'); states.companion.modalDomain=Life.key(data)
            assert(readyPosition(nil,nil,{phaseRevision=quest.combat.phaseRevision+1}).reason=='stale_phase')
            local raw=positionContext.lastStandPhase; positionContext.lastStandPhase=function() return {active=false} end
            assert(readyPosition().reason=='position_unavailable'); positionContext.lastStandPhase=raw
            modal.paused=true; assert(readyPosition().ok)
            assert(readyPosition('host','wide').reason=='position_unavailable')
            assert(quest.state=='shootout' and not quest.rewardClaimed)
        ''')

    def test_failed_ready_checkpoint_and_barrier_recovery_preserve_owned_gun(self):
        self.firing()
        self.lua.execute('''
            failSave=true; local request=assert(service:prepareRequest('companion','lastStand.position',
                args({action='ready',window='tall',phaseRevision=quest.combat.phaseRevision})))
            local r=service:execute('companion',1,request); assert(r.ok and r.savePending and not r.durable)
            local scope=quest.shooterSessions.companion; local item=scope.weaponSession.itemId
            assert(service:execute('companion',1,request).savePending and writes==1)
            scope.weaponSession.magazine=3; scope.weaponSession.cooldown=.4
            failSave=false; assert(service:retryCheckpoint())
            assert(service:execute('companion',1,request).durable and writes==2)
            service:suspendActivities(); assert(not occupied('companion') and gunCover('companion',true).reason=='position_expired')
            r=readyPosition(); assert(r.ok,r.reason)
            assert(scope.weaponSession.itemId==item and scope.weaponSession.magazine==3 and scope.weaponSession.cooldown==.4)
            assert(guest.ammo['22lr']==9 and quest.shooterSessions.companion.loanAmmo==0 and Schema.validate(saved))
        ''')

    def test_disconnect_rejoin_and_offline_reclaim_do_not_duplicate_ammo(self):
        self.firing()
        self.lua.execute('''
            assert(readyPosition().ok); local gun=quest.shooterSessions.companion.weaponSession
            local item=gun.itemId; gun.magazine=2; gun.reloadTimer=.5
            service:disconnect('companion',1); assert(not occupied('companion'))
            service:admit('companion',2)
            local request=assert(service:prepareRequest('companion','lastStand.position',
                args({action='ready',window='tall',phaseRevision=quest.combat.phaseRevision})))
            assert(service:execute('companion',2,request).ok)
            assert(gun.itemId==item and gun.magazine==2 and gun.reloadTimer==.5 and guest.ammo['22lr']==9)
            service:disconnect('companion',2)
            local r=readyPosition('host','tall'); assert(r.ok,r.reason)
            assert(PositionState.selected(data,'host')=='tall' and PositionState.selected(data,'companion')==nil)
            assert(quest.combat.defenders.host.windowId=='tall' and gun.itemId==item and gun.magazine==2)
        ''')

    def test_maintenance_renews_only_trusted_ready_actors_without_save_edits(self):
        self.firing()
        self.lua.execute('''
            assert(readyPosition().ok); local o=service.activityState.positionOccupancy
            local now=service:sweepActivities(); local guestLease=o.windows.tall; local before=guestLease.expiresAt
            local revision=data.coop.revision; local selection=quest.firingPositions.companion
            assert(Positions.maintain(data,service.activityState,service.bindings,now+1,positionContext))
            assert(guestLease.expiresAt==now+31 and guestLease.expiresAt>before)
            states.companion.movementReady=false
            assert(Positions.maintain(data,service.activityState,service.bindings,now+2,positionContext))
            assert(guestLease.expiresAt==now+31 and data.coop.revision==revision and quest.firingPositions.companion==selection)
            assert(Positions.maintain(data,service.activityState,service.bindings,now+31,positionContext))
            assert(not o.windows.tall and quest.firingPositions.companion=='tall')
        ''')

    def test_unready_carried_occupancy_expires_and_host_reclaims_saved_intent(self):
        self.firing()
        self.lua.execute('''
            local o=service.activityState.positionOccupancy; local now=service:sweepActivities()
            assert(Positions.maintain(data,service.activityState,service.bindings,now+29,positionContext))
            assert(o.windows.tall and not o.windows.tall.shootingReady)
            assert(Positions.maintain(data,service.activityState,service.bindings,now+31,positionContext))
            assert(not o.windows.tall and PositionState.selected(data,'companion')=='tall')
            service.clock=function() return now+32 end
            local r=readyPosition('host','tall'); assert(r.ok,r.reason)
            assert(PositionState.selected(data,'host')=='tall' and not PositionState.selected(data,'companion'))
        ''')


class LastStandOccupancyTests(unittest.TestCase):
    setUp = progression.LastStandProgressionTests.setUp

    def occupancy(self):
        self.lua.execute('''
            Occupancy=require('game.coop_last_stand_occupancy'); occupancy=Occupancy.new()
            domain={questId='e33',revision=5,mode='interior',sceneEpoch=data.coop.sceneEpoch}
            bindings={host=0,companion=1}
            function occupy(id,window,now,generation)
                return Occupancy.acquire(occupancy,domain,id,generation or (id=='host' and 0 or 1),window,now,bindings)
            end
        ''')

    def test_two_distinct_owners_never_create_generic_activity_locks(self):
        self.occupancy()
        self.lua.execute('''
            local revision=data.coop.revision; local quest=data.lastStand
            local host=assert(occupy('host','wide',10)); local guest=assert(occupy('companion','tall',10))
            assert(host.id~=guest.id and Occupancy.owner(occupancy,'wide')=='host' and Occupancy.owner(occupancy,'tall')=='companion')
            assert(select(2,occupy('companion','wide',10))=='position_occupied')
            assert(Occupancy.owner(occupancy,'tall')=='companion' and next(service.activityState.resources)==nil)
            assert(data.coop.revision==revision and data.lastStand==quest and Schema.validate(data))
        ''')

    def test_switch_is_atomic_and_owned_release_cannot_free_the_other_actor(self):
        self.occupancy()
        self.lua.execute('''
            local h=assert(occupy('host','wide',10)); local g=assert(occupy('companion','tall',10))
            assert(select(2,Occupancy.release(occupancy,g.id,'host',0,domain,10,bindings))=='position_owner')
            assert(Occupancy.release(occupancy,h.id,'host',0,domain,10,bindings))
            local switched=assert(occupy('companion','wide',11)); assert(switched.id~=g.id)
            assert(not Occupancy.owner(occupancy,'tall') and Occupancy.owner(occupancy,'wide')=='companion')
            assert(select(2,Occupancy.renew(occupancy,g.id,'companion',1,domain,11,bindings))=='position_expired')
        ''')

    def test_renewal_uses_fixed_host_time_and_bounded_extension_rate(self):
        self.occupancy()
        self.lua.execute('''
            local lease=assert(occupy('companion','wide',10)); assert(lease.expiresAt==40)
            for i=1,24 do assert(Occupancy.renew(occupancy,lease.id,'companion',1,domain,10+i/100,bindings)) end
            assert(lease.expiresAt==40 and lease.lastRenewedAt==10)
            assert(Occupancy.renew(occupancy,lease.id,'companion',1,domain,10.25,bindings))
            assert(lease.expiresAt==40.25)
            assert(select(2,Occupancy.renew(occupancy,lease.id,'companion',1,domain,10.2,bindings))=='invalid_time')
            assert(select(2,Occupancy.renew(occupancy,lease.id,'companion',1,domain,0/0,bindings))=='invalid_time')
            assert(lease.expiresAt==40.25)
        ''')

    def test_expiry_frees_window_for_host_at_the_exact_deadline(self):
        self.occupancy()
        self.lua.execute('''
            local guest=assert(occupy('companion','wide',10))
            assert(select(2,occupy('host','wide',39.999))=='position_occupied')
            local host=assert(occupy('host','wide',40)); assert(host.actorId=='host' and host.id~=guest.id)
            assert(select(2,Occupancy.find(occupancy,guest.id,'companion',1,domain,40,bindings))=='position_expired')
        ''')

    def test_disconnect_and_new_generation_reclaim_without_host_save_changes(self):
        self.occupancy()
        self.lua.execute('''
            local guest=assert(occupy('companion','wide',10)); bindings.companion=nil
            assert(Occupancy.sweep(occupancy,domain,bindings,11) and not Occupancy.owner(occupancy,'wide'))
            assert(occupy('host','wide',11)); bindings.companion=2
            assert(select(2,occupy('companion','tall',11,1))=='invalid_occupancy')
            local joined=assert(occupy('companion','tall',11,2)); assert(joined.id~=guest.id)
            assert(select(2,Occupancy.find(occupancy,guest.id,'companion',2,domain,11,bindings))=='position_expired')
            bindings.companion=3; assert(Occupancy.sweep(occupancy,domain,bindings,12))
            assert(Occupancy.owner(occupancy,'wide')=='host' and not Occupancy.owner(occupancy,'tall'))
        ''')

    def test_each_modal_identity_epoch_and_shooting_phase_invalidates_occupancy(self):
        self.occupancy()
        self.lua.execute('''
            local now=10
            for _,change in ipairs({function() domain.questId='e34' end,function() domain.revision=6 end,
                function() domain.sceneEpoch=domain.sceneEpoch+1 end,
                function() domain.mode='shootout'; domain.phaseRevision=1 end,function() domain.phaseRevision=2 end}) do
                assert(occupy('companion','wide',now)); change(); now=now+1
                assert(Occupancy.sweep(occupancy,domain,bindings,now) and not Occupancy.owner(occupancy,'wide'))
            end
            assert(occupy('host','wide',now)); assert(Occupancy.sweep(occupancy,nil,bindings,now+1))
            assert(next(occupancy.windows)==nil)
        ''')

    def test_live_firing_phase_acquisition_does_not_enroll_or_start_combat(self):
        self.occupancy()
        self.lua.execute('''
            domain.mode='shootout'; domain.phaseRevision=9; local quest=data.lastStand
            local lease=assert(occupy('companion','tall',10))
            assert(lease.domain.phaseRevision==9 and data.lastStand==quest and (not quest or not quest.combat))
            domain.revision=10; assert(lease.domain.revision==5)
            assert(Occupancy.sweep(occupancy,domain,bindings,11) and next(occupancy.windows)==nil)
            assert(next(service.activityState.resources)==nil)
        ''')

    def test_invalid_domain_owner_clock_and_ids_do_not_create_occupancy(self):
        self.occupancy()
        self.lua.execute('''
            assert(select(2,occupy('visitor','wide',10))=='invalid_occupancy')
            assert(select(2,occupy('host','roof',10))=='invalid_occupancy')
            assert(select(2,occupy('host','wide',10,1))=='invalid_occupancy')
            domain.dt=999; assert(select(2,occupy('host','wide',10))=='invalid_occupancy'); domain.dt=nil
            domain.mode='backyard'; assert(select(2,occupy('host','wide',10))=='invalid_occupancy'); domain.mode='shootout'
            assert(select(2,occupy('host','wide',10))=='invalid_occupancy'); domain.phaseRevision=1
            assert(select(2,occupy('host','wide',math.huge))=='invalid_time')
            occupancy.nextId=2147483647; assert(select(2,occupy('host','wide',10))=='position_ids_exhausted')
            assert(next(occupancy.windows)==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
