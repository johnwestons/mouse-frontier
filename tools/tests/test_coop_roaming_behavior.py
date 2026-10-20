"""Owned field swings, cooldowns, host RNG, durable receipts and boss limits."""
import unittest
import test_coop_battles_behavior as tactical


class RoamingCommandTests(unittest.TestCase):
    setUp = tactical.TacticalCommandTests.setUp

    def field(self):
        self.lua.execute('''
            setup(); Areas=require('game.expedition_areas'); Field=require('game.coop_roaming')
            Cue=require('game.roaming_combat_state'); Roaming=require('game.roaming_mobs')
            data.location=6; data.scene='expedition'; data.activeExpeditionArea=Areas.SURFACE_ID
            Areas.ensure(data); assert(Entities.ensure(data))
            area=data.expeditions[Areas.SURFACE_ID]; a=area.mobs['surface-bandit-a']; z=area.mobs['surface-bandit-b']
            a.x,a.y=700,600; z.x,z.y=1200,600; a.hp=100; a.maxHp=100
            Items.write(host,nil,{kind='equipment',index=1},'frontier-short-sword')
            Items.write(guest,nil,{kind='equipment',index=1},'frontier-short-sword')
            states={host={screen='game',scene='expedition',x=700,y=630,facing=1},
                companion={screen='game',scene='expedition',x=700,y=625,facing=1}}
            clock=10; visual=Roaming.new()
            service=Authority.new({campaign=data,sessionId='field',randomSeed=728431,clock=function() return clock end,
                checkpoint=function(value) writes=writes+1; if failSave then return false end; saved=assert(Schema.copy(value)); return true end})
            Field.install(service,{catalog=Catalog,actorState=function(id) return states[id] end,fieldState=function() return visual end})
            service:admit('companion',1); writes=0
            function fieldArgs(id,extra)
                local value={areaId=data.activeExpeditionArea,weaponId=Players.get(data,id).itemSlots.equipment[1].id,targetX=a.x,targetY=a.y}
                for key,v in pairs(extra or {}) do value[key]=v end
                return value
            end
            function swing(id,extra) return run(id,'roaming.attack',fieldArgs(id,extra)) end
        ''')

    def test_unarmed_host_and_guest_use_saved_cues_without_item_wear(self):
        self.field()
        self.lua.execute('''
            for _,id in ipairs({'host','companion'}) do
                local actor=Players.get(data,id)
                actor.itemSlots.equipment[1].durability=0
                assert(Field.weapon(data,id,Catalog)=='scratch')
                local hp=a.hp;local result=swing(id,{weaponId='scratch'})
                assert(result.ok,result.reason)
                local cue=data.roamingCombat.actors[id]
                assert(cue.weapon=='scratch' and cue.damage>0 and a.hp<hp and Cue.validate(data))
                assert(actor.itemSlots.equipment[1].durability==0)
                assert(swing(id,{weaponId='scratch'}).reason=='attack_cooldown')
            end
            assert(Schema.copy(saved))
        ''')

    def test_guest_swing_owns_costs_rng_and_cue_without_story_change(self):
        self.field()
        self.lua.execute('''
            local hostItem=host.itemSlots.equipment[1]; local guestItem=guest.itemSlots.equipment[1]
            local hp=a.hp; local epoch=data.coop.sceneEpoch; local hostUses=host.weaponProficiency.melee or 0
            local result=swing('companion'); assert(result.ok,result.reason); assert(result.durable and writes==1)
            assert(a.hp<hp and guestItem.durability==99 and hostItem.durability==100)
            assert((host.weaponProficiency.melee or 0)==hostUses and data.coop.randomState)
            assert(data.scene=='expedition' and data.coop.sceneEpoch==epoch and not data.tacticalBattle)
            assert(saved.roamingCombat.actors.companion.hitId==a.entityId and Cue.validate(data) and Schema.validate(saved))
            assert(result.result.actorId=='companion' and result.result.x==states.companion.x)
            assert(result.result.damage>=Catalog.weaponStats['frontier-short-sword'].min and result.result.damage<=Catalog.weaponStats['frontier-short-sword'].max)
        ''')

    def test_miss_wears_owned_weapon_and_other_actor_has_independent_cooldown(self):
        self.field()
        self.lua.execute('''
            local hp=a.hp; local r=swing('companion',{targetX=900,targetY=625}); assert(r.ok,r.reason)
            assert(r.result.damage==0 and a.hp==hp and guest.itemSlots.equipment[1].durability==99)
            assert(swing('companion').reason=='attack_cooldown'); assert(swing('host').ok)
            clock=clock+r.result.duration; assert(swing('companion').ok)
        ''')

    def test_ownership_malformed_claims_broken_guns_and_stale_area_are_rejected(self):
        self.field()
        self.lua.execute('''
            assert(swing('companion',{weaponId=host.itemSlots.equipment[1].id}).reason=='ownership')
            assert(swing('companion',{damage=9999}).reason=='invalid_args')
            assert(swing('companion',{x=700}).reason=='invalid_args')
            assert(swing('companion',{targetX=0/0}).reason=='invalid_args')
            assert(swing('companion',{areaId='wrong'}).reason=='field_unavailable')
            assert(swing('companion',{weaponId=guest.itemSlots.equipment[2].id}).reason=='melee_required')
            guest.itemSlots.equipment[1].durability=0
            assert(swing('companion').reason=='weapon_broken' and writes==0 and a.hp==100)
        ''')

    def test_duplicate_item_names_use_exact_selected_instance(self):
        self.field()
        self.lua.execute('''
            Items.write(guest,nil,{kind='equipment',index=2},'frontier-short-sword')
            local first,second=guest.itemSlots.equipment[1],guest.itemSlots.equipment[2]
            assert(swing('companion',{weaponId=second.id}).ok)
            assert(first.durability==100 and second.durability==99)
        ''')

    def test_replay_and_failed_save_retry_do_not_repeat_damage_or_rewards(self):
        self.field()
        self.lua.execute('''
            a.hp=1; local beforeHost,beforeGuest=host.stats.xp,guest.stats.xp
            local request=assert(service:prepareRequest('companion','roaming.attack',fieldArgs('companion')))
            failSave=true; local r=service:execute('companion',1,request); assert(r.ok and r.savePending,r.reason)
            assert(a.dead and a.rewardResolved and host.stats.xp>beforeHost and guest.stats.xp>beforeGuest)
            local scrap,coal,hxp,gxp=data.scrap,data.resources.coal,host.stats.xp,guest.stats.xp
            assert(service:execute('companion',1,request).ok)
            assert(data.scrap==scrap and data.resources.coal==coal and host.stats.xp==hxp and guest.stats.xp==gxp)
            failSave=false; assert(service:retryCheckpoint()); assert(saved.expeditions[data.activeExpeditionArea].mobs['surface-bandit-a'].rewardResolved)
            assert(service:execute('companion',1,request).durable)
            assert(guest.itemSlots.equipment[1].durability==99)
        ''')

    def test_reconnect_does_not_reset_cooldown_or_bypass_surface_barriers(self):
        self.field()
        self.lua.execute('''
            assert(swing('companion').ok); service:disconnect('companion',1); service:admit('companion',2)
            assert(service:prepareRequest('companion','roaming.attack',fieldArgs('companion'))==nil)
            clock=clock+1
            for _,key in ipairs({'traveling','changingCar','encounterActive','activityBlocked'}) do
                states.companion[key]=true; local request,reason=service:prepareRequest('companion','roaming.attack',fieldArgs('companion'))
                assert(not request and reason=='field_unavailable'); states.companion[key]=nil
            end
            states.companion.x=math.huge; assert(not service:prepareRequest('companion','roaming.attack',fieldArgs('companion')))
        ''')

    def test_host_known_position_range_and_line_of_sight_override_client_aim(self):
        self.field()
        self.lua.execute('''
            states.companion.x=836; states.companion.y=842
            local hp=a.hp; local r=swing('companion'); assert(r.ok and r.result.damage==0 and a.hp==hp)
            clock=clock+1; states.companion.x=700; states.companion.y=625
            local reach=Areas.canReach; Areas.canReach=function() return false end
            r=swing('companion'); Areas.canReach=reach
            assert(r.ok and r.result.damage==0 and a.hp==hp)
        ''')

    def test_public_result_excludes_pose_private_item_identity_and_ai_state(self):
        self.field()
        self.lua.execute('''
            local r=swing('companion'); assert(r.ok,r.reason)
            local Public=require('game.net.item_results'); local projected=assert(Public.project('roaming.attack',r.result))
            assert(Public.valid('roaming.attack',projected) and projected.hitId==a.entityId)
            assert(projected.x==nil and projected.alerts==nil and projected.message==nil and projected.weaponId==nil)
            projected.damage=-1; assert(not Public.valid('roaming.attack',projected))
            local Wire=require('game.net.game_state'); assert(Wire.project(data))
        ''')

    def test_saved_cues_reject_unknown_or_corrupt_ownership_and_identity(self):
        self.field()
        self.lua.execute('''
            assert(swing('companion').ok)
            local copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion=2; assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion.hitId='foreign'; assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion.damage=math.huge; assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion.actorId='host'; assert(not Schema.validate(copy))
            copy=assert(Schema.copy(data)); copy.roamingCombat.actors.companion.injected=true; assert(not Schema.validate(copy))
        ''')

    def test_guardian_shell_can_break_but_guest_cannot_finish_or_start_battle(self):
        self.field()
        self.lua.execute('''
            data.activeExpeditionArea=Areas.DUNGEON_ID; Areas.ensure(data)
            area=data.expeditions[Areas.DUNGEON_ID]
            for id,m in pairs(area.mobs) do if id~='sludge-badger-boss' then m.dead=true; m.hp=0 end end
            Areas.updateGates(data,Areas.DUNGEON_ID)
            a=area.mobs['sludge-badger-boss']; a.hp=1
            states.companion.x,states.companion.y=a.x,a.y
            assert(Entities.ensure(data)); local epoch=data.coop.sceneEpoch
            local r=swing('companion'); assert(r.ok,r.reason)
            assert(a.hp==1 and not a.dead and not a.rewardResolved and r.result.shellBroken)
            assert(not data.tacticalBattle and data.coop.sceneEpoch==epoch)
            assert(run('companion','battle.begin',{encounterId=a.entityId}).reason=='host_only')
        ''')

    def test_failed_result_validation_rolls_back_cooldown_costs_and_randomness(self):
        self.field()
        self.lua.execute('''
            local prior=Roaming.attack
            Roaming.attack=function(...) local ok,reason,r=prior(...); r.damage=-1; return ok,reason,r end
            local r=swing('companion'); Roaming.attack=prior
            assert(not r.ok and r.reason=='invalid_result')
            assert(a.hp==100 and guest.itemSlots.equipment[1].durability==100 and data.coop.randomState==nil)
            assert(not service.activityState.fieldCooldowns and not data.roamingCombat and writes==0)
            assert(swing('companion').ok)
        ''')


if __name__ == '__main__':
    unittest.main()
