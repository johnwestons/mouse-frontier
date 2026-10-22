"""Owned expedition combat, durable casualties, receipts and host continuation."""
import unittest
import test_coop_battles_behavior as ordinary


class ExpeditionTacticalTests(unittest.TestCase):
    setUp = ordinary.TacticalCommandTests.setUp
    def expedition(self, count=2):
        self.lua.globals().enemy_count = count
        self.lua.execute('''
            setup(); Areas=require('game.expedition_areas'); Expedition=require('game.coop_expedition_battles')
            data.location=6; data.scene='expedition'; data.activeExpeditionArea=Areas.SURFACE_ID
            Areas.ensure(data); state.scene='expedition'; state.x=700.25; state.y=625.75
            host.playerX,host.playerY=state.x,state.y; guest.playerX,guest.playerY=state.x+36,state.y
            area=data.expeditions[Areas.SURFACE_ID]; a=area.mobs['surface-bandit-a']; z=area.mobs['surface-bandit-b']
            a.x,a.y=700,600; z.x,z.y=710,630; a.hp=13; z.hp=18
            assert(Entities.ensure(data)); entry={encounterId=a.entityId,enemyIds={a.entityId}}
            if enemy_count==2 then entry.enemyIds[2]=z.entityId end
            local original=run
            function run(id,name,args)
                local reply=original(id,name,args)
                if reply.ok and reply.result.partyTransition then state.scene=reply.result.scene end
                return reply
            end
            function start() return run('host','battle.begin',entry) end
        ''')

    def test_expedition_roster_uses_current_saved_enemy_identity_health_and_return(self):
        self.expedition()
        self.lua.execute('''
            local reply=start(); assert(reply.ok and reply.durable,reply.reason)
            local b=ready(); assert(#b.units==4 and b.encounter.source=='expedition' and b.encounter.entityId==a.entityId)
            assert(b.units[1].actorId=='host' and b.units[2].actorId=='companion' and b.units[3].mobId=='surface-bandit-a')
            assert(b.units[3].hp==13 and b.units[4].hp==18 and b.encounter.returnContext.x==700.25)
            assert(saved.tacticalBattle and not saved.expeditionBattle and saved.scene=='expedition')
            assert(#Commands.scopes(data)<=12)
            local loaded=assert(Schema.migrate(saved)); local resumed=assert(State.restore(loaded,Catalog))
            assert(resumed.encounter.source=='expedition' and resumed.units[2].actorId=='companion' and resumed.units[3].hp==13)
        ''')

    def test_expedition_entry_rejects_guest_forged_stats_dead_locked_far_and_other_area(self):
        self.expedition()
        self.lua.execute('''
            assert(run('companion','battle.begin',entry).reason=='host_only')
            local forged=assert(Schema.copy(entry)); forged.hp=1; assert(run('host','battle.begin',forged).reason=='invalid_args')
            a.dead=true; assert(start().reason=='enemy_unavailable'); a.dead=false
            a.x=1600; assert(start().reason=='enemy_unavailable'); a.x=700
            entry.enemyIds={a.entityId,a.entityId}; assert(start().reason=='invalid_enemies')
            entry.enemyIds={a.entityId,data.expeditions[Areas.DUNGEON_ID].entityId}; assert(start().reason=='enemy_unavailable')
            entry.enemyIds={a.entityId}; state.x=0/0; assert(start().reason=='battle_unavailable')
            assert(not data.tacticalBattle and writes==0)
        ''')

    def test_expedition_owned_attack_syncs_world_hp_and_only_guest_supplies(self):
        self.expedition(1)
        self.lua.execute('''
            assert(start().ok); local b=ready(); b.active=2; b.units[3].q,b.units[3].r=2,5; b.units[2].perfectAccuracy=true; b.obstacles={}
            local reply=action('companion','battle.attack',{weapon=guest.itemSlots.equipment[2].id,targetId=b.units[3].id})
            assert(reply.ok,reply.reason); assert(guest.ammo['22lr']==8 and host.ammo['22lr']==20)
            assert(a.hp==b.units[3].hp and saved.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-a'].hp==a.hp)
            assert(a.dead==(a.hp<=0) and State.validate(saved))
        ''')

    def test_expedition_win_pays_each_owner_once_and_waits_for_host_before_return(self):
        self.expedition()
        self.lua.execute('''
            assert(start().ok); local b=ready(); b.units[3].hp=0; b.units[4].hp=0;atExit(b)
            local xp=host.stats.xp; local gxp=guest.stats.xp; local epoch=data.coop.sceneEpoch
            local request=assert(service:prepareRequest('host','battle.endTurn',args()))
            assert(service:execute('host',0,request).ok and b.finished=='win')
            local scrap,coal=data.scrap,data.resources.coal
            assert(data.scene=='expedition' and data.tacticalBattle and data.coop.sceneEpoch==epoch and host.stats.xp>xp and guest.stats.xp>gxp)
            assert(a.rewardResolved and z.rewardResolved and a.rewardReceipt.playerXP.host==a.rewardReceipt.playerXP.companion)
            assert(service:execute('host',0,request).ok and data.scrap==scrap and data.resources.coal==coal)
            local nextArgs={encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision}
            assert(run('companion','battle.continue',nextArgs).reason=='host_only')
            local r=run('host','battle.continue',nextArgs); assert(r.ok and r.result.expeditionReturn and not data.tacticalBattle)
            assert(data.scene=='expedition' and data.activeExpeditionArea==Areas.SURFACE_ID and host.playerX==700.25 and host.playerY==625.75)
            assert((host.playerX-guest.playerX)^2+(host.playerY-guest.playerY)^2>=24^2 and data.scrap==scrap)
        ''')

    def test_expedition_retreat_preserves_survivor_damage_and_one_casualty_reward(self):
        self.expedition()
        self.lua.execute('''
            assert(start().ok); local b=ready(); b.units[3].hp=0; b.units[4].hp=7
            local nextArgs={encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision}
            local request=assert(service:prepareRequest('host','battle.retreat',nextArgs))
            local r=service:execute('host',0,request); assert(r.ok and r.durable and r.result.scene=='train',r.reason)
            assert(not data.tacticalBattle and not data.activeExpeditionArea and a.dead and a.rewardResolved and z.hp==7 and not z.dead)
            assert(a.rewardReceipt.playerXP.companion and host.activeCar==1 and guest.activeCar==1)
            local scrap=data.scrap; local xp=guest.stats.xp
            assert(service:execute('host',0,request).ok and data.scrap==scrap and guest.stats.xp==xp)
            local loaded=assert(Schema.migrate(saved)); assert(loaded.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-b'].hp==7)
        ''')

    def test_expedition_loss_checkpoint_stays_in_battle_until_host_continues(self):
        self.expedition()
        self.lua.execute('''
            assert(start().ok); local b=ready(); b.active=3; b.units[1].hp=0; b.units[2].hp=0
            host.health=0; guest.health=0
            assert(action('host','battle.enemyTurn').ok and b.finished=='loss')
            assert(data.tacticalBattle and data.scene=='expedition' and saved.tacticalBattle.battle.finished=='loss')
            assert(host.health==math.floor(host.maxHealth/2) and guest.health==math.floor(guest.maxHealth/2))
            local r=run('host','battle.continue',{encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision})
            assert(r.ok and data.scene=='train' and not data.tacticalBattle)
        ''')

    def test_expedition_save_failure_retries_same_enemy_hp_rewards_and_return(self):
        self.expedition(1)
        self.lua.execute('''
            failSave=true; local r=start(); assert(r.ok and r.savePending)
            local rng=data.coop.randomState; failSave=false; assert(service:retryCheckpoint() and saved.coop.randomState==rng)
            local b=ready(); b.units[3].hp=0;atExit(b); assert(action('host','battle.endTurn').ok)
            local scrap=data.scrap; local xp=guest.stats.xp; failSave=true
            r=run('host','battle.continue',{encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision})
            assert(r.ok and r.savePending and data.scene=='expedition' and not data.tacticalBattle)
            failSave=false; assert(service:retryCheckpoint() and saved.players.companion.stats.xp==xp and saved.scrap==scrap)
            assert(saved.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-a'].rewardResolved)
        ''')

    def test_expedition_model_rejects_missing_mob_foreign_identity_and_return(self):
        self.expedition(1)
        self.lua.execute('''
            assert(start().ok)
            for _,edit in ipairs({
                function(d) d.activeExpeditionArea=Areas.DUNGEON_ID end,
                function(d) d.tacticalBattle.battle.encounter.returnContext.x=0/0 end,
                function(d) d.tacticalBattle.battle.units[3].mobId='forged' end,
                function(d) d.tacticalBattle.battle.encounter.enemyStates[1]=true end,
                function(d) d.tacticalBattle.battle.encounter.enemyStates[1].entityId='e99999' end,
                function(d) d.tacticalBattle.battle.encounter.mobFiles[1]='foreign.png' end}) do
                local copy=assert(Schema.copy(data)); edit(copy); local ok,valid=pcall(Schema.validate,copy); assert(ok and not valid)
            end
        ''')

    def test_authored_boss_gate_reward_and_host_continuation_survive_disk_model_restore(self):
        self.expedition(1)
        self.lua.execute('''
            data.activeExpeditionArea=Areas.DUNGEON_ID
            area=data.expeditions[Areas.DUNGEON_ID]; a=area.mobs['sludge-badger-boss']
            state.x,state.y=1430,460; host.playerX,host.playerY=state.x,state.y
            guest.playerX,guest.playerY=Areas.clamp(data,Areas.DUNGEON_ID,1466,460)
            entry={encounterId=a.entityId,enemyIds={a.entityId}}
            assert(not area.gates.bossGateOpen and not area.gates.bossDefeated)
            assert(start().reason=='battle_unavailable' and not data.tacticalBattle)
            for _,id in ipairs(Areas.definition(Areas.DUNGEON_ID).gateRequired) do
                local mob=area.mobs[id]; mob.hp=0; mob.dead=true
            end
            Areas.updateGates(data,Areas.DUNGEON_ID)
            assert(start().ok); local b=ready()
            assert(b.encounter.boss and b.encounter.enemyStates[1].boss and b.units[3].hp==58)
            b.units[3].hp=0;atExit(b); assert(action('host','battle.endTurn').ok and b.finished=='win')
            local scrap=data.scrap; local hxp=host.stats.xp; local gxp=guest.stats.xp
            assert(a.dead and a.rewardResolved and area.gates.bossDefeated and area.completed)
            assert(not area.chests['boss-vault'].opened and data.tacticalBattle)
            data=assert(Schema.migrate(saved)); b=assert(State.restore(data,Catalog))
            assert(b.finished=='win' and b.encounter.boss and b.units[2].actorId=='companion')
            state.screen='battle'; state.scene='expedition'
            service=Authority.new({campaign=data,sessionId='boss-restored',checkpoint=function(value) saved=assert(Schema.copy(value)); return true end})
            Commands.install(service,{catalog=Catalog,actorState=function() return state end}); service:admit('companion',2)
            local nextArgs={encounterId=data.tacticalBattle.encounterId,turnRevision=data.tacticalBattle.revision}
            local foreign,reason=service:prepareRequest('companion','battle.continue',nextArgs)
            assert(not foreign and reason=='host_only')
            local request=assert(service:prepareRequest('host','battle.continue',nextArgs))
            assert(service:execute('host',0,request).ok and not data.tacticalBattle and data.scene=='expedition')
            assert(service:execute('host',0,request).ok and data.scrap==scrap)
            assert(data.players.host.stats.xp==hxp and data.players.companion.stats.xp==gxp)
            assert(saved.expeditions[Areas.DUNGEON_ID].gates.bossDefeated and not saved.expeditions[Areas.DUNGEON_ID].chests['boss-vault'].opened)
        ''')
