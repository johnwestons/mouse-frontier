"""Tactical inspection must not change turn ownership or available equipment."""
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


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class BattleUIBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(r'''
            local function noop() end
            love={graphics=setmetatable({},{__index=function() return noop end})}
            UI=require('game.battle_ui')
            local data=require('game.save_schema').migrate({character='mouse-engineer.png',
                equipment={'frontier-short-sword'},traitBaselineApplied=true})
            ctx={W=960,H=720,saveData=data,ui={playSfx=noop},scenery={},colors={cream={1,1,1},
                brass={1,1,0},red={1,0,0},green={0,1,0},panel={0,0,0}},animationClock=0,
                playerProgression=require('game.player_progression'),
                drawLandscape=noop,drawGround=noop,drawAnimatedCharacter=noop,
                pointerPosition=function() return -1000,-1000 end,
                screenToGame=function(x,y) return x,y end,
                button=function(label,x,y,w,h,enabled) return {x=x,y=y,w=w,h=h,enabled=enabled} end}
            for _,name in ipairs({'characterImages','npcImages','mobImages','characterWalkImages','npcWalkImages',
                'mobAttackImages','mobIdleImages','mobHitImages','mobDeathImages','mobWalkImages',
                'mobRangedImages','characterAnimations'}) do ctx[name]={} end
            ctx.battle={active=1,selected=1,round=1,phase='select',units={
                {id='player',team='ally',name='Player',file='mouse-engineer.png',q=1,r=3,hp=20,maxHP=20,move=2,armor=2},
                {id='ally1',team='ally',name='Companion',file='guard-fox.png',weapon='frontier-battle-axe',q=1,r=2,hp=12,maxHP=12,move=2,armor=1},
                {id='enemy1',team='enemy',name='Enemy',file='sludge-bandit.png',q=9,r=3,hp=18,maxHP=18,move=2,armor=1}},
                tiles={},tileVariants={},obstacles={},abilitiesUsed={}}
            function keyboardFixture()
                local runtime={state='battle',saveData=ctx.saveData,battle=ctx.battle}
                local calls={}
                local function record(name)
                    return function(value) calls[#calls+1]={name=name,value=value} end
                end
                local inputContext=setmetatable({
                    runtime=runtime,ui=ctx.ui,characters={},maintenanceSession={},scenery={},inventory={},catalog={},
                    npcRelationships={},merchantTrade={},util=require('game.util'),engineUpgrades={},trainUpgradeBalance={},
                    maintenance={},battleRules=require('game.battle_rules'),stops={},settlements={},interiorDoors={},firstAid={},shootingRange={},
                    battleAttack=record('attack'),battleHeal=record('heal'),battleGuard=record('guard'),
                    advanceBattleTurn=record('end'),finishBattle=record('finish'),setBattlePrompt=record('prompt'),
                },{__index=function() return noop end})
                return require('game.gameplay_input').new(inputContext),runtime,calls
            end
        ''')

    def test_inspecting_companion_keeps_active_player_equipment(self) -> None:
        self.lua.execute(r'''
            ctx.battle.selected='ally1'
            UI.draw(ctx)
            assert(ctx.battle.options[2]=='frontier-short-sword')
            assert(ctx.ui.battleEnd and #ctx.ui.battleWeapons==2)
        ''')

    def test_inspecting_enemy_does_not_hide_player_actions(self) -> None:
        self.lua.execute(r'''
            ctx.battle.selected='enemy1'
            UI.draw(ctx)
            assert(ctx.ui.battleEnd and ctx.ui.battleAbility)
            assert(ctx.battle.options[2]=='frontier-short-sword')
        ''')

    def test_inspecting_ally_cannot_expose_actions_during_enemy_turn(self) -> None:
        self.lua.execute(r'''
            ctx.battle.active=3; ctx.battle.selected='player'
            UI.draw(ctx)
            assert(ctx.ui.battleEnd==nil and ctx.ui.battleRetreat==nil)
            assert(#ctx.ui.battleWeapons==0)
        ''')

    def test_stale_end_turn_button_cannot_skip_enemy_between_draws(self) -> None:
        self.lua.execute(r'''
            UI.draw(ctx)
            local button=ctx.ui.battleEnd
            local advanced=0
            ctx.advanceBattleTurn=function() advanced=advanced+1 end
            ctx.battle.active=3
            assert(UI.handleMouse(ctx,button.x+2,button.y+2,false)=='handled')
            assert(advanced==0 and ctx.battle.active==3)
        ''')

    def test_keyboard_cannot_skip_or_change_enemy_turn(self) -> None:
        self.lua.execute(r'''
            local input,runtime,calls=keyboardFixture()
            runtime.battle.active=3; runtime.battle.options={'scratch'}
            for _,key in ipairs({'space','m','i','r','escape','1','h','g'}) do input.keypressed(key) end
            assert(#calls==0 and runtime.battle.phase=='select' and not runtime.inventoryOpen)
        ''')

    def test_keyboard_ignores_intro_dead_unit_and_missing_battle(self) -> None:
        self.lua.execute(r'''
            local input,runtime,calls=keyboardFixture()
            runtime.battle.intro=0
            input.keypressed('space'); input.keypressed('m')
            assert(#calls==0 and runtime.battle.phase=='select')
            runtime.battle.intro=nil; runtime.battle.units[1].hp=0
            input.keypressed('space'); input.keypressed('r')
            assert(#calls==0)
            runtime.battle=nil; input.keypressed('space')
            assert(#calls==0)
        ''')

    def test_keyboard_retains_player_controls_and_finished_result_continue(self) -> None:
        self.lua.execute(r'''
            local input,runtime,calls=keyboardFixture()
            input.keypressed('space'); input.keypressed('m')
            assert(calls[1].name=='end' and calls[2].name=='prompt' and runtime.battle.phase=='move')
            input.keypressed('i'); assert(runtime.inventoryOpen)
            input.keypressed('escape'); assert(not runtime.inventoryOpen)
            runtime.battle.active=3; runtime.battle.finished='loss'
            input.keypressed('space')
            assert(calls[3].name=='finish' and calls[3].value=='loss')
        ''')

    def test_mobile_feed_health_and_ability_description_remain_visible(self) -> None:
        self.lua.execute(r'''
            local drawn={}
            local function recordText(value,x,y)
                drawn[#drawn+1]={kind='text',value=value,x=x,y=y}
            end
            love.graphics.print=recordText; love.graphics.printf=recordText
            love.graphics.rectangle=function(mode,x,y,w,h)
                if mode=='fill' then drawn[#drawn+1]={kind='fill',x=x,y=y,w=w,h=h} end
            end
            ctx.mobileEnabled=true; ctx.battle.message='Enemy hits for 4 damage.'
            UI.draw(ctx)
            local catalog=require('game.catalog')
            local ability=catalog.characterAbility(ctx.battle.units[1].file)
            local description=ctx.playerProgression.abilityProfile(ability.kind,ctx.saveData.stats.level).description
            local found={}
            for index,item in ipairs(drawn) do
                local key=item.kind=='text' and (item.value==ctx.battle.message and 'feed'
                    or item.value=='HP 20/20' and 'health'
                    or item.value:find(description,1,true) and 'ability')
                if key then
                    found[key]=true
                    assert(item.x>=0 and item.y>=0 and item.x<960 and item.y<720)
                    for later=index+1,#drawn do
                        local cover=drawn[later]
                        assert(cover.kind~='fill' or item.x<cover.x or item.x>cover.x+cover.w
                            or item.y<cover.y or item.y>cover.y+cover.h,key..' is covered by a later panel')
                    end
                end
            end
            assert(found.feed and found.health and found.ability)
        ''')


if __name__ == '__main__':
    unittest.main()
