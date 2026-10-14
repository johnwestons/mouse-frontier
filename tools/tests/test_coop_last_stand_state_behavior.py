"""Saved Last Stand simulation, actor ownership and private presentation.

Headless aperture acceptance is stubbed; slot/hit geometry is production code.
The existing native Last Stand gate retains real PNG aperture/render coverage.
"""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class LastStandStateTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=function() return .5 end}}
            Schema=require('game.save_schema'); F=require('tools.tests.lua.coop_fixtures')
            Players=require('game.coop_players'); Items=require('game.item_instances'); Catalog=require('game.catalog')
            Shooting=require('game.first_person_shooting'); Sessions=require('game.coop_shooter_sessions')
            Shootout=require('game.last_stand_shootout'); State=require('game.coop_last_stand_state')
            Window=require('game.window_scene'); Window.pointOpen=function() return true end
            Window.buildingSolid=function() return false end
            data=F.campaign(12); assert(F.enroll(data)); data.scene='stop'
            host=Players.forActor(data,'host'); guest=Players.forActor(data,'companion')
            Items.write(host,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            Items.write(guest,nil,{kind='equipment',index=2},'frontier-22-lever-rifle')
            host.ammo['22lr']=20; guest.ammo['22lr']=9
            data.lastStand={state='shootout',originStop=12,loanAmmo=0,loanActive=false}
            quest=data.lastStand; battle=Shootout.new(quest,data,Catalog,'wide',960,720)
            companion=assert(Shootout.forActor(battle,data,Catalog,'companion'))
            hgun=battle.gun; ggun=companion.gun
            function hide()
                for _,t in ipairs(battle.targets) do t.status='hidden'; t.timer=999 end
            end
            function tick(dt,ids) return Shootout.update(battle,dt,data,Catalog,960,720,ids or {'host','companion'}) end
            function exposed(id)
                hide(); local t=battle.targets[1]; t.status='exposed'; t.timer=0
                battle.lastTargetActorId=id=='host' and 'companion' or 'host'; tick(.01)
                assert(t.status=='firing' and t.targetActorId==id); return t
            end
            function reload()
                local copy=assert(Schema.migrate(data)); local q=copy.lastStand
                local b=Shootout.new(q,copy,Catalog,q.combat.defenders.host.windowId,960,720)
                return copy,b,assert(Shootout.forActor(b,copy,Catalog,'companion'))
            end
            hide()
        ''')

    def test_saved_encounter_and_actor_guns_have_stable_independent_identity(self):
        self.lua.execute('''
            assert(quest.combat.version==State.VERSION and quest.combat.entityId:match('^e%d+$'))
            assert(State.record(battle)==State.record(companion) and State.actorId(companion)=='companion')
            assert(hgun.itemId~=ggun.itemId and hgun.actorId=='host' and ggun.actorId=='companion')
            tick(.1); assert(quest.combat.clock==.1 and quest.holdElapsed==.1 and Schema.validate(data))
        ''')

    def test_restore_preserves_clock_enemy_counters_spawn_timers_cover_and_gun_cost(self):
        self.lua.execute('''
            battle.clock=5; battle.enemyShots=7; battle.spawnCursor=4; battle.spawnCooldown=.8
            companion.windowId='tall'; Shootout.setCover(companion,true); tick(.05)
            local x,y=Window.slotPosition(Window.layout('wide',960,720),1)
            Shootout.setAim(battle,x,y); assert(Shootout.fire(battle,host,960,720,Catalog))
            local clock,timer,mag,id=battle.clock,battle.targets[1].timer,hgun.magazine,quest.combat.entityId
            local d,b,c=reload()
            assert(b.clock==clock and b.enemyShots==7 and b.spawnCursor==4 and b.spawnCooldown==.75)
            assert(b.targets[1].timer==timer and c.windowId=='tall' and c.ducking and c.coverProgress>0)
            assert(b.gun.magazine==mag and b.gun.cooldown==hgun.cooldown and d.lastStand.combat.entityId==id)
            assert(d.players.host.ammo['22lr']==19 and d.players.companion.ammo['22lr']==9)
        ''')

    def test_aim_held_input_damage_numbers_and_effects_never_enter_saved_targets(self):
        self.lua.execute('''
            local t=battle.targets[1]; t.status='exposed'; t.timer=2
            local x,y=Window.slotPosition(Window.layout(companion.windowId,960,720),1)
            Shootout.setAim(companion,x,y); Shootout.setADS(companion,true)
            assert(Shootout.fire(companion,guest,960,720,Catalog))
            assert(companion.targetEffects[1].damageNumber and not t.damageNumber and not t.hitTimer)
            assert(hgun.aimX==480 and not hgun.ads and guest.ammo['22lr']==8 and host.ammo['22lr']==20)
            local copy=assert(Schema.copy(data)); assert(Schema.validate(copy))
            assert(not copy.lastStand.impacts and not copy.lastStand.combat.effects and not copy.lastStand.combat.aimX)
            assert(not copy.lastStand.shooterSessions.companion.weaponSession.ads)
            local d,b,c=reload(); assert(not next(c.targetEffects) and not c.gun.ads)
            assert(b.targets[1].health==t.health and c.gun.magazine==ggun.magazine)
        ''')

    def test_shared_host_frame_advances_both_reload_timers_once(self):
        self.lua.execute('''
            hgun.magazine=1; ggun.magazine=1
            assert(Shootout.reload(battle,host) and Shootout.reload(companion,guest))
            local ht,gt=hgun.reloadTimer,ggun.reloadTimer; tick(.1)
            assert(math.abs(hgun.reloadTimer-(ht-.1))<.000001 and math.abs(ggun.reloadTimer-(gt-.1))<.000001)
            local clock=battle.clock; local result,reason=Shootout.update(companion,.1,guest,Catalog,960,720,{'host','companion'})
            assert(reason=='host_only' and battle.clock==clock and ggun.reloadTimer==gt-.1)
        ''')

    def test_empty_host_gun_does_not_stop_a_loaded_guest_from_holding_the_phase(self):
        self.lua.execute('''
            host.ammo['22lr']=0; hgun.magazine=0; Shootout.setCover(battle,true)
            local elapsed=battle.elapsed; tick(.2)
            assert(battle.elapsed>elapsed and companion.coverProgress==0 and battle.coverProgress>0)
            Shootout.setCover(companion,true); elapsed=battle.elapsed; tick(.2); assert(battle.elapsed==elapsed)
            Shootout.setCover(companion,false); guest.ammo['22lr']=0; ggun.magazine=0
            tick(.2); assert(battle.elapsed==elapsed)
        ''')

    def test_enemy_windup_selects_and_locks_the_ready_companion(self):
        self.lua.execute('''
            local t=exposed('companion'); data.coop.randomState=1
            local hh,gh=host.health,guest.health; tick(.01)
            assert(t.fired and host.health==hh and guest.health==gh-1)
            assert(State.owner(battle,'companion').hitRecovery>0 and State.owner(battle,'host').hitRecovery==0)
            assert(companion.playerDamage==1 and battle.playerDamage==0 and not battle.result)
        ''')

    def test_departed_windup_target_is_not_redirected_to_the_host(self):
        self.lua.execute('''
            local t=exposed('companion'); data.coop.randomState=1
            local hh,gh,rng=host.health,guest.health,data.coop.randomState; tick(.01,{'host'})
            assert(t.fired and t.targetActorId=='companion' and host.health==hh and guest.health==gh)
            assert(data.coop.randomState==rng)
            t.status='exposed'; t.timer=0; tick(.01,{'host'}); assert(t.targetActorId=='host')
        ''')

    def test_personal_cover_only_blocks_the_targeted_players_damage(self):
        self.lua.execute('''
            exposed('companion'); Shootout.setCover(companion,true); data.coop.randomState=1
            local gh=guest.health; tick(.01); assert(guest.health==gh and not battle.ducking)
            Shootout.setCover(companion,false); tick(.3)
            exposed('host'); data.coop.randomState=1
            local hh=host.health; tick(.01); assert(host.health==hh-1 and guest.health==gh)
        ''')

    def test_guest_is_downed_without_ending_the_hosts_defense_or_healing(self):
        self.lua.execute('''
            guest.health=2; exposed('companion'); data.coop.randomState=1; tick(.01)
            assert(guest.health==1 and not battle.result and host.health==17)
            local ammo=guest.ammo['22lr']; assert(not Shootout.fire(companion,guest,960,720,Catalog) and guest.ammo['22lr']==ammo)
            assert(State.target(battle,data,{'host','companion'})=='host')
            local d,b,c=reload(); assert(d.players.companion.health==1 and not b.result and c.playerDamage==1)
            local ok,reason=Shootout.retry(c); assert(reason=='host_only' and guest.health==1)
        ''')

    def test_wounded_host_uses_existing_retreat_rule_and_retry_preserves_guest_costs(self):
        self.lua.execute('''
            host.health=2; exposed('host'); data.coop.randomState=1; tick(.01)
            assert(host.health==1 and battle.result=='retreat' and battle.retreatReason=='wounded')
            local gh,ammo=guest.health,guest.ammo['22lr']; Shootout.retry(battle)
            assert(not battle.result and not battle.retreatReason and host.health==1 and guest.health==gh)
            assert(guest.ammo['22lr']==ammo and companion.hitRecovery==0 and not companion.ducking)
        ''')

    def test_both_actors_damage_one_enemy_pool_and_record_one_elimination(self):
        self.lua.execute('''
            local t=battle.targets[1]; t.status='exposed'; t.timer=2; t.health=2
            local x,y=Window.slotPosition(Window.layout('wide',960,720),1)
            Shootout.setAim(companion,x,y); assert(Shootout.fire(companion,guest,960,720,Catalog))
            assert(t.health==1 and quest.kills==0)
            Shootout.setAim(battle,x,y); assert(Shootout.fire(battle,host,960,720,Catalog))
            assert(t.health==0 and t.status=='dying' and quest.kills==1 and quest.enemyMorale==96)
            hgun.cooldown=0; assert(Shootout.fire(battle,host,960,720,Catalog)); assert(quest.kills==1)
            assert(guest.ammo['22lr']==8 and host.ammo['22lr']==18)
        ''')

    def test_foreign_campaign_or_actor_cannot_simulate_or_spend_through_a_bound_view(self):
        self.lua.execute('''
            local foreign=assert(Schema.migrate(data)); local other=Players.forActor(foreign,'companion')
            assert(not Shootout.forActor(battle,foreign,Catalog,'companion'))
            local clock,ammo=battle.clock,other.ammo['22lr']
            local _,reason=Shootout.update(battle,.1,foreign,Catalog,960,720); assert(reason=='host_only' and battle.clock==clock)
            assert(not Shootout.fire(companion,other,960,720,Catalog) and not Shootout.reload(companion,other))
            assert(not Shootout.supply(companion,other,Catalog) and not Shootout.cycleWeapon(companion,other,Catalog))
            assert(other.ammo['22lr']==ammo and not Shootout.fire(companion,host,960,720,Catalog))
        ''')

    def test_companion_loan_and_resupply_remain_separate_from_real_packs(self):
        self.lua.execute('''
            assert(Shootout.supply(companion,guest,Catalog))
            assert(companion.gun.borrowed and quest.shooterSessions.companion.loanAmmo==48 and quest.loanAmmo==0)
            local x,y=Window.slotPosition(Window.layout('wide',960,720),1)
            Shootout.setAim(companion,x,y); assert(Shootout.fire(companion,guest,960,720,Catalog))
            assert(quest.shooterSessions.companion.loanAmmo==47 and guest.ammo['22lr']==9 and host.ammo['22lr']==20)
            assert(not Shootout.supply(companion,host,Catalog))
            local d,b,c=reload(); assert(c.gun.borrowed and d.lastStand.shooterSessions.companion.loanAmmo==47 and d.lastStand.loanAmmo==0)
        ''')

    def test_gameplay_rng_is_saved_and_independent_of_cosmetic_global_draws(self):
        self.lua.execute('''
            local raw=assert(Schema.copy(data)); local outcomes={}
            for n=1,2 do
                local d=assert(Schema.migrate(raw)); d.coop.randomState=321
                love.math.random=function() return n==1 and .01 or .99 end
                local b=Shootout.new(d.lastStand,d,Catalog,'wide',960,720)
                for i,t in ipairs(b.targets) do t.status='hidden'; t.timer=-1 end
                for _=1,35 do Shootout.update(b,.1,d,Catalog,960,720,{'host','companion'}) end
                outcomes[n]=assert(Schema.copy(d))
            end
            local Codec=require('game.net.codec')
            assert(Codec.encode(outcomes[1].lastStand.combat)==Codec.encode(outcomes[2].lastStand.combat))
            assert(Codec.encode(outcomes[1].lastStand.targets)==Codec.encode(outcomes[2].lastStand.targets))
            assert(outcomes[1].coop.randomState==outcomes[2].coop.randomState and outcomes[1].coop.randomState~=321)
        ''')

    def test_intermission_requires_host_open_and_does_not_refill_or_repeat_phase(self):
        self.lua.execute('''
            battle.elapsed=44.99; tick(.02); assert(battle.result=='intermission' and quest.completedPhase==1)
            local gm,hm=ggun.magazine,hgun.magazine; local d,b,c=reload()
            assert(b.result=='intermission' and d.lastStand.completedPhase==1)
            State.open(d.lastStand); assert(not b.result)
            Shootout.update(b,.01,d,Catalog,960,720,{'host','companion'})
            assert(not b.result and d.lastStand.completedPhase==1 and b.gun.magazine==hm and c.gun.magazine==gm)
        ''')

    def test_withdrawal_result_and_timer_survive_restore_until_single_victory(self):
        self.lua.execute('''
            battle.result='withdrawing'; battle.withdrawTimer=1.4; tick(.2)
            local d,b,c=reload(); assert(b.result=='withdrawing' and b.withdrawTimer==1.2)
            Shootout.update(b,1.3,d,Catalog,960,720,{'host','companion'}); assert(b.result=='victory')
            local kills=d.lastStand.kills; Shootout.update(b,.1,d,Catalog,960,720)
            assert(b.result=='victory' and d.lastStand.kills==kills)
        ''')

    def test_replication_contains_saved_simulation_and_both_guns_without_runtime_views(self):
        self.lua.execute('''
            Shootout.setCover(companion,true); tick(.1)
            local GameState=require('game.net.game_state'); local producer=GameState.producer(); local replica=GameState.replica()
            assert(replica:apply(assert(producer:capture(data,true))))
            local q=replica.data.lastStand
            assert(q.combat.entityId==quest.combat.entityId and q.combat.clock==battle.clock)
            assert(q.combat.defenders.companion.ducking and q.shooterSessions.companion.weaponSession.itemId==ggun.itemId)
            assert(not q.combat.gun and not q.targets[1].damageNumber and not q.shooterSessions.companion.weaponSession.aimX)
        ''')

    def test_malformed_marked_saved_combat_and_private_target_fields_are_rejected(self):
        self.lua.execute('''
            for _,edit in ipairs({
                function(q) q.combat.version=3 end,function(q) q.combat.entityId='fake' end,
                function(q) q.combat.clock=0/0 end,function(q) q.combat.enemyShots=-1 end,
                function(q) q.combat.defenders.host.ducking=1 end,function(q) q.combat.defenders.host.coverProgress=2 end,
                function(q) q.combat.defenders.evil={} end,function(q) q.combat.defenders.companion.windowId='outside' end,
                function(q) q.combat.result='advance' end,function(q) q.combat.lastTargetActorId='evil' end,
                function(q) q.combat.effects={} end,function(q) q.targets[1].aimX=1 end,
                function(q) q.targets[1].hitTimer=.2 end,function(q) q.targets[1].damageNumber='1' end,
                function(q) q.targets[1].health=99 end,function(q) q.targets[1].slot=2 end,
                function(q) q.targets[1].atlas='arbitrary/path.png' end,function(q) q.targets[1].targetActorId='evil' end,
                function(q) q.targets[1]=false end,function(q) q.targets[9]={} end}) do
                local d=assert(Schema.copy(data)); edit(d.lastStand)
                assert(not Schema.validate(d)); assert(not Schema.migrate(d))
            end
        ''')

    def test_legacy_enemy_health_is_adopted_without_resetting_costs_or_private_state(self):
        self.lua.execute('''
            local raw=assert(Schema.copy(data)); raw.lastStand.combat=nil
            raw.lastStand.targets[1].health=1; raw.lastStand.targets[1].hasSpawned=true
            raw.lastStand.targets[1].hitTimer=.1; raw.lastStand.targets[1].damageNumber='2'
            local d=assert(Schema.migrate(raw)); local before=d.players.companion.ammo['22lr']
            local b=Shootout.new(d.lastStand,d,Catalog,'wide',960,720)
            assert(b.targets[1].health==1 and b.targets[1].hasSpawned and not b.targets[1].hitTimer)
            assert(d.players.companion.ammo['22lr']==before and Schema.validate(d))
        ''')


if __name__ == '__main__':
    unittest.main()
