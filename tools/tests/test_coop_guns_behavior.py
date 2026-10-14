"""Owned ambush commands, host time/targets, saved receipts and personal cover."""
import unittest
import test_coop_battles_behavior as tactical


class AmbushCommandTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def ambush(self):
        self.lua.execute('''
            setup(); data.location=6; data.scene='train'
            Guns=require('game.coop_guns'); Ambush=require('game.train_ambush_rules')
            Personal=require('game.coop_ambush_state'); Shooting=require('game.first_person_shooting')
            Sessions=require('game.coop_shooter_sessions')
            convoy=Ambush.start(data); convoy.phase='combat'
            pickup=Ambush.vehicle(convoy,'pickup'); pickup.motion.phase='matched'
            for _,v in ipairs(convoy.vehicles) do for _,c in ipairs(v.crew) do c.timer=999 end end
            pickup.crew[1].phase='aim'; pickup.crew[1].timer=999
            hgun=Shooting.new(host,Catalog,convoy,960,720); ggun=Shooting.new(guest,Catalog,convoy,960,720)
            Personal.owner(convoy,'companion',true)
            states={host={screen='game',scene='train'},companion={screen='game',scene='train'}}
            ready={active=true,encounterId=convoy.entityId,paused=false}
            ctx={catalog=Catalog,actorState=function(id) return states[id] end,ambushState=function() return ready end,
                ambushOpen=function(s,w,h,x,y) assert(w==960 and h==720); return x>200 and x<800 and y>100 and y<450 end,
                ambushTarget=function(s,w,h,x,y)
                    if crashTarget then error('forced target failure') end
                    if x<300 then return {kind='crew',vehicle='pickup',index=1} end
                    return nil
                end}
            Guns.install(service,ctx); writes=0
            function ga(id,extra)
                local owner=id=='host' and convoy or convoy.shooterSessions[id]
                local result={mode='ambush',encounterId=convoy.entityId,weaponId=owner.weaponSession.itemId}
                for key,value in pairs(extra or {}) do result[key]=value end
                return result
            end
            function shoot(id,extra)
                local args=ga(id,{x=260000,y=350000})
                for key,value in pairs(extra or {}) do args[key]=value end
                return run(id,'gun.fire',args)
            end
            function cover(id,value) return run(id,'gun.cover',{mode='ambush',encounterId=convoy.entityId,cover=value}) end
            function tick(dt) Personal.updateGuns(data,convoy,dt,960,720); Personal.updateCover(convoy,dt) end
        ''')

    def test_guest_shot_uses_own_ammo_and_one_shared_target_without_story_progress(self):
        self.ambush()
        self.lua.execute('''
            convoy.cover=true; convoy.coverProgress=1
            local epoch=data.coop.sceneEpoch; local hp=pickup.crew[1].hp; local hostMag=hgun.magazine
            local r=shoot('companion'); assert(r.ok,r.reason); assert(r.durable and writes==1 and r.result.hit)
            assert(guest.ammo['22lr']==8 and host.ammo['22lr']==20 and hgun.magazine==hostMag)
            assert(pickup.crew[1].hp==hp-1 and convoy.shots==1)
            assert(data.scene=='train' and data.location==6 and data.coop.sceneEpoch==epoch)
            assert(saved.trainAmbush.shooterSessions.companion.weaponSession.itemId==ggun.itemId)
            assert(Schema.validate(saved)); local restored=assert(Schema.migrate(saved))
            assert(restored.trainAmbush.shooterSessions.companion.weaponSession.cooldown==ggun.cooldown)
        ''')

    def test_miss_costs_one_round_but_blocked_window_costs_nothing(self):
        self.ambush()
        self.lua.execute('''
            local hp=pickup.crew[1].hp
            local r=shoot('companion',{x=600000}); assert(r.ok and not r.result.hit)
            assert(guest.ammo['22lr']==8 and convoy.shots==1 and pickup.crew[1].hp==hp)
            tick(1); assert(shoot('companion',{x=10000}).reason=='window_blocked')
            assert(guest.ammo['22lr']==8 and convoy.shots==1 and writes==1)
        ''')

    def test_forged_damage_targets_owner_timing_and_coordinates_are_rejected(self):
        self.ambush()
        self.lua.execute('''
            for _,extra in ipairs({{damage=999},{targetId='pickup'},{actorId='host'},{dt=99},
                {x=0/0},{x=-1},{y=1000001},{mode='lastStand'}}) do
                assert(shoot('companion',extra).reason=='invalid_args')
            end
            assert(writes==0 and guest.ammo['22lr']==9 and convoy.shots==0)
        ''')

    def test_foreign_broken_removed_or_changed_weapon_is_rejected(self):
        self.ambush()
        self.lua.execute('''
            assert(shoot('companion',{weaponId=hgun.itemId}).reason=='ownership')
            guest.itemSlots.equipment[2].durability=0; assert(shoot('companion').reason=='weapon_broken')
            guest.itemSlots.equipment[2].durability=100
            Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            local second=guest.itemSlots.inventory[1]
            assert(shoot('companion',{weaponId=second.id}).reason=='weapon_changed')
            Items.write(guest,nil,{kind='equipment',index=2},nil)
            assert(shoot('companion').reason=='ownership' and writes==0 and convoy.shots==0)
        ''')

    def test_cover_and_raise_transition_are_personal(self):
        self.ambush()
        self.lua.execute('''
            assert(cover('companion',true).ok); assert(not convoy.cover)
            assert(shoot('companion').reason=='in_cover'); tick(.2)
            assert(convoy.defenders.companion.coverProgress==1 and convoy.coverProgress==0)
            assert(cover('companion',false).ok); assert(shoot('companion').reason=='in_cover')
            tick(.2); assert(shoot('companion').ok); assert(convoy.playerDamage==0)
        ''')

    def test_host_and_guest_have_independent_cooldowns_and_host_time_advances_both(self):
        self.ambush()
        self.lua.execute('''
            assert(shoot('companion',{x=600000}).ok); assert(shoot('companion').reason=='busy')
            assert(shoot('host',{x=600000}).ok); assert(ggun.cooldown>0 and hgun.cooldown>0)
            tick(1); assert(ggun.cooldown==0 and hgun.cooldown==0)
            assert(shoot('companion',{x=600000}).ok and guest.ammo['22lr']==7 and host.ammo['22lr']==19)
        ''')

    def test_partial_reload_restores_without_refill_or_recharging_ammo(self):
        self.ambush()
        self.lua.execute('''
            guest.ammo['22lr']=20; ggun.magazine=ggun.capacity
            assert(shoot('companion',{x=600000}).ok); tick(1)
            assert(run('companion','gun.reload',ga('companion')).ok); assert(ggun.reloadTimer>0)
            tick(.75); local magazine,timer=ggun.magazine,ggun.reloadTimer
            local copy=assert(Schema.migrate(data)); local own=Players.forActor(copy,'companion')
            local restored=Shooting.new(own,Catalog,copy.trainAmbush,960,720)
            assert(restored.magazine==magazine and restored.reloadTimer==timer)
            assert(own.ammo['22lr']==19 and copy.players.host.ammo['22lr']==20)
        ''')

    def test_switching_exact_guns_keeps_the_previous_cached_magazine_and_cooldown(self):
        self.ambush()
        self.lua.execute('''
            local first=ggun.itemId; assert(shoot('companion',{x=600000}).ok)
            local magazine,cooldown=ggun.magazine,ggun.cooldown
            Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            local second=guest.itemSlots.inventory[1].id
            assert(run('companion','gun.select',ga('companion',{weaponId=second})).ok)
            local owner=convoy.shooterSessions.companion
            assert(owner.weaponSession.itemId==second and owner.weaponSessions[first].itemId==first)
            assert(owner.weaponSessions[first].magazine==magazine and owner.weaponSessions[first].cooldown==cooldown)
            assert(Schema.validate(data))
            assert(run('companion','gun.select',ga('companion',{weaponId=first})).ok)
            assert(owner.weaponSession.itemId==first and owner.weaponSession.magazine==magazine and owner.weaponSession.cooldown==cooldown)
            assert(owner.weaponSessions[second].itemId==second and guest.ammo['22lr']==8 and Schema.validate(data))
        ''')

    def test_ambush_cannot_create_a_loan_or_borrow_another_gun(self):
        self.ambush()
        self.lua.execute('''
            assert(run('companion','gun.select',ga('companion',{weaponId='loan'})).reason=='ownership')
            assert(run('companion','gun.select',ga('companion',{borrowed=true})).reason=='invalid_args')
            assert(not convoy.loanActive and not convoy.shooterSessions.companion.loanActive)
            assert(convoy.shooterSessions.companion.loanAmmo==0 and writes==0)
        ''')

    def test_switching_away_from_a_removed_gun_never_refills_the_other_cached_gun(self):
        self.ambush()
        self.lua.execute('''
            local first=ggun.itemId
            Items.write(guest,nil,{kind='inventory',index=1},'frontier-22-lever-rifle')
            local second=guest.itemSlots.inventory[1].id
            assert(run('companion','gun.select',ga('companion',{weaponId=second})).ok)
            assert(shoot('companion',{x=600000}).ok)
            local owner=convoy.shooterSessions.companion; local magazine=owner.weaponSession.magazine
            local cooldown=owner.weaponSession.cooldown
            assert(run('companion','gun.select',ga('companion',{weaponId=first})).ok)
            Items.write(guest,nil,{kind='equipment',index=2},nil)
            assert(run('companion','gun.select',ga('companion',{weaponId=second})).ok)
            assert(owner.weaponSession.magazine==magazine and owner.weaponSession.cooldown==cooldown)
            assert(guest.ammo['22lr']==8 and owner.weaponSessions[first].itemId==first and Schema.validate(data))
        ''')

    def test_two_final_shots_and_replay_award_one_shared_reward(self):
        self.ambush()
        self.lua.execute('''
            for _,v in ipairs(convoy.vehicles) do for _,c in ipairs(v.crew) do c.hp=0; c.phase='down' end end
            pickup.crew[1].hp=1; pickup.crew[1].phase='aim'
            local scrap=data.scrap
            local hostRequest=assert(service:prepareRequest('host','gun.fire',ga('host',{x=260000,y=350000})))
            local guestRequest=assert(service:prepareRequest('companion','gun.fire',ga('companion',{x=260000,y=350000})))
            local r=service:execute('companion',1,guestRequest); assert(r.ok and r.durable and convoy.outcome=='crew')
            assert(data.scrap==scrap+Ambush.reward and guest.ammo['22lr']==8)
            assert(not service:execute('host',0,hostRequest).ok and host.ammo['22lr']==20)
            assert(service:execute('companion',1,guestRequest).durable and data.scrap==scrap+Ambush.reward)
            local loaded=assert(Schema.migrate(saved)); assert(loaded.scrap==data.scrap and loaded.trainAmbush.reward==Ambush.reward)
        ''')

    def test_failed_save_replay_retry_and_disk_receipt_never_repeat_the_shot(self):
        self.ambush()
        self.lua.execute('''
            local request=assert(service:prepareRequest('companion','gun.fire',ga('companion',{x=260000,y=350000})))
            failSave=true; local r=service:execute('companion',1,request); assert(r.ok and r.savePending)
            local hp=pickup.crew[1].hp
            assert(service:execute('companion',1,request).ok and pickup.crew[1].hp==hp and guest.ammo['22lr']==8)
            assert(cover('host',true).reason=='save_pending'); failSave=false; assert(service:retryCheckpoint())
            assert(service:execute('companion',1,request).durable and guest.ammo['22lr']==8 and convoy.shots==1)
            local oldSession=service.sessionId; local loaded=assert(Schema.migrate(saved))
            local fresh=Authority.new({campaign=loaded,sessionId='ambush-restarted',randomSeed=728431,checkpoint=function() return true end})
            fresh:admit('companion',1)
            local fingerprint=assert(require('game.net.codec').encode(request,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}))
            local receipt=fresh:receipt('companion',1,oldSession,request.requestId,fingerprint)
            assert(receipt.ok and receipt.durable and loaded.players.companion.ammo['22lr']==8)
            assert(fresh:execute('companion',1,request).reason=='wrong_session')
        ''')

    def test_enemy_windups_lock_either_actor_and_use_that_actors_cover(self):
        self.ambush()
        self.lua.execute('''
            convoy.cover=true; convoy.coverProgress=1
            for _,c in ipairs(pickup.crew) do c.phase='hidden'; c.timer=0 end
            Ambush.update(data,convoy,.01,nil,{'host','companion'})
            assert(pickup.crew[1].targetActorId=='host' and pickup.crew[2].targetActorId=='companion')
            for _,c in ipairs(pickup.crew) do c.phase='aim'; c.timer=0 end
            local hostHP,guestHP=host.health,guest.health
            Ambush.update(data,convoy,.01,nil,{'host','companion'})
            assert(host.health==hostHP and guest.health==guestHP-2)
            assert(convoy.playerDamage==0 and convoy.defenders.companion.playerDamage==2 and convoy.trainDamage==2)
            assert(Schema.validate(data)); local copy=assert(Schema.migrate(data))
            assert(copy.trainAmbush.vehicles[3].crew[2].targetActorId=='companion')
        ''')

    def test_disconnected_locked_target_does_not_redirect_damage_to_host(self):
        self.ambush()
        self.lua.execute('''
            pickup.crew[1].targetActorId='companion'; pickup.crew[1].phase='aim'; pickup.crew[1].timer=0
            local hostHP,guestHP=host.health,guest.health
            Ambush.update(data,convoy,.01,nil,{'host'})
            assert(host.health==hostHP and guest.health==guestHP and convoy.trainDamage==1)
        ''')

    def test_malformed_personal_cover_damage_and_windup_owners_are_rejected(self):
        self.ambush()
        self.lua.execute('''
            for _,edit in ipairs({function(s) s.defenders.evil={} end,
                function(s) s.defenders.companion.coverProgress=2 end,
                function(s) s.defenders.companion.playerDamage=-1 end,
                function(s) s.defenders.companion.coverProgress=0/0 end,
                function(s) s.defenders.companion.aimX=50 end,
                function(s) s.vehicles[3].crew[1].targetActorId='evil' end,
                function(s) s.lastTargetActorId='evil' end,
                function(s) s.vehicles=false end,
                function(s) s.vehicles[3].crew=false end,
                function(s) s.vehicles[3].crew[1]=false end}) do
                local copy=assert(Schema.copy(data)); edit(copy.trainAmbush); assert(not Schema.validate(copy))
            end
        ''')

    def test_projection_preserves_owned_combat_facts_and_omits_private_aim(self):
        self.ambush()
        self.lua.execute('''
            assert(cover('companion',true).ok); ggun.aimX=222; ggun.ads=true
            local Net=require('game.net.game_state'); local producer=Net.producer()
            local packet=assert(producer:capture(data,true)); local replica=Net.replica(); assert(replica:apply(packet))
            local s=replica.data.trainAmbush; assert(s.defenders.companion.cover and not s.cover)
            assert(s.shooterSessions.companion.weaponSession.itemId==ggun.itemId)
            assert(not s.shooterSessions.companion.weaponSession.aimX and not Schema.validate(replica.data))
        ''')

    def test_loans_are_reclaimed_for_both_actors_without_losing_owned_sessions(self):
        self.ambush()
        self.lua.execute('''
            local h=Shooting.useLoan(hgun,host,Catalog,convoy); local g=Shooting.useLoan(ggun,guest,Catalog,convoy)
            assert(h.borrowed and g.borrowed and convoy.loanAmmo==48 and convoy.shooterSessions.companion.loanAmmo==48)
            local owner=convoy.shooterSessions.companion; local owned=owner.weaponSessions[ggun.itemId]
            Sessions.reclaim(convoy)
            assert(not convoy.weaponSession and not owner.weaponSession and not owner.weaponSessions.loan)
            assert(not convoy.loanActive and not owner.loanActive and convoy.loanAmmo==0 and owner.loanAmmo==0)
            assert(owner.weaponSessions[ggun.itemId]==owned and guest.ammo['22lr']==9 and host.ammo['22lr']==20)
            Sessions.reset(convoy); assert(not convoy.weaponSessions and not owner.weaponSessions and Schema.validate(data))
        ''')

    def test_old_prepared_shot_conflicts_with_another_actors_committed_hit(self):
        self.ambush()
        self.lua.execute('''
            local old=assert(service:prepareRequest('host','gun.fire',ga('host',{x=600000,y=350000})))
            assert(shoot('companion',{x=600000}).ok)
            assert(service:execute('host',0,old).reason=='stale_revision' and host.ammo['22lr']==20)
            assert(shoot('host',{x=600000}).ok and convoy.shots==2)
        ''')

    def test_encounter_identity_and_host_progression_are_enforced(self):
        self.ambush()
        self.lua.execute('''
            local old=ga('companion',{x=600000,y=350000}); convoy.active=false
            local new=Ambush.start(data); assert(new.entityId~=old.encounterId)
            new.phase='combat'; ready.encounterId=new.entityId
            assert(run('companion','gun.fire',old).reason=='shooter_unavailable')
            for _,name in ipairs({'ambush.start','ambush.continue','ambush.retry','ambush.withdraw','lastStand.advance'}) do
                assert(run('companion',name,{}).reason=='host_only')
            end
        ''')

    def test_approach_allows_personal_setup_but_paused_or_wrong_scene_rejects_actions(self):
        self.ambush()
        self.lua.execute('''
            convoy.phase='approach'; assert(cover('companion',true).ok); assert(shoot('companion').reason=='shooter_unavailable')
            convoy.phase='combat'; ready.paused=true; assert(cover('companion',false).reason=='shooter_unavailable')
            ready.paused=false; states.companion.scene='stop'; assert(cover('companion',false).reason=='shooter_unavailable')
            states.companion.scene='train'; guest.health=1; assert(cover('companion',false).reason=='shooter_unavailable')
        ''')

    def test_target_failure_rolls_back_ammo_magazine_and_all_shared_changes(self):
        self.ambush()
        self.lua.execute('''
            crashTarget=true; local magazine=ggun.magazine; local revision=data.coop.revision
            assert(shoot('companion').reason=='handler_error')
            assert(guest.ammo['22lr']==9 and ggun.magazine==magazine and convoy.shots==0 and writes==0 and data.coop.revision==revision)
        ''')

    def test_actual_host_input_uses_the_same_authority_commands(self):
        self.ambush()
        self.lua.execute('''
            require('game.coop_ambush_progression').install(service,ctx)
            local scene=require('game.train_ambush_scene'); scene.pointOpen=ctx.ambushOpen; scene.target=ctx.ambushTarget
            local runtime={state='game',saveData=data}; local input; local calls={}
            input=require('game.train_ambush').new({runtime=runtime,catalog=Catalog,width=960,height=720,
                controlBindings={},writeSave=function() end,enterStop=function() error('unexpected progression') end,
                submit=function(name,args) calls[#calls+1]=name; return service:submitLocal(name,args) end})
            ctx.ambushState=function() return input:commandState() end
            input:mousemoved(250,250,0,0,false); input:keypressed('space',nil,false); input:keyreleased('space')
            assert(calls[1]=='ambush.start' and calls[2]=='gun.fire' and host.ammo['22lr']==19 and guest.ammo['22lr']==9)
            input:keypressed('c',nil,false); assert(calls[3]=='gun.cover' and convoy.cover and not convoy.defenders.companion.cover)
            assert(writes==3 and Schema.validate(data))
        ''')


if __name__ == '__main__':
    unittest.main()
