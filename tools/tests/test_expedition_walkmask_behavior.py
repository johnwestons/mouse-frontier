"""Exercise editable expedition masks using the same pixel rules as stop masks."""
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
images={}
loads={}
love={image={newImageData=function(path)
    loads[path]=(loads[path] or 0)+1
    return assert(images[path], 'missing image: '..tostring(path))
end}}

function mask(width,height,red,green,blue,alpha)
    local result={width=width,height=height,pixels={},reads={},
        default={red or 1,green or 1,blue or 1,alpha or 1}}
    function result:getDimensions() return self.width,self.height end
    function result:getWidth() return self.width end
    function result:getHeight() return self.height end
    function result:getPixel(x,y)
        assert(x==math.floor(x) and y==math.floor(y),'pixel indices must be integers')
        assert(x>=0 and y>=0 and x<self.width and y<self.height,'pixel index outside mask')
        self.reads[#self.reads+1]={x=x,y=y}
        return unpack(self.pixels[x..':'..y] or self.default)
    end
    function result:setPixel(x,y,r,g,b,a) self.pixels[x..':'..y]={r,g,b,a} end
    return result
end

function fixture(areaId,image)
    local area=Areas.definition(areaId)
    assert(type(area.walkMask)=='string','area must declare an editable walkMask')
    if image then images[area.walkMask]=image end
    local data={location=6,activeExpeditionArea=areaId,expeditions={}}
    Areas.ensure(data); Areas.updateGates(data,areaId)
    return data,area,Areas.state(data,areaId)
end

function defeat(data,areaId,mobId)
    local mob=Areas.state(data,areaId).mobs[mobId]
    mob.dead=true; mob.hp=0
    Areas.updateGates(data,areaId)
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class ExpeditionWalkMaskBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_white_pixels_replace_old_corridors_and_black_pixels_block_them(self) -> None:
        self.lua.execute(r'''
            local image=mask(1672,941)
            local data,area=fixture(Areas.SURFACE_ID,image)
            assert(Areas.isWalkable(data,area.id,520,380),'white edited ground outside legacy paths must be usable')
            image:setPixel(836,842,0,0,0,1)
            assert(not Areas.isWalkable(data,area.id,836,842),'black paint must override an old authored path')
            assert(not Areas.isWalkable(data,area.id,-1,842),'white masks must not allow leaving the map')
            assert(not Areas.isWalkable(data,area.id,area.width+1,842))
        ''')

    def test_pixel_threshold_matches_stops_red_channel_and_ignores_alpha(self) -> None:
        self.lua.execute(r'''
            local image=mask(1672,941)
            local data,area=fixture(Areas.SURFACE_ID,image)
            image:setPixel(836,842,.5,1,1,1)
            assert(not Areas.isWalkable(data,area.id,836,842),'red at the threshold is blocked even if green and blue are white')
            image:setPixel(836,842,.501,0,0,1)
            assert(Areas.isWalkable(data,area.id,836,842),'red above the threshold is walkable')
            image:setPixel(836,842,1,1,1,0)
            assert(Areas.isWalkable(data,area.id,836,842),'alpha must follow stop-mask semantics')
        ''')

    def test_mask_checks_clearance_on_all_four_sides_of_the_feet(self) -> None:
        self.lua.execute(r'''
            local image=mask(1672,941)
            local data,area=fixture(Areas.SURFACE_ID,image)
            for _,offset in ipairs({{-6,0},{6,0},{0,-6},{0,6}}) do
                local x,y=836+offset[1],842+offset[2]
                image:setPixel(x,y,0,0,0,1)
                assert(not Areas.isWalkable(data,area.id,836,842),'black paint beside the feet must block movement')
                image:setPixel(x,y,1,1,1,1)
            end
            assert(Areas.isWalkable(data,area.id,836,842))
        ''')

    def test_smaller_mask_maps_pixels_and_foot_clearance_to_original_map_coordinates(self) -> None:
        self.lua.execute(r'''
            local image=mask(836,941)
            local data,area=fixture(Areas.SURFACE_ID,image)
            assert(Areas.isWalkable(data,area.id,1000,600))
            local sampled={}
            for _,point in ipairs(image.reads) do sampled[point.x..':'..point.y]=true end
            for _,key in ipairs({'500:600','497:600','503:600','500:594','500:606'}) do
                assert(sampled[key],'expected normalized foot sample '..key)
            end
            image:setPixel(503,600,0,0,0,1)
            assert(not Areas.isWalkable(data,area.id,1000,600),'clearance radius must remain six native map units')
        ''')

    def test_each_area_mask_is_loaded_once_across_queries_and_save_states(self) -> None:
        self.lua.execute(r'''
            local surface,area=fixture(Areas.SURFACE_ID,mask(1672,941))
            local dungeon,dungeonArea=fixture(Areas.DUNGEON_ID,mask(1672,941))
            for _=1,5 do
                assert(Areas.isWalkable(surface,area.id,836,842))
                assert(Areas.isWalkable(dungeon,dungeonArea.id,135,405))
            end
            local otherSave=fixture(Areas.SURFACE_ID)
            assert(Areas.canReach(otherSave,area.id,800,800,900,800))
            assert(loads[area.walkMask]==1,'surface mask should not reload per collision query or save')
            assert(loads[dungeonArea.walkMask]==1,'dungeon mask has its own cached image')
            assert(area.walkMask~=dungeonArea.walkMask)
        ''')

    def test_white_dungeon_mask_preserves_bandit_and_boss_gate_progression(self) -> None:
        self.lua.execute(r'''
            local image=mask(1672,941)
            local data,area=fixture(Areas.DUNGEON_ID,image)
            assert(Areas.isWalkable(data,area.id,1200,700),'white ground outside old paths is editable in dungeons too')
            assert(Areas.isWalkable(data,area.id,991,490),'ungated ground overlapping the gate approach remains accessible')
            assert(not Areas.isWalkable(data,area.id,1035,486))
            assert(not Areas.isWalkable(data,area.id,1430,460))
            assert(not Areas.isWalkable(data,area.id,1480,150))
            defeat(data,area.id,'dungeon-bandit-a')
            assert(not Areas.isWalkable(data,area.id,1430,460),'both bandits are required')
            defeat(data,area.id,'dungeon-bandit-b')
            assert(Areas.isWalkable(data,area.id,1035,486))
            assert(Areas.isWalkable(data,area.id,1430,460))
            assert(not Areas.isWalkable(data,area.id,1480,150),'the boss still locks the vault')
            defeat(data,area.id,'sludge-badger-boss')
            assert(Areas.isWalkable(data,area.id,1480,150))
            image:setPixel(1430,460,0,0,0,1)
            assert(not Areas.isWalkable(data,area.id,1430,460),'an opened gate never overrides black paint')
        ''')

    def test_movement_cannot_skip_a_painted_blockage(self) -> None:
        self.lua.execute(r'''
            local image=mask(1672,941)
            local data,area=fixture(Areas.SURFACE_ID,image)
            for x=1110,1119 do
                for y=280,320 do image:setPixel(x,y,0,0,0,1) end
            end
            assert(Areas.isWalkable(data,area.id,1100,301) and Areas.isWalkable(data,area.id,1130,301))
            assert(not Areas.canReach(data,area.id,1100,301,1130,301))
            local x,y=Areas.move(data,area.id,1100,301,1130,301)
            assert(x<1110 and y==301,'a long movement step must stop before painted obstacles')
            assert(Areas.isWalkable(data,area.id,x,y))
        ''')

    def test_missing_image_or_headless_loader_keeps_analytic_fallback(self) -> None:
        self.lua.execute(r'''
            local data,area=fixture(Areas.SURFACE_ID)
            assert(Areas.isWalkable(data,area.id,836,842),'missing mask falls back to known ground')
            assert(not Areas.isWalkable(data,area.id,520,380),'missing mask must not open the whole map')
            love.image=nil
            local dungeon,dungeonArea=fixture(Areas.DUNGEON_ID)
            assert(Areas.isWalkable(dungeon,dungeonArea.id,135,405))
            assert(not Areas.isWalkable(dungeon,dungeonArea.id,1200,700))
        ''')


if __name__ == "__main__":
    unittest.main()
