"""Isolated render fixture uses real authority, authored reach and canonical results."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class ExpeditionPreviewFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures')
            Fixture=require('tools.expedition-integration-preview.fixture')
            Areas=require('game.expedition_areas'); Catalog=require('game.catalog')
            Session=require('game.game_session'); Runtime=require('game.runtime_state')
            CommandRuntime=require('game.coop_inventory_runtime')
            State=require('game.tactical_battle_state'); Schema=require('game.save_schema')
            session=Session.new(); runtime=Runtime.new({session=session,transition=function(screen) session.screen=screen end})
            runtime.saveData=F.campaign(6,{scene='stop',playerX=875,playerY=367})
            runtime.state='game'; runtime.scene='stop'
            runtime.player={x=875,y=367,facing=1,velocityX=0,velocityY=0}
            identity=Fixture.IDENTITY; saves=0
            context={runtime=runtime,session=session,catalog=Catalog,
                checkpoint=function() saves=saves+1; return true end,
                scene={trainSpawn=function() return 430,430 end,
                    trainClamp=function(data,id,x,y) return x,y end},
                applyParty=function(result) session:acceptPartyState(result) end}
            commands=Fixture.commands(CommandRuntime.new,context,function() return identity end)
            function position(x,y)
                if runtime.scene=='expedition' then x,y=Areas.clamp(runtime.saveData,runtime.saveData.activeExpeditionArea,x,y) end
                runtime.player.x,runtime.player.y=x,y
            end
            world={currentExpeditionInteraction=function()
                return Areas.interaction(runtime.saveData,runtime.scene,runtime.player)
            end,activateExpeditionInteraction=function(selected)
                local reply=commands.submit('scene.expedition',
                    {action=selected.action,areaId=selected.targetArea,spawn=selected.spawn})
                assert(not reply.durable and not reply.savePending)
                return reply.ok,reply.reason
            end}
            function enter(target,spawn)
                assert(Fixture.enter(runtime,world,position,target,spawn))
                assert(runtime.scene=='expedition' and runtime.saveData.activeExpeditionArea==target)
            end
            function begin(mobId)
                local area=Areas.state(runtime.saveData,runtime.saveData.activeExpeditionArea)
                local mob=area.mobs[mobId]; position(mob.x,mob.y)
                local reply=commands.submit('battle.begin',{encounterId=mob.entityId,enemyIds={mob.entityId}})
                assert(reply.ok,tostring(reply.reason))
                assert(runtime.state=='battle')
                runtime.battle=assert(State.restore(runtime.saveData,Catalog))
            end
            function continueBattle()
                local state=runtime.saveData.tacticalBattle
                local reply=commands.submit('battle.continue',{encounterId=state.encounterId,turnRevision=state.revision})
                assert(reply.ok,tostring(reply.reason)); runtime.battle=nil
                return reply
            end
        ''')

    def test_authored_routes_and_reach_enforcement(self):
        self.lua.execute('''
            position(790,420)
            assert(world.currentExpeditionInteraction()==nil)
            local reply=commands.submit('scene.expedition',{action='enterArea',areaId=Areas.SURFACE_ID,spawn='town'})
            assert(not reply.ok and reply.reason=='gate_unavailable')
            enter(Areas.SURFACE_ID,'town')
            assert(not pcall(Fixture.gate,runtime.saveData,Areas.DUNGEON_ID,'town'))
            enter(Areas.DUNGEON_ID,'surface')
            assert(not pcall(Fixture.gate,runtime.saveData,Areas.SURFACE_ID,'town'))
            enter(Areas.SURFACE_ID,'dungeonReturn')
            local x,y=Areas.spawn(Areas.SURFACE_ID,'dungeonReturn')
            x,y=Areas.clamp(runtime.saveData,Areas.SURFACE_ID,x,y)
            assert(runtime.player.x==x and runtime.player.y==y)
            assert(context.checkpoint~=nil and commands.authority().checkpoint==nil and saves==0)
            assert(runtime.selectedSlot==nil and session.networkMode=='offline')
        ''')

    def test_real_cache_boss_result_reward_and_loss_return(self):
        self.lua.execute('''
            enter(Areas.SURFACE_ID,'town'); position(1520,467)
            local selected=world.currentExpeditionInteraction(); assert(selected.chestId=='surface-cache')
            local cache=Areas.state(runtime.saveData,Areas.SURFACE_ID).chests[selected.chestId]
            local reply=commands.submit('expedition.cache',{areaId=Areas.SURFACE_ID,containerId=cache.entityId})
            assert(reply.ok,tostring(reply.reason)); assert(not reply.durable)
            enter(Areas.DUNGEON_ID,'surface')
            local area=Areas.state(runtime.saveData,Areas.DUNGEON_ID)
            for _,id in ipairs({'dungeon-bandit-a','dungeon-bandit-b'}) do area.mobs[id].dead=true; area.mobs[id].hp=0 end
            assert(Areas.updateGates(runtime.saveData,Areas.DUNGEON_ID).bossGateOpen)
            area.mobs['sludge-badger-boss'].hp=37
            begin('sludge-badger-boss')
            local boss; for _,u in ipairs(runtime.battle.units) do if u.boss then boss=u end end
            assert(boss.hp==37 and boss.maxHP==58)
            local revision=runtime.saveData.tacticalBattle.revision
            -- A divergent renderer copy must not be the staged authority board.
            runtime.battle=assert(Schema.copy(runtime.battle))
            local reply=Fixture.resolveStagedBattle(runtime,commands,Catalog,'win')
            assert(reply.ok and runtime.saveData.tacticalBattle.revision==revision+1)
            assert(runtime.battle==runtime.saveData.tacticalBattle.battle and runtime.battle.finished=='win')
            local bossState=Areas.state(runtime.saveData,Areas.DUNGEON_ID).mobs['sludge-badger-boss']
            assert(bossState.dead and bossState.hp==0)
            assert(runtime.battle.expeditionRewardReceipt and Schema.validate(runtime.saveData))
            local entry=runtime.battle.encounter.returnContext
            continueBattle()
            assert(runtime.scene=='expedition' and runtime.player.x==entry.x and runtime.player.y==entry.y)
            assert(Areas.updateGates(runtime.saveData,Areas.DUNGEON_ID).bossDefeated)
            enter(Areas.SURFACE_ID,'dungeonReturn'); begin('surface-bandit-a')
            Fixture.resolveStagedBattle(runtime,commands,Catalog,'loss')
            local reply=continueBattle()
            assert(reply.result.outcome=='loss' and runtime.state=='game' and runtime.scene=='train')
            assert(runtime.saveData.activeExpeditionArea==nil and runtime.saveData.tacticalBattle==nil)
            assert(runtime.player.x==430 and runtime.player.y==430 and runtime.saveData.health>0)
            assert(Schema.validate(runtime.saveData) and saves==0)
        ''')

    def test_identity_slot_role_changes_and_saves_fail_closed(self):
        self.lua.execute('''
            local function blocked(change,restore)
                change(); assert(not pcall(commands.authority))
                assert(not pcall(commands.submit,'scene.expedition',{})); restore()
            end
            blocked(function() runtime.selectedSlot=1 end,function() runtime.selectedSlot=nil end)
            blocked(function() identity='normal-game' end,function() identity=Fixture.IDENTITY end)
            blocked(function() session:setNetworkMode('host') end,function() session:setNetworkMode('offline') end)
            blocked(function() session:setNetworkMode('client') end,function() session:setNetworkMode('offline') end)
            local save={}; Fixture.installSaveTripwires(save)
            for _,name in ipairs({'write','schedule','remove'}) do assert(not pcall(save[name],1,runtime.saveData)) end
            assert(saves==0 and commands.authority().checkpoint==nil)
        ''')

    def test_default_production_adapter_retains_checkpoint_barrier(self):
        self.lua.execute('''
            -- The helper copies context; normal composition still checkpoints.
            context.checkpoint=function() saves=saves+1; return false end
            local ordinary=CommandRuntime.new(context)
            local reply=ordinary.submit('scene.expedition',{action='enterArea',areaId=Areas.SURFACE_ID,spawn='town'})
            assert(not reply.ok and reply.reason=='save_pending' and not reply.durable and saves>0)
            assert(runtime.scene=='stop' and runtime.saveData.activeExpeditionArea==nil)
            assert(ordinary.authority().checkpoint==context.checkpoint)
            assert(commands.authority().checkpoint==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
