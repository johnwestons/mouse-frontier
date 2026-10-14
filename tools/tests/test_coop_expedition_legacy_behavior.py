"""Production adoption preserves an old battle and its host-owned result."""
import unittest
import test_expedition_persistence_behavior as legacy


class ExpeditionLegacyCoopTests(unittest.TestCase):
    setUp = legacy.ExpeditionPersistenceBehaviorTests.setUp

    def test_production_bootstrap_adopts_same_board_vitals_and_turn(self):
        self.lua.execute('''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local b=startBattle(runtime,api,true); b.intro=nil; b.units[2].hp=7; b.units[2].bleedRounds=2
            b.round=3; b.active=2; runtime:syncForSave()
            local saved=saveRoundTrip(runtime.saveData); local fresh=newRuntime(newData())
            local ok,reason,info=newBootstrap(fresh,true).enterGame(saved); assert(ok,reason)
            assert(info.expeditionImported and fresh.state=='battle' and fresh.scene=='expedition')
            local d=fresh.saveData; local model=assert(require('game.tactical_battle_state').pending(d))
            assert(not d.expeditionBattle and model==fresh.battle and model.round==3 and model.active==2)
            assert(model.units[2].hp==7 and model.units[2].bleedRounds==2 and model.encounter.entityId)
            assert(d.expeditions[Areas.SURFACE_ID].mobs['surface-bandit-a'].hp==7)
            assert(Schema.validate(d) and saveRoundTrip(d).tacticalBattle.battle.round==3)
        ''')

    def test_finished_legacy_result_waits_for_host_without_repaying_rewards(self):
        self.lua.execute('''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime)
            local b=startBattle(runtime,api); b.units[2].hp=0; api.advanceTurn()
            assert(b.finished=='win'); local d=runtime.saveData; local xp=d.stats.xp; local scrap=d.scrap
            Checkpoints.capture(d,b) -- snapshot taken before the old destination recovery
            local fresh=newRuntime(newData()); assert(newBootstrap(fresh,true).enterGame(saveRoundTrip(d)))
            assert(fresh.state=='battle' and fresh.battle.finished=='win' and fresh.saveData.tacticalBattle)
            assert(fresh.saveData.stats.xp==xp and fresh.saveData.scrap==scrap)
            local again=newRuntime(newData()); assert(newBootstrap(again,true).enterGame(saveRoundTrip(fresh.saveData)))
            assert(again.state=='battle' and again.saveData.stats.xp==xp and again.saveData.scrap==scrap)
        ''')

    def test_failed_conversion_leaves_checkpoint_for_existing_recovery(self):
        self.lua.execute('''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime); local b=startBattle(runtime,api)
            b.units[2].mobId='unknown'; local d=runtime.saveData; local pending=d.expeditionBattle
            local converted=require('game.tactical_battle_state').importLegacy(d)
            assert(not converted and d.expeditionBattle==pending and not d.tacticalBattle)
            local fresh=newRuntime(newData()); assert(newBootstrap(fresh,true).enterGame(d))
            assert(fresh.state=='game' and fresh.scene=='train' and not fresh.saveData.expeditionBattle)
        ''')

    def test_current_checkpoint_is_not_replaced_or_reimported(self):
        self.lua.execute('''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime); startBattle(runtime,api)
            local d=runtime.saveData; require('game.coop_entities').ensure(d)
            local State=require('game.tactical_battle_state'); assert(State.importLegacy(d))
            local model=d.tacticalBattle; assert(not State.importLegacy(d) and d.tacticalBattle==model)
        ''')

    def test_strictly_unconvertible_old_board_recovers_without_using_solo_combat(self):
        self.lua.execute('''
            local runtime=newRuntime(newData()); local api=newBattleRuntime(runtime); local b=startBattle(runtime,api)
            b.tiles[0]=nil; local d=runtime.saveData; local item=d.itemSlots.equipment[1].id
            assert(Checkpoints.pending(d)) -- the old validator accepted incomplete boards
            local fresh=newRuntime(newData()); local ok,reason,info=newBootstrap(fresh,true).enterGame(d); assert(ok,reason)
            assert(info.expeditionRecovered and fresh.state=='game' and fresh.scene=='train')
            assert(not fresh.battle and not fresh.saveData.expeditionBattle and not fresh.saveData.tacticalBattle)
            assert(fresh.saveData.itemSlots.equipment[1].id==item and fresh.saveData.inventory[1]=='field-bandage-roll')
        ''')
