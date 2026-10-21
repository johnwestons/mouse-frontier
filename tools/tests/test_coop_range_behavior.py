"""Independent range lanes using real rules, host clocks and durable authority."""
import unittest
import test_coop_battles_behavior as tactical


class RangeCommandTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def range(self):
        self.lua.execute('''
            setup(); data.scene='stop'; data.stopped=true; data.tacticalBattle=nil
            Range=require('game.shooting_range'); RangeState=require('game.coop_range_state')
            RangeCommands=require('game.coop_range'); Results=require('game.net.item_results')
            layout={x=0,y=0}; data.stopLayouts['2']=layout
            spot=assert(Range.ensure(layout,2)); assert(Entities.ensure(data)); clock=0
            host.ammo['22lr']=120; guest.ammo['22lr']=120
            states={host={screen='game',scene='stop',x=spot.x,y=spot.y},
                companion={screen='game',scene='stop',x=spot.x,y=spot.y,movementReady=true}}
            readiness={host={active=true,ready=true,paused=false},companion={active=true,ready=true,paused=false}}
            ctx={catalog=Catalog,rangeRandomSeed=728431,actorState=function(id) return states[id] end,
                rangeState=function(id) return readiness[id] end}
            service.clock=function() return clock end
            RangeCommands.install(service,ctx); writes=0
            leases={}
            function lane(id) return assert(RangeState.session(data,id)) end
            function request(id,name,extra)
                local s=RangeState.session(data,id)
                local a=name=='range.acquire' and {spotId=spot.entityId} or name=='range.release' and {leaseId=leases[id]}
                    or {leaseId=leases[id],roundRevision=s.roundRevision}
                if name=='range.fire' or name=='range.ammo' or name=='range.reload' then a.weaponId=s.itemId end
                for k,v in pairs(extra or {}) do a[k]=v end
                return a
            end
            function rangeRun(id,name,extra)
                local reply=run(id,name,request(id,name,extra))
                if reply.ok then
                    assert(reply.durable and Schema.validate(data),name..' not durable/valid')
                    local projected=assert(Results.project(name,reply.result)); assert(Results.valid(name,projected),name..' invalid wire result')
                    if name=='range.acquire' then leases[id]=reply.result.leaseId end
                end
                return reply
            end
            function acquire(id) return rangeRun(id,'range.acquire') end
            function config(id,action,extra)
                extra=extra or {}; extra.action=action; return rangeRun(id,'range.configure',extra)
            end
            function advance(seconds)
                local steps=math.ceil(seconds/.08); for _=1,steps do
                    local dt=seconds/steps; clock=clock+dt
                    RangeCommands.advance(data,service.activityState,service.bindings,clock,ctx,dt)
                    assert(RangeState.validate(data),'host tick corrupted saved lane')
                end
            end
            function shootTarget(id)
                local t=lane(id).targets[1]; assert(t)
                return rangeRun(id,'range.fire',{x=math.floor(t.x/960*1000000+.5),y=math.floor(t.y/720*1000000+.5)})
            end
            assert(acquire('host').ok); assert(acquire('companion').ok)
        ''')

    def test_two_independent_lanes_and_own_revision_scopes(self):
        self.range()
        self.lua.execute('''
            assert(leases.host~=leases.companion and lane('host')~=lane('companion'))
            local hs=RangeState.scopes(data,'host',spot.entityId,'range.fire',{})
            local gs=RangeState.scopes(data,'companion',spot.entityId,'range.fire',{})
            assert(#hs==2 and hs[1]~=gs[1] and hs[2]~=gs[2])
            assert(config('host','start').ok and config('companion','start').ok)
            advance(.2); local guestScore=lane('companion').score; local guestMag=lane('companion').loaded
            local r=shootTarget('host'); assert(r.ok and r.result.hit)
            assert(lane('companion').score==guestScore and lane('companion').loaded==guestMag)
            assert(host.ammo['22lr']==119 and guest.ammo['22lr']==120)
        ''')

    def test_host_private_pause_does_not_pause_guest_lane(self):
        self.range()
        self.lua.execute('''
            assert(config('host','start').ok and config('companion','start').ok)
            readiness.host.paused=true; advance(2)
            assert(lane('host').clock==0 and lane('companion').clock>1.9)
            assert(shootTarget('companion').ok)
            assert(config('host','mode').reason=='range_not_ready')
        ''')

    def test_guest_range_continues_when_host_visits_another_scene(self):
        self.range()
        self.lua.execute('''
            assert(config('host','start').ok and config('companion','start').ok)
            require('game.coop_presence').ensure(data)
            Players.forActor(data,'companion').scene='stop'
            data.scene='house'; data.activeHouseDoor=1; states.host.scene='house'
            advance(.4)
            assert(lane('companion').clock>.39 and lane('host').clock==0)
            assert(RangeCommands.view(data,service.activityState,service.bindings,clock,'companion',ctx))
            assert(shootTarget('companion').ok and lane('companion').hits==1)
            data.scene='train'; states.host.scene='train'; advance(.4)
            assert(lane('companion').clock>.79 and lane('host').clock==0)
            assert(config('companion','pause',{paused=true}).ok)
            local stopped=lane('companion').clock; advance(.3)
            assert(lane('companion').clock==stopped)
            assert(config('companion','pause',{paused=false}).ok)
            data.scene='stop'; states.host.scene='stop'
            Players.forActor(data,'companion').scene='train'; states.companion.scene='train'
            advance(.4)
            assert(lane('companion').clock==stopped and lane('host').clock>.39)
            assert(rangeRun('companion','range.fire',{x=0,y=0}).reason=='range_unavailable')
        ''')

    def test_forged_score_time_damage_actor_and_target_claims_rejected(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2); local ammo=guest.ammo['22lr']; writes=0
            for _,extra in ipairs({{score=999},{dt=99},{time=0},{targetId='e9'},{hit=true},{actorId='host'},
                {x=0/0,y=1},{x=-1,y=1},{x=1000001,y=1}}) do
                assert(rangeRun('companion','range.fire',extra).reason=='invalid_args')
            end
            assert(guest.ammo['22lr']==ammo and writes==0)
            assert(config('companion','complete').reason=='round_not_complete')
        ''')

    def test_proximity_living_scene_ack_and_competing_activity_required(self):
        self.range()
        self.lua.execute('''
            assert(rangeRun('companion','range.release').ok)
            states.companion.x=spot.x+67; assert(acquire('companion').reason=='range_distance')
            states.companion.x=spot.x; states.companion.movementReady=false
            assert(acquire('companion').reason=='range_unavailable'); states.companion.movementReady=true
            states.companion.activityBlocked=true; states.companion.activeActivity='sewing'
            assert(acquire('companion').reason=='range_unavailable'); states.companion.activityBlocked=false
            guest.health=0; assert(acquire('companion').reason=='range_unavailable'); guest.health=20
            data.scene='train'; assert(acquire('companion').reason=='range_unavailable')
        ''')

    def test_foreign_removed_and_broken_firearms_cannot_fire(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2)
            assert(rangeRun('companion','range.fire',{weaponId=lane('host').itemId,x=1,y=1}).reason=='ownership')
            local item=Items.owned(guest,lane('companion').itemId); item.durability=0
            assert(shootTarget('companion').reason=='weapon_broken'); item.durability=100
            Items.write(guest,nil,{kind='equipment',index=2},'frontier-short-sword')
            assert(shootTarget('companion').reason=='ownership')
        ''')

    def test_setup_replay_release_and_reacquire_preserve_magazine_cooldown(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2); assert(shootTarget('companion').ok)
            local s=lane('companion'); local mag=s.loaded; local cooldown=s.cooldown; local gun=s.itemId
            assert(config('companion','setup').ok and s.loaded==mag and s.cooldown==cooldown)
            assert(config('companion','start').ok and s.loaded==mag and s.cooldown==cooldown)
            assert(rangeRun('companion','range.release').ok)
            local oldClock=s.clock; advance(2); assert(s.clock==oldClock)
            assert(acquire('companion').ok and s.loaded==mag and s.cooldown==cooldown and s.itemId==gun)
            assert(not s.fireHeld and not s.aimX and not s.spot and not s.npc)
        ''')

    def test_failed_save_replay_charges_one_shot_and_blocks_other_lane(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2)
            local t=lane('companion').targets[1]
            local args=request('companion','range.fire',{x=math.floor(t.x/960*1000000+.5),y=math.floor(t.y/720*1000000+.5)})
            local req=assert(service:prepareRequest('companion','range.fire',args))
            failSave=true; local reply=service:execute('companion',1,req)
            assert(reply.ok and reply.savePending and guest.ammo['22lr']==119)
            assert(service:execute('companion',1,req).savePending and guest.ammo['22lr']==119)
            assert(config('host','start').reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint())
            local recovered=service:execute('companion',1,req); assert(recovered.ok and recovered.durable and guest.ammo['22lr']==119)
        ''')

    def test_reload_and_restart_preserve_exact_partial_state_and_need_fresh_lease(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2); assert(shootTarget('companion').ok); advance(.5)
            assert(rangeRun('companion','range.reload').ok); advance(.2)
            local prior=assert(Schema.copy(data)); local old=lane('companion'); local oldLease=leases.companion
            local mag,timer,gun=old.loaded,old.reloadTimer,old.itemId; assert(timer>0)
            data=assert(Schema.migrate(prior)); host=Players.forActor(data,'host'); guest=Players.forActor(data,'companion')
            spot=data.stopLayouts['2'].shootingRange
            service=Authority.new({campaign=data,sessionId='range-restart',randomSeed=728431,clock=function() return clock end,
                checkpoint=function(value) saved=assert(Schema.copy(value)); return true end})
            RangeCommands.install(service,ctx); service:admit('companion',1)
            assert(rangeRun('companion','range.reload').reason=='lease_expired')
            assert(acquire('companion').ok); local s=lane('companion')
            assert(s.loaded==mag and s.reloadTimer==timer and s.itemId==gun and s.weaponSessions[gun].reloadTimer==timer)
            readiness.companion.ready=false; advance(1); assert(s.reloadTimer==timer)
            readiness.companion.ready=true; advance(timer+.1); assert(s.reloadTimer==0 and s.loaded>mag)
        ''')

    def test_expiry_disconnect_generation_and_scene_invalidate_only_lease(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2)
            local s=lane('companion'); local oldClock=s.clock
            readiness.companion.ready=false; clock=clock+31; advance(.1)
            assert(s.clock==oldClock and config('companion','setup').reason=='lease_expired')
            readiness.companion.ready=true; assert(acquire('companion').ok)
            service:disconnect('companion',1); advance(1); assert(s.clock==oldClock)
            service:admit('companion',2); assert(acquire('host').ok)
            local req=assert(service:prepareRequest('companion','range.acquire',{spotId=spot.entityId}))
            local reply=service:execute('companion',2,req); assert(reply.ok)
            leases.companion=reply.result.leaseId; assert(s.clock==oldClock)
            data.coop.sceneEpoch=data.coop.sceneEpoch+1
            assert(not RangeCommands.occupied(data,service.activityState,service.bindings,clock,'companion',ctx))
        ''')

    def test_ammo_purchase_once_and_only_own_caliber_receives_bundle(self):
        self.range()
        self.lua.execute('''
            local scrap=data.scrap; local req=assert(service:prepareRequest('companion','range.ammo',request('companion','range.ammo')))
            local r=service:execute('companion',1,req); assert(r.ok and r.result.purchasedRounds==18 and r.result.cost==3)
            assert(guest.ammo['22lr']==138 and host.ammo['22lr']==120 and data.scrap==scrap-3)
            assert(service:execute('companion',1,req).ok and guest.ammo['22lr']==138 and data.scrap==scrap-3)
            assert(Results.valid('range.ammo',assert(Results.project('range.ammo',r.result))))
        ''')

    def test_shared_reward_increment_and_replayed_completion_are_once_only(self):
        self.range()
        self.lua.execute('''
            local goodwill=data.goodwill
            assert(config('host','start').ok and config('companion','start').ok); advance(.2)
            assert(shootTarget('host').ok); assert(shootTarget('companion').ok)
            advance(45); assert(lane('host').time==0 and lane('companion').time==0)
            local r=config('host','complete'); assert(r.ok and r.result.gained==1 and r.result.completed)
            assert(data.goodwill==goodwill+1 and spot.rewardTier==1)
            assert(config('host','complete').ok and data.goodwill==goodwill+1)
            local g=config('companion','complete'); assert(g.ok and g.result.gained==0 and data.goodwill==goodwill+1)
            assert(spot.highScores['frontier-22-lever-rifle']==math.max(lane('host').score,lane('companion').score)
                and spot.highScores['frontier-22-lever-rifle']>=124)
        ''')

    def test_corruption_infinity_duplicate_targets_and_private_fields_rejected(self):
        self.range()
        self.lua.execute('''
            local before=assert(Schema.copy(data)); local s=lane('companion')
            s.aimX=1; assert(not RangeState.validate(data)); s.aimX=nil
            s.loaded=math.huge; assert(not RangeState.validate(data)); s.loaded=12
            s.weaponSessions[s.itemId].itemId=lane('host').itemId; assert(not RangeState.validate(data))
            data=before; assert(RangeState.validate(data))
        ''')

    def test_boomerang_return_is_saved_finite_and_no_ammunition_reply_field(self):
        self.range()
        self.lua.execute('''
            Items.write(guest,nil,{kind='equipment',index=2},'scrap-boomerang')
            assert(config('companion','change',{kind='weapon',direction=1}).ok)
            assert(config('companion','start').ok); advance(.2)
            local r=shootTarget('companion'); assert(r.ok and r.result.rounds==nil)
            local s=lane('companion'); assert(s.loaded==0 and s.weaponViewSequence)
            local index=s.weaponViewSequence.index; local elapsed=s.weaponViewSequence.elapsed
            assert(rangeRun('companion','range.release').ok and acquire('companion').ok)
            assert(s.loaded==0 and s.weaponViewSequence.index==index and s.weaponViewSequence.elapsed==elapsed)
            local oldShots=s.shots; assert(not shootTarget('companion').ok and s.shots==oldShots)
            advance(2); assert(s.loaded==1 and not s.weaponViewSequence)
            assert(shootTarget('companion').ok and s.shots==oldShots+1)
        ''')

    def test_shotgun_multiple_targets_accuracy_above_one_projects_and_saves(self):
        self.range()
        self.lua.execute('''
            Items.write(guest,nil,{kind='equipment',index=2},'frontier-12g-pump-shotgun'); guest.ammo['12-gauge']=20
            assert(config('companion','change',{kind='weapon',direction=1}).ok)
            assert(config('companion','start').ok); advance(2)
            local s=lane('companion'); assert(#s.targets>=2)
            -- Controlled geometric overlap tests the original seven-pellet
            -- scorer, not a claimed client hit count or edited result.
            local first=s.targets[1]; local center=first.x
            first.x=center-6; s.targets[2].x=center+6; s.targets[2].y=first.y
            for i=3,#s.targets do s.targets[i].x=850; s.targets[i].y=200 end
            local r=rangeRun('companion','range.fire',{x=math.floor(center/960*1000000+.5),y=math.floor(first.y/720*1000000+.5)})
            assert(r.ok and s.hits>=2 and s.shots==1 and guest.ammo['12-gauge']==19)
            advance(45); local done=config('companion','complete')
            assert(done.ok and done.result.accuracy>1 and Schema.validate(saved))
        ''')

    def test_shared_tier_one_to_three_only_pays_incremental_goodwill(self):
        self.range()
        self.lua.execute('''
            local goodwill=data.goodwill
            assert(config('host','start').ok); advance(.2); assert(shootTarget('host').ok); advance(45)
            assert(config('host','complete').result.gained==1 and data.goodwill==goodwill+1)
            assert(config('companion','change',{kind='pattern',direction=1}).ok)
            assert(config('companion','start').ok)
            for _=1,120 do
                advance(.4); local s=lane('companion')
                if s.hits<10 and s.cooldown<=0 and s.reloadTimer<=0 then
                    for _,t in ipairs(s.targets) do if not t.hit then
                        assert(rangeRun('companion','range.fire',{x=math.floor(t.x/960*1000000+.5),y=math.floor(t.y/720*1000000+.5)}).ok); break
                    end end
                end
            end
            local r=config('companion','complete'); assert(r.ok and r.result.earnedRewardTier==3 and r.result.gained==2)
            assert(spot.rewardTier==3 and data.goodwill==goodwill+3)
            assert(config('companion','complete').ok and data.goodwill==goodwill+3)
            assert(#data.helpHistory==2)
        ''')

    def test_missing_selected_weapon_can_reopen_setup_without_using_foreign_cache(self):
        self.range()
        self.lua.execute('''
            assert(rangeRun('companion','range.release').ok)
            Items.write(guest,nil,{kind='equipment',index=2},'hunting-bow'); guest.ammo.arrows=4
            assert(acquire('companion').ok)
            assert(config('companion','start').reason=='weapon_unavailable')
            assert(config('companion','change',{kind='weapon',direction=1}).ok)
            assert(lane('companion').weapon=='hunting-bow' and config('companion','start').ok)
        ''')

    def test_round_identity_changes_on_transitions_but_not_timing_or_fire(self):
        self.range()
        self.lua.execute('''
            local first=lane('companion').roundRevision
            assert(config('companion','change',{kind='length',direction=1}).ok)
            assert(lane('companion').roundRevision==first+1)
            assert(config('companion','start').ok); local active=lane('companion').roundRevision
            advance(.2); assert(shootTarget('companion').ok and lane('companion').roundRevision==active)
            assert(config('companion','setup').ok and lane('companion').roundRevision==active+1)
            assert(rangeRun('companion','range.fire',{roundRevision=active,x=1,y=1}).reason=='stale_round')
        ''')

    def test_pause_is_independent_checked_and_ephemeral_with_durable_resume(self):
        self.range()
        self.lua.execute('''
            assert(config('host','start').ok and config('companion','start').ok); advance(.2)
            local s=lane('host'); local timer=s.time; local revision=s.roundRevision
            local p=config('host','pause',{paused=true}); assert(p.ok and p.result.paused==true)
            advance(35); assert(s.time==timer and lane('companion').clock>35)
            assert(RangeCommands.view(data,service.activityState,service.bindings,clock,'host',ctx).paused==true)
            assert(shootTarget('host').reason=='range_paused' and config('host','setup').reason=='range_paused')
            assert(s.roundRevision==revision and s.paused==nil and saved.rangeSessions.host.paused==nil)
            assert(acquire('host').result.paused==true)
            readiness.host.paused=true
            assert(config('host','pause',{paused=false}).ok)
            readiness.host.paused=false; advance(.4); assert(s.time<timer and s.roundRevision==revision)
        ''')

    def test_pause_spoofed_owner_state_and_unacknowledged_resume_rejected(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','pause',{paused=true}).ok)
            for _,extra in ipairs({{paused=1},{paused='false'},{paused=true,actorId='host'},
                {paused=true,score=9},{paused=true,npc='claimed.png'}}) do
                assert(config('companion','pause',extra).reason=='invalid_args')
            end
            assert(config('companion','pause',{paused=false,leaseId=leases.host}).reason=='lease_owner')
            assert(config('companion','change',{kind='motion',direction=1,paused=false}).reason=='invalid_args')
            states.companion.movementReady=false
            assert(config('companion','pause',{paused=false}).reason=='range_unavailable')
            states.companion.movementReady=true; readiness.companion.ready=false
            assert(config('companion','pause',{paused=false}).reason=='range_not_ready')
            readiness.companion.ready=true; assert(config('companion','pause',{paused=false}).ok)
            lane('companion').paused=true; assert(not RangeState.validate(data)); lane('companion').paused=nil
        ''')

    def test_paused_lane_rejoin_retains_round_and_weapon_but_discards_pause(self):
        self.range()
        self.lua.execute('''
            assert(config('companion','start').ok); advance(.2); assert(shootTarget('companion').ok)
            assert(config('companion','pause',{paused=true}).ok)
            local s=lane('companion'); local timer,mag,cooldown=s.time,s.loaded,s.cooldown
            service:disconnect('companion',1); advance(3)
            assert(s.time==timer and s.loaded==mag and s.cooldown==cooldown)
            service:admit('companion',2)
            local req=assert(service:prepareRequest('companion','range.acquire',{spotId=spot.entityId}))
            local r=service:execute('companion',2,req); assert(r.ok and r.durable and r.result.paused==false)
            assert(Results.valid('range.acquire',assert(Results.project('range.acquire',r.result))))
            assert(s.time==timer and s.loaded==mag and s.cooldown==cooldown)
            assert(not RangeCommands.view(data,service.activityState,service.bindings,clock,'companion',ctx).paused)
        ''')

    def test_trusted_resident_receives_original_incremental_relationship_help(self):
        self.range()
        self.lua.execute('''
            layout.npcOutside='trusted-outside.png'; layout.npc='fallback-resident.png'; data.currentNPC='stale-house.png'
            local goodwill=data.goodwill
            assert(config('host','start').ok); advance(.2); assert(shootTarget('host').ok); advance(45)
            assert(config('host','complete').result.gained==1)
            local relationship=data.relationships['trusted-outside.png']
            assert(relationship.goodwillEarned==1 and relationship.helpCount==1 and data.goodwill==goodwill+1)
            assert(data.helpHistory[1].npc=='trusted-outside.png' and not data.relationships['stale-house.png'])
            assert(config('companion','change',{kind='pattern',direction=1}).ok and config('companion','start').ok)
            for _=1,120 do
                advance(.4); local s=lane('companion')
                if s.hits<10 and s.cooldown<=0 then for _,t in ipairs(s.targets) do if not t.hit then
                    assert(rangeRun('companion','range.fire',{x=math.floor(t.x/960*1000000+.5),y=math.floor(t.y/720*1000000+.5)}).ok); break
                end end end
            end
            local r=config('companion','complete'); assert(r.ok and r.result.gained==2)
            assert(relationship.goodwillEarned==3 and relationship.helpCount==2 and data.goodwill==goodwill+3)
            assert(#data.helpHistory==2 and data.helpHistory[2].npc=='trusted-outside.png')
            assert(config('companion','complete').ok and relationship.goodwillEarned==3 and relationship.helpCount==2)
            assert(config('host','complete',{npc='claimed.png'}).reason=='invalid_args')
        ''')

    def test_completion_failed_save_replay_does_not_repeat_reward_or_relationship(self):
        self.range()
        self.lua.execute('''
            layout.npcOutside='trusted-resident.png'
            assert(config('companion','start').ok); advance(.2); assert(shootTarget('companion').ok); advance(45)
            local goodwill=data.goodwill; local args=request('companion','range.configure',{action='complete'})
            local req=assert(service:prepareRequest('companion','range.configure',args))
            failSave=true; local r=service:execute('companion',1,req)
            assert(r.ok and r.savePending and not r.durable and data.goodwill==goodwill+1)
            assert(data.relationships['trusted-resident.png'].goodwillEarned==1 and #data.helpHistory==1)
            assert(service:execute('companion',1,req).savePending and data.goodwill==goodwill+1)
            assert(config('host','start').reason=='save_pending')
            failSave=false; assert(service:retryCheckpoint())
            local done=service:execute('companion',1,req); assert(done.ok and done.durable)
            assert(Results.valid('range.configure',assert(Results.project('range.configure',done.result))))
            assert(saved.goodwill==goodwill+1 and saved.relationships['trusted-resident.png'].helpCount==1 and #saved.helpHistory==1)
            assert(config('companion','complete').ok and data.goodwill==goodwill+1 and #data.helpHistory==1)
        ''')

    def test_story_offer_sweep_frees_range_locks_without_changing_saved_lanes(self):
        self.range()
        self.lua.execute('''
            local Leases=require('game.coop_leases'); local Life=require('game.coop_last_stand_lifecycle')
            local Codec=require('game.net.codec'); local limits={maxBytes=65536,maxDepth=16,maxEntries=4096,maxStringBytes=256}
            assert(config('host','start').ok and config('companion','start').ok); advance(.2)
            assert(shootTarget('companion').ok); advance(.5); assert(rangeRun('companion','range.reload').ok); advance(.2)
            local before=assert(Codec.encode(data.rangeSessions,limits))
            local epoch=data.coop.sceneEpoch; local now=clock; local serial=service.activityState.nextId
            assert(Leases.acquire(service.activityState,'test:aid','companion',1,epoch,now,{kind='lastStandAid'})==nil)
            service:sweepActivities()
            assert(service.activityState.resources[RangeState.resource(spot.entityId,'host')])
            assert(service.activityState.resources[RangeState.resource(spot.entityId,'companion')])
            data.lastStand={state='waiting',originStop=data.location}; Life.ensure(data); assert(Life.move(data.lastStand,'offer'))
            assert(Life.key(data) and data.coop.sceneEpoch==epoch)
            service:sweepActivities()
            assert(not service.activityState.resources[RangeState.resource(spot.entityId,'host')])
            assert(not service.activityState.resources[RangeState.resource(spot.entityId,'companion')])
            assert(service.activityState.nextId==serial and assert(Codec.encode(data.rangeSessions,limits))==before)
            assert(Leases.acquire(service.activityState,'test:aid','companion',1,epoch,now,
                {kind='lastStandAid',modalDomain=Life.key(data)}))
            assert(Leases.acquire(service.activityState,'test:supply','host',0,epoch,now,
                {kind='lastStandSupply',modalDomain=Life.key(data)}))
            service:sweepActivities()
            assert(service.activityState.resources['test:aid'] and service.activityState.resources['test:supply'])
            assert(not RangeCommands.occupied(data,service.activityState,service.bindings,now,'companion',ctx))
            advance(2); assert(assert(Codec.encode(data.rangeSessions,limits))==before)
            local restored=assert(Schema.migrate(assert(Schema.copy(data))))
            assert(RangeState.validate(restored) and assert(Codec.encode(restored.rangeSessions,limits))==before)
            assert(restored.rangeSessions.companion.loaded==lane('companion').loaded
                and restored.rangeSessions.companion.reloadTimer==lane('companion').reloadTimer)
        ''')


if __name__ == '__main__':
    unittest.main()
