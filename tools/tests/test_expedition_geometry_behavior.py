"""Exercise authored expedition paths, gate progression, and content migration."""
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
Areas=require('game.expedition_areas')
function fixture(areaId)
    local data={location=6,activeExpeditionArea=areaId,expeditions={}}
    Areas.ensure(data); Areas.updateGates(data,areaId)
    return data,Areas.definition(areaId),Areas.state(data,areaId)
end
function defeat(data,areaId,mobId)
    local saved=Areas.state(data,areaId).mobs[mobId]
    saved.dead=true; saved.hp=0
    Areas.updateGates(data,areaId)
end
function allDefeated(data,area)
    for _,mob in ipairs(area.mobs) do defeat(data,area.id,mob.id) end
end
function route(data,areaId,x,y,targetX,targetY,label)
    assert(Areas.isWalkable(data,areaId,x,y),label..': blocked route origin')
    assert(Areas.isWalkable(data,areaId,targetX,targetY),label..': blocked route destination')
    local seen={}
    for step=1,90 do
        if (x-targetX)^2+(y-targetY)^2<.01 then return step end
        local nx,ny=Areas.pathTarget(data,areaId,x,y,targetX,targetY)
        assert(nx and ny,label..': no waypoint from '..x..','..y)
        assert(Areas.canReach(data,areaId,x,y,nx,ny),label..': waypoint crosses blocked ground')
        local movedX,movedY=Areas.move(data,areaId,x,y,nx,ny)
        assert((movedX-nx)^2+(movedY-ny)^2<.01,label..': movement cannot follow navigation waypoint')
        local key=string.format('%.2f:%.2f',movedX,movedY)
        assert(not seen[key],label..': navigation loops at '..key)
        seen[key]=true; x,y=movedX,movedY
    end
    error(label..': navigation did not finish')
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class ExpeditionGeometryBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_bridge_deck_is_walkable_and_adjacent_water_is_blocked(self) -> None:
        self.lua.execute(r'''
            local data=fixture(Areas.SURFACE_ID)
            assert(Areas.canReach(data,Areas.SURFACE_ID,1038,447,1114,466))
            assert(Areas.canReach(data,Areas.SURFACE_ID,1114,466,1202,454))
            assert(Areas.isWalkable(data,Areas.SURFACE_ID,1100,455),'painted bridge deck must be traversable')
            for _,point in ipairs({{1114,425},{1114,515},{1114,380},{1150,380},{520,380}}) do
                assert(not Areas.isWalkable(data,Areas.SURFACE_ID,point[1],point[2]),'painted water must not become a clearing')
            end
        ''')

    def test_long_frame_cannot_jump_between_paths_across_water(self) -> None:
        self.lua.execute(r'''
            local data=fixture(Areas.SURFACE_ID)
            assert(Areas.isWalkable(data,Areas.SURFACE_ID,1114,301))
            assert(Areas.isWalkable(data,Areas.SURFACE_ID,1114,466))
            assert(not Areas.canReach(data,Areas.SURFACE_ID,1114,301,1114,466))
            local x,y=Areas.move(data,Areas.SURFACE_ID,1114,301,1114,466)
            assert(Areas.isWalkable(data,Areas.SURFACE_ID,x,y) and y<380)
            assert(math.abs(x-1114)<.001)
            route(data,Areas.SURFACE_ID,1114,301,1114,466,'bridge detour')
        ''')

    def test_every_surface_interaction_and_patrol_is_connected(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.SURFACE_ID)
            for spawnId,spawn in pairs(area.spawns) do
                for _,interaction in ipairs(area.interactions) do
                    route(data,area.id,spawn.x,spawn.y,interaction.x,interaction.y,spawnId..' -> '..interaction.id)
                end
            end
            for _,mob in ipairs(area.mobs) do
                route(data,area.id,area.spawns.town.x,area.spawns.town.y,mob.x,mob.y,'town -> '..mob.id)
                local x,y=mob.x,mob.y
                for index,point in ipairs(mob.patrol) do
                    route(data,area.id,x,y,point.x,point.y,mob.id..' patrol '..index)
                    x,y=point.x,point.y
                end
                route(data,area.id,x,y,mob.patrol[1].x,mob.patrol[1].y,mob.id..' patrol loop')
            end
        ''')

    def test_dungeon_gate_requires_both_bandits_and_vault_requires_boss(self) -> None:
        self.lua.execute(r'''
            local data,area,state=fixture(Areas.DUNGEON_ID)
            local boss=Areas.mobDefinition(area,'sludge-badger-boss')
            assert(not state.gates.bossGateOpen and not Areas.isMobActive(data,area.id,boss))
            assert(not Areas.isWalkable(data,area.id,1035,486))
            assert(Areas.pathTarget(data,area.id,991,490,boss.x,boss.y)==nil)
            defeat(data,area.id,'dungeon-bandit-a')
            assert(not state.gates.bossGateOpen and not Areas.isMobActive(data,area.id,boss))
            defeat(data,area.id,'dungeon-bandit-b')
            assert(state.gates.bossGateOpen and Areas.isMobActive(data,area.id,boss))
            assert(Areas.isWalkable(data,area.id,1035,486))
            assert(Areas.isWalkable(data,area.id,1510,540) and Areas.isWalkable(data,area.id,1430,445))
            assert(not Areas.isWalkable(data,area.id,1250,575),'arena must not extend into painted water')
            route(data,area.id,135,405,boss.x,boss.y,'unlocked boss route')
            assert(not state.gates.bossDefeated and not Areas.isWalkable(data,area.id,1480,150))
            assert(Areas.pathTarget(data,area.id,boss.x,boss.y,1480,150)==nil)
            defeat(data,area.id,boss.id)
            assert(state.gates.bossDefeated and state.completed)
            route(data,area.id,boss.x,boss.y,1480,150,'unlocked treasure route')
        ''')

    def test_all_dungeon_interactions_and_enemy_patrols_connect_after_unlock(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.DUNGEON_ID)
            allDefeated(data,area)
            for spawnId,spawn in pairs(area.spawns) do
                for _,interaction in ipairs(area.interactions) do
                    route(data,area.id,spawn.x,spawn.y,interaction.x,interaction.y,spawnId..' -> '..interaction.id)
                end
            end
            for _,mob in ipairs(area.mobs) do
                route(data,area.id,135,405,mob.x,mob.y,'dungeon entrance -> '..mob.id)
                local x,y=mob.x,mob.y
                for index,point in ipairs(mob.patrol) do
                    route(data,area.id,x,y,point.x,point.y,mob.id..' patrol '..index)
                    x,y=point.x,point.y
                end
                route(data,area.id,x,y,mob.patrol[1].x,mob.patrol[1].y,mob.id..' patrol loop')
            end
        ''')

    def test_closed_dungeon_still_connects_bandits_cache_and_exit(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.DUNGEON_ID)
            for _,interaction in ipairs(area.interactions) do
                if not interaction.requires then
                    route(data,area.id,135,405,interaction.x,interaction.y,'closed gate -> '..interaction.id)
                end
            end
            for _,mob in ipairs(area.mobs) do
                if not mob.requires then
                    route(data,area.id,135,405,mob.x,mob.y,'closed gate -> '..mob.id)
                    for _,point in ipairs(mob.patrol) do route(data,area.id,mob.x,mob.y,point.x,point.y,mob.id..' accessible patrol') end
                end
            end
        ''')

    def test_map_revision_repairs_only_obsolete_pending_battle_return_points(self) -> None:
        self.lua.execute(r'''
            local destination={areaId=Areas.SURFACE_ID,x=520,y=380}
            local data={location=6,activeExpeditionArea=Areas.SURFACE_ID,
                expeditions={[Areas.SURFACE_ID]={contentVersion=1}},
                expeditionBattle={version=1,battle={encounter={returnContext=destination}}}}
            Areas.ensure(data)
            assert(Areas.isWalkable(data,Areas.SURFACE_ID,destination.x,destination.y))
            assert(destination.x~=520 or destination.y~=380)
            local x,y=destination.x,destination.y
            Areas.ensure(data)
            assert(destination.x==x and destination.y==y,'initialization must not move a repaired return again')
            local fresh=fixture(Areas.SURFACE_ID)
            local exact={areaId=Areas.SURFACE_ID,x=700.25,y=625.75}
            fresh.expeditionBattle={version=1,battle={encounter={returnContext=exact}}}
            Areas.ensure(fresh)
            assert(exact.x==700.25 and exact.y==625.75,'ordinary returns must remain exact')
        ''')

    def test_content_revision_rehomes_mobs_without_resetting_health_rewards_or_chests(self) -> None:
        self.lua.execute(r'''
            local storage={[2]='water-bottle'}
            local data={location=6,activeExpeditionArea=Areas.SURFACE_ID,expeditions={
                [Areas.SURFACE_ID]={contentVersion=1,discovered=true,mobs={
                    ['surface-bandit-a']={x=620,y=520,hp=4,maxHp=18},
                    ['surface-bandit-b']={x=1080,y=285,hp=0,maxHp=18,dead=true,rewardResolved=true,rewardReceipt={xp=8}},
                },chests={['surface-cache']={opened=true,storage=storage}}},
                [Areas.DUNGEON_ID]={contentVersion=1,mobs={
                    ['dungeon-bandit-a']={hp=0,dead=true},['dungeon-bandit-b']={hp=0,dead=true},
                    ['sludge-badger-boss']={hp=0,dead=true,rewardResolved=true},
                },chests={['boss-vault']={opened=true,storage={}}}},
            }}
            Areas.ensure(data)
            local surface=Areas.state(data,Areas.SURFACE_ID)
            local authored=Areas.mobDefinition(Areas.SURFACE_ID,'surface-bandit-a')
            assert(surface.contentVersion==Areas.CONTENT_VERSION and surface.discovered)
            assert(surface.mobs['surface-bandit-a'].x==authored.x and surface.mobs['surface-bandit-a'].y==authored.y)
            assert(surface.mobs['surface-bandit-a'].hp==4 and not surface.mobs['surface-bandit-a'].dead)
            assert(surface.mobs['surface-bandit-b'].dead and surface.mobs['surface-bandit-b'].rewardResolved)
            assert(surface.mobs['surface-bandit-b'].rewardReceipt.xp==8)
            assert(surface.chests['surface-cache'].opened and surface.chests['surface-cache'].storage==storage)
            assert(storage[1]==nil and storage[2]=='water-bottle')
            local dungeon=Areas.state(data,Areas.DUNGEON_ID)
            Areas.updateGates(data,Areas.DUNGEON_ID)
            assert(dungeon.gates.bossGateOpen and dungeon.gates.bossDefeated and dungeon.completed)
            assert(dungeon.chests['boss-vault'].opened and next(dungeon.chests['boss-vault'].storage)==nil)
        ''')


if __name__ == "__main__":
    unittest.main()
