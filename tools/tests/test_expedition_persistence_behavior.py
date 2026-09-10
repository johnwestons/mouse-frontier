"""Execute the expedition checkpoint/return lifecycle against the Lua modules."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]

HARNESS = r'''
love={math={random=math.random}}
math.randomseed(841)
Areas=require("game.expedition_areas")
Schema=require("game.save_schema")
Catalog=require("game.catalog")
Checkpoints=require("game.expedition_battle_state")
Session=require("game.game_session")
Runtime=require("game.runtime_state")
RETURN_X,RETURN_Y=700.25,625.75

function saveRoundTrip(data)
    local files={}
    love.filesystem={
        getInfo=function(path) return files[path] and {type='file'} or nil end,
        createDirectory=function() return true end,
        write=function(path,contents) files[path]=contents; return true end,
        read=function(path) return files[path] end,
        load=function(path) return files[path] and loadstring(files[path]) or nil end,
        remove=function(path) files[path]=nil; return true end,
    }
    local Save=require('game.save')
    assert(Save.write(99,data))
    return assert(Save.read(99))
end

function newRuntime(data)
    local session=Session.new()
    local runtime=Runtime.new{session=session,transition=function(value) session:setScreen(value) end}
    runtime.selectedSlot=1
    runtime:activate(data,{x=RETURN_X,y=RETURN_Y,velocityX=0,velocityY=0})
    return runtime
end

function newData()
    local data=assert(Schema.migrate({location=6,scene="expedition",activeExpeditionArea=Areas.SURFACE_ID,
        character="mouse-engineer.png",health=20,maxHealth=20,equipment={"frontier-short-sword"},
        inventory={"field-bandage-roll"},ammo={["9mm"]=4},resources={coal=0},
        stats={level=1,xp=0,nextXP=10},traitBaselineApplied=true}))
    data.trait=Catalog.characterTrait(data.character)
    data.crowCaravans.scheduleVersion=1
    Areas.ensure(data)
    return data
end

function newBattleRuntime(runtime)
    local ctx={runtime=runtime,width=960,height=720,catalog=Catalog,
        util={titleFromFile=function(value) return value or "" end},
        battleRules=require("game.battle_rules"),battleGrid=require("game.battle_grid"),
        battleController=require("game.battle_controller"),events=require("game.events"),
        combatBalance=require("game.combat_balance"),trainUpgradeBalance=require("game.train_upgrade_balance"),
        playerProgression=require("game.player_progression"),
        ui={playSfx=function() end,weaponSfx=function() return "sword" end}}
    for _,name in ipairs({"scenery","colors","characterImages","npcImages","mobImages","characterWalkImages","npcWalkImages",
        "mobAttackImages","mobIdleImages","mobHitImages","mobDeathImages","mobWalkImages","mobRangedImages","battleUI"}) do ctx[name]={} end
    for _,name in ipairs({"getCharacterAnimations","mobileEnabled","getWorldRenderer","getScreenUI","screenToGame",
        "pointerPosition","enterStop","handleInventoryClick"}) do ctx[name]=function() end end
    ctx.writeSave=function()
        runtime.saveCount=(runtime.saveCount or 0)+1
        runtime:syncForSave()
        runtime.lastSaved=assert(Schema.migrate(runtime.saveData))
    end
    ctx.returnToTrain=function()
        runtime.scene="train"; runtime.player.x,runtime.player.y=900,350
        ctx.writeSave()
    end
    return require("game.battle_runtime").new(ctx)
end

function startBattle(runtime,api,twoEnemies)
    assert(Areas.isWalkable(runtime.saveData,Areas.SURFACE_ID,RETURN_X,RETURN_Y),
        'battle return fixture must be a valid authored path point')
    local states={{mobId="surface-bandit-a",file="sludge-bandit.png",name="Bandit",hp=13,maxHp=18,weapon="mob-claw"}}
    if twoEnemies then states[2]={mobId="surface-bandit-b",file="sludge-bandit.png",name="Bandit",hp=18,maxHp=18,weapon="mob-claw"} end
    local files={}; for i,enemy in ipairs(states) do files[i]=enemy.file end
    api.beginEncounter{source="expedition",areaId=Areas.SURFACE_ID,tier="easy",mobFiles=files,enemyStates=states,
        returnContext={scene="expedition",areaId=Areas.SURFACE_ID,x=RETURN_X,y=RETURN_Y}}
    return runtime.battle
end

function newBootstrap(runtime)
    local image={getHeight=function() return 100 end}
    local noop=function() end
    local ctx={saveSchema=Schema,characters={"mouse-engineer.png"},characterImages={["mouse-engineer.png"]=image},
        npcImages={["villager.png"]=image},car={x=0,y=0,w=960,h=720},ui={},maintenanceSession={},runtime=runtime,
        filesystem={getDirectoryItems=function() return {} end},
        roster={isPlayable=function() return true end,mergeNpcRoster=function() return {"villager.png"} end},
        house={storeLoot=noop},catalog=Catalog,maintenance={close=noop,ensure=noop},engineUpgrades={tiers={{}}},
        passengers={},events={storyStops={},ensure=noop},settlements={clamp=function(x,y) return x,y end},
        playerProgression=require("game.player_progression"),stopHelpProgression={ensure=noop},
        crowCaravans={version=1,ensureSchedule=function(data) return data.crowCaravans,nil,false end},
        crowCaravanArea={hasStopGate=function() return true end},shootingRange={hostStops={}},
        trainObjectBounds=function() return 0,960,0,720 end,trainFloorBounds=function() return 0,960,0,720 end,
        clampToTrainFloor=function(x,y) return math.max(0,math.min(960,x)),math.max(0,math.min(720,y)) end,
        isFurnitureItem=function() return false end,resetStopSludges=noop,expeditionAreas=Areas,
        resetExpedition=function() runtime.resetCount=(runtime.resetCount or 0)+1 end,
        prepareExpeditionBattleAssets=function() runtime.assetsPrepared=(runtime.assetsPrepared or 0)+1 end,
        writeSave=noop}
    return require("game.session_bootstrap").new(ctx)
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class ExpeditionPersistenceBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_suspend_restores_same_turn_hp_status_items_and_potion_once(self) -> None:
        self.lua.execute(r'''
            local data=newData(); data.nextBattlePotions={['red-potion-vial']=true}
            local runtime=newRuntime(data); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            local potionAim=battle.units[1].aim
            assert(potionAim>2 and next(data.nextBattlePotions)==nil)
            battle.units[2].hp=5; battle.units[2].bleedRounds=2
            battle.units[1].hp=9; data.health=9; data.ammo['9mm']=2; data.inventory[1]=nil
            battle.round=3; battle.active=2; battle.phase='select'; battle.moveUsed=true
            runtime:syncForSave()
            local saved=saveRoundTrip(data)
            local fresh=newRuntime(newData()); local bootstrap=newBootstrap(fresh)
            assert(bootstrap.enterGame(saved))
            assert(fresh.state=='battle' and fresh.scene=='expedition')
            assert(fresh.battle.round==3 and fresh.battle.active==2 and fresh.battle.moveUsed)
            assert(fresh.battle.units[2].hp==5 and fresh.battle.units[2].bleedRounds==2)
            assert(fresh.battle.units[1].hp==9 and fresh.battle.units[1].aim==potionAim)
            assert(fresh.saveData.ammo['9mm']==2 and fresh.saveData.inventory[1]==nil)
            assert(fresh.assetsPrepared==1 and fresh.resetCount==1)
            assert(fresh.saveData.expeditionBattle.battle==fresh.battle)
        ''')

    def test_loss_is_saved_on_train_before_continue(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            battle.units[1].hp=0; runtime.saveData.health=0
            api.advanceTurn()
            assert(battle.finished=='loss' and runtime.state=='battle')
            assert(runtime.scene=='train' and runtime.player.x==900 and runtime.player.y==350)
            assert(runtime.lastSaved.scene=='train' and runtime.lastSaved.expeditionBattle==nil)
            assert(runtime.lastSaved.playerX==900 and runtime.lastSaved.playerY==350)
            assert(runtime.lastSaved.health==math.floor(runtime.lastSaved.maxHealth/2))
            local fresh=newRuntime(newData())
            assert(newBootstrap(fresh).enterGame(runtime.lastSaved))
            assert(fresh.state=='game' and fresh.scene=='train' and fresh.battle==nil)
        ''')

    def test_backpack_health_potion_keeps_its_max_health_effect(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            battle.units[1].hp=10; runtime.saveData.health=10
            runtime.saveData.inventory={'green-potion-vial'}
            local maxHP=battle.units[1].maxHP
            assert(api.useHealingItem('green-potion-vial'))
            assert(battle.units[1].maxHP==maxHP+6 and battle.units[1].hp==16)
            assert(runtime.saveData.inventory[1]==nil)
            local resumed=assert(Checkpoints.pending(saveRoundTrip(runtime.saveData)))
            assert(resumed.units[1].maxHP==maxHP+6 and resumed.units[1].hp==16)
        ''')

    def test_quick_heal_applies_the_complete_health_potion(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            battle.units[1].hp=10; runtime.saveData.health=10
            runtime.saveData.inventory={'green-potion-vial'}
            local maxHP=battle.units[1].maxHP
            api.heal()
            assert(battle.units[1].maxHP==maxHP+6 and battle.units[1].hp==16)
            assert(runtime.saveData.inventory[1]==nil and battle.active==2)
        ''')

    def test_victory_returns_exactly_and_reward_cannot_repeat_after_reload(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            battle.units[2].hp=0
            api.advanceTurn()
            assert(runtime.state=='battle' and runtime.scene=='expedition')
            assert(runtime.player.x==RETURN_X and runtime.player.y==RETURN_Y and runtime.expeditionGraceTimer==1.5)
            assert(runtime.lastSaved.expeditionBattle==nil)
            local saved=runtime.lastSaved
            local xp,scrap,coal=saved.stats.xp,saved.scrap,saved.resources.coal
            assert(saved.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-a'].rewardResolved)
            local fresh=newRuntime(newData()); assert(newBootstrap(fresh).enterGame(saved))
            assert(fresh.state=='game' and fresh.player.x==RETURN_X and fresh.player.y==RETURN_Y)
            api.finishBattle('win')
            Checkpoints.syncEnemies(fresh.saveData,Catalog,battle)
            assert(fresh.saveData.stats.xp==xp and fresh.saveData.scrap==scrap and fresh.saveData.resources.coal==coal)
        ''')

    def test_retreat_keeps_survivor_damage_and_claims_casualty_once(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api,true)
            battle.units[2].hp=0; battle.units[3].hp=7
            api.finishBattle('retreat')
            local saved=runtime.lastSaved
            assert(saved.scene=='train' and saved.expeditionBattle==nil)
            local mobs=saved.expeditions[Areas.SURFACE_ID].mobs
            assert(mobs['surface-bandit-a'].dead and mobs['surface-bandit-a'].rewardResolved)
            assert(mobs['surface-bandit-b'].hp==7 and not mobs['surface-bandit-b'].dead)
            local scrap=saved.scrap
            Checkpoints.syncEnemies(saved,Catalog,battle)
            assert(saved.scrap==scrap)
        ''')

    def test_interrupted_finished_snapshot_reconciles_loss_after_levelup(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api,true)
            runtime.saveData.stats.xp=9
            battle.units[1].hp=0; battle.units[2].hp=0; battle.units[3].hp=6; battle.finished='loss'
            local saved=assert(Schema.migrate(runtime.saveData))
            local pending,changed=Checkpoints.recover(saved,Catalog)
            assert(not pending and changed and saved.scene=='train' and saved.expeditionBattle==nil)
            assert(saved.health==math.floor(saved.maxHealth/2))
            local scrap=saved.scrap
            local again,changedAgain=Checkpoints.recover(saved,Catalog)
            assert(not again and not changedAgain and saved.scrap==scrap)
        ''')

    def test_invalid_checkpoint_recovers_without_losing_inventory(self) -> None:
        self.lua.execute(r'''
            local data=newData(); data.expeditionBattle={version=999,battle={}}
            local pending,changed,errorMessage=Checkpoints.recover(data,Catalog)
            assert(not pending and changed and errorMessage and data.scene=='train')
            assert(data.inventory[1]=='field-bandage-roll' and data.expeditionBattle==nil)
        ''')

    def test_loading_another_slot_clears_battle_and_resets_roaming(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            startBattle(runtime,api)
            local bootstrap=newBootstrap(runtime)
            local other=newData(); other.scene='train'; other.activeExpeditionArea=nil
            assert(bootstrap.enterGame(other))
            assert(runtime.battle==nil and runtime.state=='game' and runtime.resetCount==1)
            assert(bootstrap.enterGame(newData()))
            assert(runtime.battle==nil and runtime.resetCount==2 and runtime.expeditionGraceTimer==1.5)
        ''')

    def test_resumed_actions_bind_to_restored_battle_and_not_old_session(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local oldBattle=startBattle(runtime,api)
            oldBattle.units[1].moveAnim={fromQ=0,fromR=3,toQ=1,toR=3,t=.2,duration=.48}
            oldBattle.projectile={fromQ=1,fromR=3,toQ=9,toR=1,t=.1,duration=.42,ammo='9mm'}
            local saved=saveRoundTrip(runtime.saveData)
            assert(newBootstrap(runtime).enterGame(saved))
            local resumed=runtime.battle
            assert(resumed~=oldBattle and resumed.units[1].moveAnim.t==.2 and resumed.projectile.t==.1)
            api.guard()
            assert(resumed.units[1].guarding and not oldBattle.units[1].guarding)
            assert(runtime.saveData.expeditionBattle.battle==resumed)
            assert(runtime.lastSaved.expeditionBattle.battle.units[1].guarding)
        ''')

    def test_completed_result_updates_do_not_repeat_autosave_or_rewards(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            battle.units[2].hp=0; api.advanceTurn()
            local saves,scrap=runtime.saveCount,runtime.saveData.scrap
            for i=1,40 do api.update(.1) end
            assert(runtime.saveCount==saves and runtime.saveData.scrap==scrap)
            assert(runtime.state=='battle' and runtime.saveData.expeditionBattle==nil)
        ''')

    def test_enemy_turn_is_checkpointed_without_waiting_for_player_input(self) -> None:
        self.lua.execute(r'''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local battle=startBattle(runtime,api)
            battle.intro=nil; battle.active=2; battle.enemyDelay=0
            battle.units[2].q,battle.units[2].r=2,3
            local saves=runtime.saveCount
            api.update(.02)
            assert(battle.active==1 and runtime.saveCount>saves)
            assert(runtime.lastSaved.expeditionBattle.battle.active==1)
            assert(runtime.lastSaved.health==runtime.saveData.health)
        ''')


if __name__ == "__main__":
    unittest.main()
