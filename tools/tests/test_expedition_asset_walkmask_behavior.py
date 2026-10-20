"""Exercise Stop 5's shipped PNGs and preserve pixel-edge navigation precision."""
from __future__ import annotations

import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
elif (ROOT / ".stabilization/python-deps").is_dir():
    sys.path.insert(0, str(ROOT / ".stabilization/python-deps"))
try:
    from lupa.lua51 import LuaRuntime
    from PIL import Image
except ImportError:
    LuaRuntime = None


HARNESS = r'''
Areas=require('game.expedition_areas')
images={}
loads={}
love={image={newImageData=function(path)
    loads[path]=(loads[path] or 0)+1
    return assert(images[path], 'real PNG was not loaded: '..tostring(path))
end}}

function installMask(path,width,height,red)
    assert(#red==width*height, 'mask red-channel byte count must match its dimensions')
    local image={width=width,height=height,red=red}
    function image:getDimensions() return self.width,self.height end
    function image:getPixel(x,y)
        assert(x==math.floor(x) and y==math.floor(y),'pixel indices must be integers')
        assert(x>=0 and y>=0 and x<self.width and y<self.height,'pixel index outside mask')
        local value=string.byte(self.red,y*self.width+x+1)/255
        return value,value,value,1
    end
    images[path]=image
end

function fixture(areaId,flooded)
    local area=assert(Areas.definition(areaId))
    local data={location=area.stop,activeExpeditionArea=areaId,expeditions={}}
    Areas.ensure(data)
    Areas.updateGates(data,areaId)
    if flooded then
        Areas.resetEnvironment(data,areaId)
        Areas.updateEnvironment(data,areaId,area.environment.floodAt)
        assert(Areas.environment(data,areaId).flooded,'fixture must exercise active flood')
    end
    return data,area
end

function assertWalkable(data,area,x,y,label)
    assert(Areas.isWalkable(data,area.id,x,y),
        area.id..' '..label..' is blocked at '..x..','..y)
    assert(loads[area.walkMask], 'navigation must load mask pixels, never analytic fallback')
end

function walkRoute(data,area,source,target,label)
    assertWalkable(data,area,source.x,source.y,label..' start')
    assertWalkable(data,area,target.x,target.y,label..' destination')
    local x,y=source.x,source.y
    for step=1,128 do
        if math.abs(x-target.x)<.001 and math.abs(y-target.y)<.001 then return end
        local nx,ny=Areas.pathTarget(data,area.id,x,y,target.x,target.y)
        assert(nx and ny,area.id..' has no route for '..label..' from '..x..','..y)
        assert(math.abs(nx-x)+math.abs(ny-y)>.001,area.id..' route made no progress: '..label)
        local movedX,movedY=Areas.move(data,area.id,x,y,nx,ny)
        assert(math.abs(movedX-nx)<.001 and math.abs(movedY-ny)<.001,
            area.id..' movement blocked on '..label..' at '..movedX..','..movedY..' toward '..nx..','..ny)
        assertWalkable(data,area,movedX,movedY,label..' waypoint')
        x,y=movedX,movedY
    end
    error(area.id..' route did not finish: '..label)
end

function checkHighlightedGround(areaId,spawnId,points)
    local data,area=fixture(areaId)
    local spawn=assert(area.spawns[spawnId])
    for index,point in ipairs(points) do
        walkRoute(data,area,spawn,point,'user-marked ground '..index)
        walkRoute(data,area,point,spawn,'user-marked ground '..index..' return')
    end
    for _,region in ipairs(area.walkRegions or {}) do
        for index,node in ipairs(region.nodes or {}) do
            walkRoute(data,area,spawn,node,region.id..' navigation node '..index)
            walkRoute(data,area,node,spawn,region.id..' navigation node '..index..' return')
        end
    end
end
'''


@unittest.skipIf(LuaRuntime is None, "Pillow and Lua 5.1 runtime required; install Pillow/Lupa or set LUA_RUNTIME_PYTHONPATH")
class ExpeditionAssetWalkMaskBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)
        areas = self.lua.globals().Areas
        self.area_ids = (areas.BADLANDS_SURFACE_ID, areas.BADLANDS_BASIN_ID)
        for area_id in self.area_ids:
            area = areas.definition(area_id)
            with Image.open(ROOT / area.walkMask) as image:
                red = image.convert("RGB").getchannel("R")
                self.lua.globals().installMask(area.walkMask, *red.size, red.tobytes())

    def test_painted_approach_entrance_trail_accepts_continuous_player_movement(self) -> None:
        # These reference points follow the visible background, deliberately
        # independently of the corridor definitions that generate the mask.
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_SURFACE_ID)
            local trail={{836,900},{836,840},{836,770},{830,710},{810,657},
                {782,612},{810,565},{890,528},{955,478}}
            for index,point in ipairs(trail) do
                assertWalkable(data,area,point[1],point[2],'painted entrance trail '..index)
                if index>1 then
                    local previous=trail[index-1]
                    for _,segment in ipairs({{previous,point},{point,previous}}) do
                        local from,to=segment[1],segment[2]
                        local x,y=Areas.move(data,area.id,from[1],from[2],to[1],to[2])
                        assert(math.abs(x-to[1])<.001 and math.abs(y-to[2])<.001,
                            'player cannot follow painted entrance segment '..index..' at '..x..','..y)
                    end
                end
            end
        ''')

    def test_each_spawn_reaches_every_interaction_and_mob_on_real_masks(self) -> None:
        for area_id in self.area_ids:
            with self.subTest(area=area_id):
                self.lua.globals().testedAreaId = area_id
                self.lua.execute(r'''
                    local data,area=fixture(testedAreaId)
                    for spawnId,spawn in pairs(area.spawns) do
                        for _,interaction in ipairs(area.interactions) do
                            walkRoute(data,area,spawn,interaction,spawnId..' to '..interaction.id)
                            local action=Areas.interaction(data,Areas.SCENE,{x=interaction.x,y=interaction.y})
                            assert(action and action.id==interaction.id,'arrival must expose interaction '..interaction.id)
                            walkRoute(data,area,interaction,spawn,interaction.id..' back to '..spawnId)
                        end
                        for _,mob in ipairs(area.mobs) do
                            walkRoute(data,area,spawn,mob,spawnId..' to mob '..mob.id)
                        end
                    end
                ''')

    def test_approach_rock_faces_and_tent_are_not_walkable(self) -> None:
        # Background landmarks that the old diagonal mask incorrectly opened.
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_SURFACE_ID)
            for _,point in ipairs({{920,610,'rock face'},{1137,399,'rock pillar'},
                {1264,397,'tent'},{1085,334,'small pillar'},{1150,300,'upper pillar'}}) do
                assert(not Areas.isWalkable(data,area.id,point[1],point[2]),
                    'painted '..point[3]..' must not be walkable at '..point[1]..','..point[2])
            end
        ''')

    def test_approach_painted_western_loop_rejoins_the_main_trail(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_SURFACE_ID)
            local source=area.spawns.town
            for index,target in ipairs({{x=543,y=415},{x=646,y=344},
                {x=693,y=247},{x=861,y=337},{x=984,y=385}}) do
                walkRoute(data,area,source,target,'painted western loop '..index)
                source=target
            end
            walkRoute(data,area,source,area.spawns.town,'western loop return to entrance')
            assert(not Areas.isWalkable(data,area.id,751,330),'western stone wall must remain blocked')
        ''')

    def test_basin_visible_channel_and_banks_connect_from_the_painted_entrance(self) -> None:
        # Independent background anchors protect against a connected mask that
        # nevertheless opens rock faces instead of the actual ground.
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_BASIN_ID)
            local source=area.spawns.surface
            for index,target in ipairs({{x=1174,y=867},{x=1210,y=835},{x=1220,y=807},{x=1186,y=780},
                {x=1120,y=737},{x=981,y=661},{x=996,y=623},{x=897,y=578},
                {x=790,y=555},{x=603,y=500},{x=770,y=461},{x=1040,y=392},
                {x=1190,y=344},{x=1225,y=295},{x=146,y=790}}) do
                walkRoute(data,area,source,target,'painted basin ground '..index)
                source=target
            end
            walkRoute(data,area,source,area.spawns.surface,'painted basin return to entrance')
        ''')

    def test_approach_user_marked_ground_connects_to_the_entrance(self) -> None:
        # Independent samples from the user's red outlines, in native pixels.
        self.lua.execute(r'''
            checkHighlightedGround(Areas.BADLANDS_SURFACE_ID,'town',{
                {x=780,y=861},{x=894,y=860},{x=763,y=710},{x=883,y=682},
                {x=723,y=586},{x=1238,y=459},{x=1360,y=520},{x=1043,y=448},
                {x=838,y=366},{x=1370,y=295},{x=1250,y=195},{x=1015,y=205},
                {x=954,y=123},{x=490,y=303},{x=602,y=214},
            })
        ''')

    def test_basin_user_marked_ground_connects_to_the_entrance(self) -> None:
        self.lua.execute(r'''
            checkHighlightedGround(Areas.BADLANDS_BASIN_ID,'surface',{
                {x=1010,y=840},{x=1355,y=775},{x=1160,y=640},{x=1340,y=466},
                {x=1270,y=412},{x=1095,y=442},{x=915,y=495},{x=907,y=625},
                {x=690,y=658},{x=394,y=728},{x=100,y=657},{x=640,y=553},{x=518,y=513},
            })
        ''')

    def test_basin_cliffs_arch_void_log_and_background_remain_blocked(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_BASIN_ID)
            for _,point in ipairs({{280,550,'left cliff'},{280,500,'left cliff face'},{490,260,'tall cliff'},
                {1115,280,'arch void'},{1120,300,'below arch'},{1205,430,'rock pillar'},
                {1450,430,'right cliff face'},{1460,620,'right cliff'},
                {750,515,'fallen log'},{1585,345,'disconnected high cairn'},{900,70,'sky'}}) do
                assert(not Areas.isWalkable(data,area.id,point[1],point[2]),
                    'painted basin '..point[3]..' must not be walkable at '..point[1]..','..point[2])
            end
        ''')

    def test_mobs_can_complete_patrol_loops_on_real_masks(self) -> None:
        for area_id in self.area_ids:
            with self.subTest(area=area_id):
                self.lua.globals().testedAreaId = area_id
                self.lua.execute(r'''
                    local data,area=fixture(testedAreaId)
                    for _,mob in ipairs(area.mobs) do
                        local source=mob
                        for index,point in ipairs(mob.patrol or {}) do
                            walkRoute(data,area,source,point,mob.id..' patrol '..index)
                            source=point
                        end
                        if mob.patrol and #mob.patrol>0 then
                            walkRoute(data,area,source,mob.patrol[1],mob.id..' patrol wrap')
                        end
                    end
                ''')

    def test_navigation_rejects_an_edge_that_stops_slow_movement(self) -> None:
        # Preserve the playthrough's one-pixel snag independently of later
        # user-approved expansions that intentionally fill its old location.
        area = self.lua.globals().Areas.definition(self.lua.globals().Areas.BADLANDS_BASIN_ID)
        red = bytearray(b"\xff" * (area.width * area.height))
        red[542 * area.width + 1010] = 0
        self.lua.globals().installMask(area.walkMask, area.width, area.height, bytes(red))
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_BASIN_ID)
            assertWalkable(data,area,1003.97,542.25,'tight bend start')
            assertWalkable(data,area,1007.97,542.25,'sparse visibility midpoint')
            assertWalkable(data,area,1011.97,542.25,'tight bend destination')
            local x,y=Areas.move(data,area.id,1003.97,542.25,1004.97,542.25)
            assert(x<1004.97 and y==542.25,'slow walking must stop at the painted corner')
            assert(not Areas.canReach(data,area.id,1003.97,542.25,1011.97,542.25),
                'navigation must reject a shortcut across the painted corner')
        ''')

    def test_flood_leaves_banks_and_safe_interactions_reachable_on_real_mask(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.BADLANDS_BASIN_ID,true)
            local zone=area.environment.floodZone
            for _,spawn in pairs(area.spawns) do
                for index,bank in ipairs(zone.safeBanks) do
                    assert(not Areas.isInFlood(data,area.id,bank.x,bank.y),'safe bank must remain outside flood')
                    walkRoute(data,area,spawn,bank,'flood bank '..index)
                    walkRoute(data,area,bank,spawn,'flood bank '..index..' return')
                end
                for _,interaction in ipairs(area.interactions) do
                    if not Areas.isInFlood(data,area.id,interaction.x,interaction.y) then
                        walkRoute(data,area,spawn,interaction,'flood-safe '..interaction.id)
                        walkRoute(data,area,interaction,spawn,'flood-safe '..interaction.id..' return')
                    end
                end
            end
            for _,point in ipairs(zone.points) do
                assert(not Areas.isWalkable(data,area.id,point.x,point.y),'active wash must block walking')
                local x,y=Areas.nearestFloodBank(data,area.id,point.x,point.y)
                assert(x and y,'flood evacuation must find a bank on the shipped mask')
                assertWalkable(data,area,x,y,'evacuation bank')
                assert(not Areas.isInFlood(data,area.id,x,y),'evacuation must land outside the flood')
            end
        ''')


if __name__ == "__main__":
    unittest.main()
