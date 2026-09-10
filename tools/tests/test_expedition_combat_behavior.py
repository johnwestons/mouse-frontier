"""Behavioral expedition combat checks using the real Lua modules.

Install lupa in the test environment, or point LUA_RUNTIME_PYTHONPATH at a
directory containing it. No LÖVE window or user save is opened by these checks.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "lupa is required for behavioral Lua checks")
class ExpeditionCombatBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().project_root = ROOT.as_posix()
        self.lua.execute(
            """
            package.path=project_root..'/?.lua;'..package.path
            love={math={random=function(a,b) return a or .5 end}}
            R=require('game.roaming_mobs')
            Areas=require('game.expedition_areas')
            Rewards=require('game.expedition_rewards')
            Controller=require('game.battle_controller')
            function fixture(mobs)
                local data={equipment={'sword'},weaponDurability={sword=100},weaponProficiency={},
                    location=6,resources={coal=0},scrap=0,health=20,maxHealth=20,
                    stats={level=1,xp=0},trait={reward=1},inventory={},passengers={},nextBattlePotions={}}
                local catalog={weaponCombat={sword={kind='melee',range=5,family='blade'}},
                    weaponStats={sword={min=4,max=4}},characterTraitProfiles={{reward=1}}}
                local state={mobs={}}
                for _,mob in ipairs(mobs) do
                    state.mobs[mob.id]={x=mob.x or 60,y=mob.y or 0,hp=mob.maxHp or 40,maxHp=mob.maxHp or 40}
                end
                local ctx={data=data,catalog=catalog,isWeapon=function() return true end,
                    area={id='test',mobs=mobs},areaState=state,player={x=0,y=0,facing=1},encounters={},
                    move=function(ox,oy,nx,ny) return nx,ny end,
                    isActive=function(mob) return not mob.locked end,
                    canReach=function() return true end}
                ctx.beginEncounter=function(encounter) ctx.encounters[#ctx.encounters+1]=encounter end
                return R.new(),ctx
            end
            function controllerContext(data)
                return {saveData=data,Catalog=require('game.catalog'),Util=require('game.util'),
                    CombatBalance=require('game.combat_balance'),PlayerProgression=require('game.player_progression'),
                    BattleRules=require('game.battle_rules'),TrainUpgradeBalance=require('game.train_upgrade_balance'),
                    Events={grantBattleLoot=function() error('Expedition must use its per-enemy rewards') end},
                    BattleGrid={generateObstacles=function() return {} end},BOARD_COLS=9,BOARD_ROWS=6,
                    writeSave=function() end}
            end
            """
        )

    def test_repeated_swings_do_not_cancel_a_committed_enemy_attack(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='bandit',maxHp=200,x=60,y=0,tier='easy'}})
            for tick=1,120 do
                if tick%26==1 then R.attack(sys,ctx,60,0) end
                if R.update(sys,ctx,1/60)=='battle' then break end
            end
            return #ctx.encounters,ctx.encounters[1].enemyStates[1].hp<200
            """
        )
        self.assertEqual(result, (1, True))

    def test_moving_out_of_the_telegraphed_strike_avoids_battle(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='bandit',maxHp=200,x=60,y=0,tier='easy'}})
            for tick=1,30 do R.update(sys,ctx,1/60) end
            ctx.player.x=-180
            for tick=1,45 do R.update(sys,ctx,1/60) end
            return #ctx.encounters
            """
        )
        self.assertEqual(result, 0)

    def test_broken_weapon_cannot_damage_and_worn_weapon_uses_condition(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='bandit',x=60,y=0}})
            ctx.data.weaponDurability.sword=0
            local used=R.attack(sys,ctx,60,0)
            assert(not used and ctx.areaState.mobs.bandit.hp==40)
            assert(ctx.data.weaponProficiency.blade==nil)
            ctx.data.weaponDurability.sword=10
            assert(R.attack(sys,ctx,60,0))
            return ctx.areaState.mobs.bandit.hp,ctx.data.weaponDurability.sword,ctx.data.weaponProficiency.blade
            """
        )
        self.assertEqual(result, (38, 9, 1))

    def test_click_target_beats_nearer_mob_and_aiming_away_misses(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='near',x=65,y=0},{id='clicked',x=110,y=0},{id='behind',x=-60,y=0}})
            assert(R.attack(sys,ctx,110,-35))
            assert(ctx.areaState.mobs.clicked.hp==36 and ctx.areaState.mobs.near.hp==40 and ctx.areaState.mobs.behind.hp==40)
            sys,ctx=fixture({{id='behind',x=-60,y=0}})
            R.attack(sys,ctx,150,0)
            return ctx.areaState.mobs.behind.hp,R.message(sys)
            """
        )
        self.assertEqual(result, (40, "The swing misses."))

    def test_cooldown_press_does_not_create_modal_feedback(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='bandit',x=60,y=0}})
            R.attack(sys,ctx,60,0)
            local used,reason=R.attack(sys,ctx,60,0)
            R.update(sys,ctx,.20)
            return used,reason,sys.attackTimer<.42
            """
        )
        self.assertEqual(result, (False, None, True))

    def test_quick_attack_uses_last_movement_direction_including_vertical(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='north',x=0,y=-70},{id='east',x=60,y=0}})
            ctx.player.intentX=0; ctx.player.intentY=-1
            R.attack(sys,ctx)
            return ctx.areaState.mobs.north.hp,ctx.areaState.mobs.east.hp
            """
        )
        self.assertEqual(result, (36, 40))

    def test_softened_boss_can_be_challenged_without_taking_a_hit(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='boss',x=100,y=0,maxHp=3,boss=true,tier='medium'}})
            assert(R.attack(sys,ctx,100,0))
            assert(ctx.areaState.mobs.boss.hp==1 and #ctx.encounters==0)
            assert(R.challenge(sys,ctx,'boss'))
            return ctx.encounters[1].enemyStates[1].hp,ctx.data.health
            """
        )
        self.assertEqual(result, (1, 20))

    def test_walls_block_awareness_damage_and_completed_enemy_strikes(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='bandit',maxHp=200,x=60,y=0,tier='easy'}})
            ctx.canReach=function() return false end
            R.attack(sys,ctx,60,0)
            for tick=1,120 do R.update(sys,ctx,1/60) end
            assert(ctx.areaState.mobs.bandit.hp==200 and #ctx.encounters==0)
            ctx.canReach=function() return true end
            for tick=1,30 do R.update(sys,ctx,1/60) end
            ctx.canReach=function() return false end
            for tick=1,45 do R.update(sys,ctx,1/60) end
            return #ctx.encounters
            """
        )
        self.assertEqual(result, 0)

    def test_locked_boss_cannot_join_or_be_challenged_and_challenge_carries_hp(self) -> None:
        result = self.lua.execute(
            """
            local boss={id='boss',maxHp=58,x=90,y=0,boss=true,locked=true,tier='medium'}
            local sys,ctx=fixture({{id='bandit',x=60,y=0,tier='easy'},boss})
            assert(not R.challenge(sys,ctx,'boss'))
            for tick=1,120 do if R.update(sys,ctx,1/60)=='battle' then break end end
            assert(#ctx.encounters==1 and #ctx.encounters[1].enemyStates==1)
            boss.locked=false; ctx.areaState.mobs.boss.hp=7
            assert(R.challenge(sys,ctx,'boss'))
            local encounter=ctx.encounters[2]
            return encounter.enemyStates[1].mobId,encounter.enemyStates[1].hp,encounter.returnContext.x,encounter.returnContext.y
            """
        )
        self.assertEqual(result, ("boss", 7, 0, 0))

    def test_return_grace_prevents_an_immediate_attack_but_not_player_actions(self) -> None:
        result = self.lua.execute(
            """
            local sys,ctx=fixture({{id='bandit',maxHp=200,x=60,y=0,tier='easy'}})
            ctx.grace=true
            ctx.onHostileAction=function() ctx.grace=false end
            for tick=1,180 do R.update(sys,ctx,1/60) end
            assert(#ctx.encounters==0)
            R.attack(sys,ctx,60,0)
            for tick=1,120 do if R.update(sys,ctx,1/60)=='battle' then break end end
            return ctx.grace,#ctx.encounters
            """
        )
        self.assertEqual(result, (False, 1))

    def test_boss_flag_and_health_are_per_unit_in_a_mixed_encounter(self) -> None:
        result = self.lua.execute(
            """
            local _,ctx=fixture({})
            local c=controllerContext(ctx.data)
            c.saveData.character='player.png'
            local b=Controller.begin(c,{source='expedition',tier='medium',boss=true,
                mobFiles={'sludge-bandit.png','sludge-badger-boss.png'},
                enemyStates={{mobId='bandit',boss=false,hp=4,maxHp=22,weapon='mob-claw'},
                    {mobId='boss',boss=true,hp=7,maxHp=58,weapon='mob-claw'}}})
            return b.units[2].boss,b.units[2].hp,b.units[3].boss,b.units[3].hp
            """
        )
        self.assertEqual(result, (False, 4, True, 7))

    def test_field_and_battle_rewards_match_and_cannot_be_claimed_twice(self) -> None:
        result = self.lua.execute(
            """
            local _,field=fixture({})
            local _,tactical=fixture({})
            Areas.ensure(field.data); Areas.ensure(tactical.data)
            local mobId='surface-bandit-a'
            local definition=Areas.mobDefinition(Areas.SURFACE_ID,mobId)
            local saved=field.data.expeditions[Areas.SURFACE_ID].mobs[mobId]
            saved.hp=0; saved.dead=true
            assert(Rewards.claimEnemy(field.data,field.catalog,definition,saved).count==1)
            assert(Rewards.claimEnemy(field.data,field.catalog,definition,saved)==nil)
            local c=controllerContext(tactical.data)
            c.battle={encounter={source='expedition',areaId=Areas.SURFACE_ID,tier='easy'},
                units={{id='player',team='ally',hp=20},{id='enemy1',team='enemy',mobId=mobId,hp=0}}}
            assert(Controller.advance(c))
            assert(Controller.advance(c))
            assert(Rewards.claimBattle(tactical.data,tactical.catalog,c.battle).count==0)
            return field.data.stats.xp==tactical.data.stats.xp,field.data.scrap==tactical.data.scrap,
                field.data.resources.coal==tactical.data.resources.coal,c.battle.finished,
                tactical.data.expeditions[Areas.SURFACE_ID].mobs[mobId].dead
            """
        )
        self.assertEqual(result, (True, True, True, "win", True))


if __name__ == "__main__":
    unittest.main()
