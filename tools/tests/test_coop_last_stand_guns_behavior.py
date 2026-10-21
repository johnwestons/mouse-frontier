"""Detached Last Stand gun authority, phase barriers and durable costs.

Headless PNG aperture acceptance is stubbed; authored slot/hit geometry is real.
"""
import unittest
import test_coop_battles_behavior as tactical


class LastStandGunCommandsTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def stand(self):
        self.lua.execute('''
            setup(); data.location=12; data.scene='stop'
            Guns=require('game.coop_guns'); Shootout=require('game.last_stand_shootout')
            Personal=require('game.coop_last_stand_state'); Window=require('game.window_scene')
            Shooting=require('game.first_person_shooting'); Sessions=require('game.coop_shooter_sessions')
            WorldView=require('game.world_view'); WorldView.toWorld=function() error('private camera used by command') end
            Shooting.playReport=function() error('audio played by command') end
            Window.pointOpen=function(window,w,h,x,y) testedWindow=window; return not blocked end
            data.lastStand={state='shootout',originStop=12,loanAmmo=0,loanActive=false}
            quest=data.lastStand; battle=Shootout.new(quest,data,Catalog,'wide',960,720)
            companion=assert(Shootout.forActor(battle,data,Catalog,'companion'))
            companion.windowId='tall'; hgun=battle.gun; ggun=companion.gun
            Life=require('game.coop_last_stand_lifecycle'); Life.ensure(data)
            PositionState=require('game.coop_last_stand_position_state'); PositionState.ensure(data)
            assert(PositionState.claim(data,'host','wide')); assert(PositionState.claim(data,'companion','tall'))
            Positions=require('game.coop_last_stand_positions'); Occupancy=require('game.coop_last_stand_occupancy')
            for _,target in ipairs(quest.targets) do target.status='hidden'; target.timer=999 end
            target=quest.targets[1]; target.status='exposed'; target.timer=999
            states={host={screen='game',scene='stop'},companion={screen='game',scene='stop',movementReady=true,modalDomain=Life.key(data)}}
            function readyPositions()
                local o=service.activityState.positionOccupancy or Occupancy.new(); service.activityState.positionOccupancy=o
                local now=service:sweepActivities()
                for _,id in ipairs({'host','companion'}) do
                    local lease=assert(Occupancy.acquire(o,Positions.domain(data),id,service.bindings[id],PositionState.selected(data,id),now,service.bindings))
                    lease.shootingReady=true
                end
            end
            readyPositions()
            ready={active=true,paused=false,encounterId=quest.combat.entityId,phaseRevision=quest.combat.phaseRevision}
            Guns.install(service,{catalog=Catalog,actorState=function(id) return states[id] end,
                lastStandState=function() return unavailable and nil or ready end,
                lastStandPosition=function(id) return Positions.occupied(data,service.activityState,service.bindings,service:sweepActivities(),id) end})
            function ga(id,extra)
                local scope=id=='host' and quest or quest.shooterSessions[id]
                local result={mode='lastStand',encounterId=quest.combat.entityId,
                    phaseRevision=quest.combat.phaseRevision,weaponId=scope.weaponSession.itemId}
                for key,value in pairs(extra or {}) do result[key]=value end
                return result
            end
            function point(id,slot)
                local window=quest.combat.defenders[id].windowId
                local x,y=Window.slotPosition(Window.layout(window,960,720),slot or 1)
                return math.floor(x/960*1000000+.5),math.floor(y/720*1000000+.5)
            end
            function shotArgs(id,extra)
                local x,y=point(id); local a=ga(id,{x=x,y=y})
                for key,value in pairs(extra or {}) do a[key]=value end
                return a
            end
            function shoot(id,extra) return run(id,'gun.fire',shotArgs(id,extra)) end
            function cover(id,value)
                return run(id,'gun.cover',{mode='lastStand',encounterId=quest.combat.entityId,
                    phaseRevision=quest.combat.phaseRevision,cover=value})
            end
            function tick(dt)
                Personal.updateGuns(battle,data,dt,960,720); Personal.updateDefenders(battle,dt)
            end
            function advance()
                assert(Personal.open(quest)); ready.phaseRevision=quest.combat.phaseRevision
                readyPositions()
            end
            writes=0
        ''')

    def test_guest_hit_uses_own_window_ammo_proficiency_and_shared_target(self):
        self.stand()
        self.lua.execute('''
            battle.ducking=true; battle.coverProgress=1
            local hp=target.health; local hm=hgun.magazine; local epoch=data.coop.sceneEpoch; local proficiency=host.weaponProficiency.firearms
            local r=shoot('companion'); assert(r.ok,r.reason); assert(r.durable and writes==1 and r.result.hit)
            assert(testedWindow=='tall' and target.health<hp and guest.ammo['22lr']==8)
            assert(host.ammo['22lr']==20 and hgun.magazine==hm and guest.weaponProficiency.firearms==1)
            assert(host.weaponProficiency.firearms==proficiency and data.scene=='stop' and data.coop.sceneEpoch==epoch)
            assert(#battle.effects==0 and next(battle.targetEffects)==nil and #companion.effects==0)
            assert(Schema.validate(saved) and saved.lastStand.combat.phaseRevision==r.result.phaseRevision)
        ''')

    def test_in_flight_guest_shot_survives_host_fire_and_is_charged_once(self):
        self.stand()
        self.lua.execute('''
            target.health=100; target.maxHealth=100
            local request=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            assert(shoot('host').ok)
            local r=service:execute('companion',1,request)
            assert(r.ok,r.reason); assert(r.durable and guest.ammo['22lr']==8)
            local hp=target.health
            assert(service:execute('companion',1,request).durable)
            assert(guest.ammo['22lr']==8 and target.health==hp and writes==2)
            local loaded=assert(Schema.migrate(saved))
            local fresh=Authority.new({campaign=loaded,sessionId='concurrent-restart',checkpoint=function() return true end})
            fresh:admit('companion',1)
            local fingerprint=assert(require('game.net.codec').encode(request,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            assert(fresh:receipt('companion',1,service.sessionId,request.requestId,fingerprint).durable)
            assert(loaded.players.companion.ammo['22lr']==8)
        ''')

    def test_live_shared_conflicts_never_relax_personal_or_future_revisions(self):
        self.stand()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            assert(cover('companion',false).ok)
            -- Use a new transport request ID with the original stale personal state.
            request.requestId=request.requestId+1
            assert(service:execute('companion',1,request).reason=='stale_revision')
            local future=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            future.expected['resources']=(data.coop.revisions.resources or 0)+1
            assert(service:execute('companion',1,future).reason=='stale_revision')
            assert(guest.ammo['22lr']==9)
        ''')

    def test_miss_cost_and_blocked_aperture_without_cost(self):
        self.stand()
        self.lua.execute('''
            local hp=target.health
            local r=shoot('companion',{x=990000,y=990000}); assert(r.ok and not r.result.hit)
            assert(guest.ammo['22lr']==8 and target.health==hp); tick(1)
            blocked=true; assert(shoot('companion').reason=='window_blocked')
            assert(guest.ammo['22lr']==8 and writes==1)
        ''')

    def test_forged_fields_invalid_coordinates_and_phase_are_rejected(self):
        self.stand()
        self.lua.execute('''
            for _,extra in ipairs({{damage=999},{targetId=1},{actorId='host'},{dt=99},{windowId='wide'},
                {x=0/0},{x=-1},{y=1000001},{phaseRevision=0},{phaseRevision=1.5}}) do
                assert(shoot('companion',extra).reason=='invalid_args')
            end
            local a=shotArgs('companion'); a.phaseRevision=nil
            assert(run('companion','gun.fire',a).reason=='invalid_args')
            assert(writes==0 and guest.ammo['22lr']==9)
        ''')

    def test_stale_phase_denies_every_gun_action_and_prepared_request(self):
        self.stand()
        self.lua.execute('''
            local old=quest.combat.phaseRevision
            local request=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            advance(); assert(service:execute('companion',1,request).reason=='stale_phase')
            for _,name in ipairs({'gun.fire','gun.reload','gun.select','gun.mode','gun.cover'}) do
                local a=name=='gun.fire' and shotArgs('companion') or ga('companion')
                if name=='gun.cover' then a.weaponId=nil; a.cover=true end
                a.phaseRevision=old; assert(run('companion',name,a).reason=='stale_phase')
            end
            ready.phaseRevision=old; assert(shoot('companion').reason=='stale_phase')
            assert(guest.ammo['22lr']==9 and writes==0)
        ''')

    def test_interior_paused_unready_down_and_foreign_scenes_cannot_shoot(self):
        self.stand()
        self.lua.execute('''
            quest.state='interior'; assert(shoot('companion').reason=='shooter_unavailable'); quest.state='shootout'
            ready.paused=true; assert(shoot('companion').reason=='shooter_unavailable'); ready.paused=false
            ready.active=false; assert(shoot('companion').reason=='shooter_unavailable'); ready.active=true
            guest.health=1; assert(shoot('companion').reason=='shooter_unavailable'); guest.health=20
            states.companion.scene='train'; assert(shoot('companion').reason=='shooter_unavailable'); states.companion.scene='stop'
            data.location=13; assert(shoot('companion').reason=='shooter_unavailable'); data.location=12
            ready.encounterId='e999'; assert(shoot('companion').reason=='shooter_unavailable')
            assert(writes==0 and guest.ammo['22lr']==9)
        ''')

    def test_cover_and_raise_interpolation_are_actor_owned(self):
        self.stand()
        self.lua.execute('''
            assert(cover('companion',true).ok and not battle.ducking)
            assert(shoot('companion').reason=='in_cover'); tick(.3)
            assert(companion.coverProgress==1 and battle.coverProgress==0)
            assert(cover('companion',false).ok); assert(shoot('companion').reason=='in_cover')
            tick(.3); assert(shoot('companion').ok)
        ''')

    def test_foreign_broken_changed_removed_and_loan_selection_are_denied(self):
        self.stand()
        self.lua.execute('''
            assert(shoot('companion',{weaponId=hgun.itemId}).reason=='ownership')
            guest.itemSlots.equipment[2].durability=0; assert(shoot('companion').reason=='weapon_broken')
            guest.itemSlots.equipment[2].durability=100
            assert(run('companion','gun.select',ga('companion',{weaponId='loan'})).reason=='ownership')
            Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            assert(shoot('companion',{weaponId=guest.itemSlots.inventory[1].id}).reason=='weapon_changed')
            Items.write(guest,nil,{kind='equipment',index=2},nil)
            assert(shoot('companion').reason=='ownership' and writes==0)
        ''')

    def test_partial_reload_and_mode_use_own_saved_session(self):
        self.stand()
        self.lua.execute('''
            guest.ammo['22lr']=20; assert(shoot('companion').ok); tick(1)
            assert(run('companion','gun.reload',ga('companion')).ok); tick(.75)
            local mag,timer=ggun.magazine,ggun.reloadTimer
            local copy=assert(Schema.migrate(data)); local own=Players.forActor(copy,'companion')
            local gun=Shooting.new(own,Catalog,copy.lastStand,960,720)
            assert(gun.magazine==mag and gun.reloadTimer==timer and own.ammo['22lr']==19 and host.ammo['22lr']==20)
            tick(20); local mode=hgun.fireMode
            local r=run('companion','gun.mode',ga('companion')); assert(r.ok,r.reason)
            assert(hgun.fireMode==mode and r.result.fireMode==ggun.fireMode and r.result.weaponId==ggun.itemId)
        ''')

    def test_switching_exact_duplicate_guns_preserves_cached_partial_magazines(self):
        self.stand()
        self.lua.execute('''
            local first=ggun.itemId; assert(shoot('companion').ok)
            assert(run('companion','gun.select',ga('companion')).reason=='weapon_busy'); tick(1)
            local mag,timer=ggun.magazine,ggun.cooldown
            Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            local second=guest.itemSlots.inventory[1].id
            assert(run('companion','gun.select',ga('companion',{weaponId=second})).ok)
            assert(run('companion','gun.select',ga('companion',{weaponId=first})).ok)
            local own=quest.shooterSessions.companion.weaponSession
            assert(own.itemId==first and own.magazine==mag and own.cooldown==timer and guest.ammo['22lr']==8)
            assert(Schema.validate(data))
        ''')

    def test_concurrent_finishing_shots_cost_each_shooter_but_award_one_kill(self):
        self.stand()
        self.lua.execute('''
            target.health=.01
            local hostRequest=assert(service:prepareRequest('host','gun.fire',shotArgs('host')))
            local guestRequest=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            local r=service:execute('companion',1,guestRequest); assert(r.ok and r.result.hit)
            assert(quest.kills==1 and target.status=='dying')
            local second=service:execute('host',0,hostRequest)
            assert(second.ok and not second.result.hit and host.ammo['22lr']==19)
            assert(service:execute('companion',1,guestRequest).durable and quest.kills==1 and guest.ammo['22lr']==8)
        ''')

    def test_failed_checkpoint_replay_retry_and_restored_receipt_do_not_charge_twice(self):
        self.stand()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            failSave=true; local r=service:execute('companion',1,request); assert(r.ok and r.savePending)
            local hp=target.health
            assert(service:execute('companion',1,request).ok and target.health==hp and guest.ammo['22lr']==8)
            assert(cover('host',true).reason=='save_pending'); failSave=false; assert(service:retryCheckpoint())
            assert(service:execute('companion',1,request).durable and guest.ammo['22lr']==8)
            local loaded=assert(Schema.migrate(saved))
            local fresh=Authority.new({campaign=loaded,sessionId='stand-restarted',checkpoint=function() return true end})
            fresh:admit('companion',1)
            local fingerprint=assert(require('game.net.codec').encode(request,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            local receipt=fresh:receipt('companion',1,service.sessionId,request.requestId,fingerprint)
            assert(receipt.ok and receipt.durable and loaded.players.companion.ammo['22lr']==8)
            assert(fresh:execute('companion',1,request).reason=='wrong_session')
        ''')

    def test_geometry_failure_leaves_ammo_health_revision_and_checkpoint_untouched(self):
        self.stand()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','gun.fire',shotArgs('companion')))
            Window.targetHit=function() error('forced geometry failure') end
            local revision=data.coop.revision; local hp=target.health
            assert(service:execute('companion',1,request).reason=='handler_error')
            assert(guest.ammo['22lr']==9 and target.health==hp and data.coop.revision==revision and writes==0)
        ''')

    def test_public_result_is_bounded_and_hides_private_hit_details(self):
        self.stand()
        self.lua.execute('''
            local r=shoot('companion'); assert(r.ok,r.reason)
            local Results=require('game.net.gun_results')
            r.result.x=55; r.result.damage=999; r.result.target={secret=true}
            local public=assert(Results.project('gun.fire',r.result))
            assert(public.x==nil and public.damage==nil and public.target==nil and public.phaseRevision==1)
            assert(Results.valid('gun.fire',public))
            public.phaseRevision=nil; assert(not Results.valid('gun.fire',public))
            public.phaseRevision=1; public.mode='ambush'; assert(not Results.valid('gun.fire',public))
        ''')

    def test_legacy_saved_phase_migration_and_malformed_revisions(self):
        self.stand()
        self.lua.execute('''
            guest.ammo['22lr']=20; assert(shoot('companion').ok); tick(1); assert(run('companion','gun.reload',ga('companion')).ok)
            local old=assert(Schema.copy(data)); old.version=38; old.lastStand.combat.version=1
            old.lastStand.combat.phaseRevision=nil
            local restored=assert(Schema.migrate(old)); local c=restored.lastStand.combat
            assert(restored.version==Schema.CURRENT_VERSION and c.version==2 and c.phaseRevision==1 and c.entityId==quest.combat.entityId)
            assert(c.clock==quest.combat.clock and restored.players.companion.ammo['22lr']==guest.ammo['22lr'])
            assert(restored.lastStand.shooterSessions.companion.weaponSession.reloadTimer==ggun.reloadTimer)
            for _,value in ipairs({0,-1,1.5,1e9+1,0/0,'1'}) do
                local bad=assert(Schema.copy(data)); bad.lastStand.combat.phaseRevision=value
                assert(not Schema.validate(bad) and not Schema.migrate(bad))
            end
            local bad=assert(Schema.copy(old)); bad.lastStand.combat.phaseRevision=1
            assert(not Schema.migrate(bad))
        ''')

    def test_guest_cannot_progress_or_retry_and_host_retry_invalidates_phase(self):
        self.stand()
        self.lua.execute('''
            for _,name in ipairs({'lastStand.accept','lastStand.start','lastStand.advance','lastStand.retry','lastStand.withdraw'}) do
                assert(run('companion',name,{}).reason=='host_only')
            end
            local phase=quest.combat.phaseRevision
            assert(Shootout.retry(companion)==false and quest.combat.phaseRevision==phase)
            Shootout.retry(battle); assert(quest.combat.phaseRevision==phase+1)
            assert(Personal.advance(quest) and quest.combat.phaseRevision==phase+2)
            quest.combat.phaseRevision=1e9
            assert(not Personal.open(quest) and quest.combat.phaseRevision==1e9)
        ''')


if __name__ == '__main__':
    unittest.main()
