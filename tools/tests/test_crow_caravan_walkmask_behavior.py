"""Exercise user-painted caravan ground through movement and saved positions."""
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
Area=require('game.crow_caravan_area')
images={}
loads={}
love={image={newImageData=function(path)
    loads[path]=(loads[path] or 0)+1
    return assert(images[path], 'missing image: '..tostring(path))
end}}

function mask(width,height)
    local result={width=width,height=height,pixels={},reads={}}
    function result:getDimensions() return self.width,self.height end
    function result:getPixel(x,y)
        assert(x==math.floor(x) and y==math.floor(y),'pixel indices must be integers')
        assert(x>=0 and y>=0 and x<self.width and y<self.height,'pixel index outside mask')
        self.reads[#self.reads+1]={x=x,y=y}
        return unpack(self.pixels[x..':'..y] or {1,1,1,1})
    end
    function result:setPixel(x,y,r,g,b,a) self.pixels[x..':'..y]={r,g,b,a} end
    return result
end

function fixture(image)
    local definition=Area.definition(9)
    assert(definition.walkMask==Area.WALK_MASK,'definition must expose the actual editable mask')
    assert(Area.WALK_MASK=='assets/backgrounds/walkmask-crow-caravan-campsite-v1.png',
        'mask must be beside the campsite background')
    if image then images[Area.WALK_MASK]=image end
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class CrowCaravanWalkMaskBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_white_paint_replaces_old_floor_and_props_and_black_paint_blocks_ground(self) -> None:
        self.lua.execute(r'''
            local image=mask(960,720)
            fixture(image)
            assert(Area.isWalkable(480,466),'white paint must replace the old campfire obstacle')
            assert(Area.isWalkable(450,170),'white paint must replace the old wagon obstacle')
            assert(Area.isWalkable(80,150),'white paint must replace the old ellipse boundary')
            assert(Area.isWalkable(20,20),'white paint must replace the old inset map bounds')
            image:setPixel(480,626,0,0,0,1)
            assert(not Area.isWalkable(480,626),'black paint must block a formerly walkable point')
        ''')

    def test_red_threshold_and_alpha_match_stop_masks(self) -> None:
        self.lua.execute(r'''
            local image=mask(960,720)
            fixture(image)
            image:setPixel(480,626,.5,1,1,1)
            assert(not Area.isWalkable(480,626),'red exactly at the threshold is blocked')
            image:setPixel(480,626,.501,0,0,1)
            assert(Area.isWalkable(480,626),'only the red channel determines walkability')
            image:setPixel(480,626,1,1,1,0)
            assert(Area.isWalkable(480,626),'alpha must follow stop-mask semantics')
        ''')

    def test_clearance_samples_all_four_sides_and_honors_explicit_radius(self) -> None:
        self.lua.execute(r'''
            local image=mask(960,720)
            fixture(image)
            for _,offset in ipairs({{-6,0},{6,0},{0,-6},{0,6}}) do
                local x,y=500+offset[1],600+offset[2]
                image:setPixel(x,y,0,0,0,1)
                assert(not Area.isWalkable(500,600),'default feet need six units of clearance')
                assert(Area.isWalkable(500,600,0),'zero-radius queries only test their center')
                image:setPixel(x,y,1,1,1,1)
            end
            image:setPixel(512,600,0,0,0,1)
            assert(Area.isWalkable(500,600))
            assert(not Area.isWalkable(500,600,12),'an explicit foot radius must be respected')
        ''')

    def test_authored_resolution_maps_to_logical_screen_and_preserves_foot_radius(self) -> None:
        self.lua.execute(r'''
            local image=mask(1448,1086)
            fixture(image)
            assert(Area.isWalkable(480,360))
            local sampled={}
            for _,point in ipairs(image.reads) do sampled[point.x..':'..point.y]=true end
            for _,key in ipairs({'724:543','714:543','733:543','724:533','724:552'}) do
                assert(sampled[key],'expected source-pixel sample '..key)
            end
            image:setPixel(733,543,0,0,0,1)
            assert(not Area.isWalkable(480,360),'six logical units must scale with the source mask')
        ''')

    def test_white_mask_keeps_feet_inside_the_screen(self) -> None:
        self.lua.execute(r'''
            fixture(mask(960,720))
            assert(Area.isWalkable(6,6) and Area.isWalkable(954,714))
            for _,point in ipairs({{5,360},{955,360},{480,5},{480,715},
                {-1,360},{961,360},{480,-1},{480,721}}) do
                assert(not Area.isWalkable(point[1],point[2]),'feet may not leave the map')
            end
        ''')

    def test_saved_positions_in_painted_edge_ground_survive_restore(self) -> None:
        self.lua.execute(r'''
            fixture(mask(960,720))
            local data={location=9}
            local session=assert(Area.enter(data,9,{x=820,y=610,facing=-1},{camp={}}))
            for _,point in ipairs({{20,20},{940,700}}) do
                assert(Area.savePosition(session,{x=point[1],y=point[2],facing=1}))
                local restored=assert(Area.restore(data))
                local x,y=Area.spawn(restored,'saved')
                assert(x==point[1] and y==point[2],'restore must not reapply the old inset bounds')
            end
        ''')

    def test_clamp_moves_a_saved_position_off_new_black_paint(self) -> None:
        self.lua.execute(r'''
            local image=mask(960,720)
            fixture(image)
            local session=assert(Area.new({stop=9}))
            Area.savePosition(session,{x=480,y=600})
            for x=470,490 do
                for y=590,610 do image:setPixel(x,y,0,0,0,1) end
            end
            local x,y=Area.spawn(session,'saved')
            assert(x~=480 or y~=600,'saved feet must move off newly blocked ground')
            assert(Area.isWalkable(x,y),'restored feet must land on white ground')
        ''')

    def test_one_mask_is_cached_across_caravan_stops(self) -> None:
        self.lua.execute(r'''
            fixture(mask(960,720))
            for _,stop in ipairs({9,24,42}) do
                assert(Area.definition(stop).walkMask==Area.WALK_MASK)
                local session=assert(Area.new({stop=stop}))
                local x,y=Area.spawn(session)
                assert(Area.isWalkable(x,y))
                assert(Area.isWalkable(480,466))
            end
            assert(loads[Area.WALK_MASK]==1,'collision queries and stops share one loaded mask')
        ''')

    def test_movement_cannot_skip_a_thin_painted_wall_and_can_slide_along_it(self) -> None:
        self.lua.execute(r'''
            local image=mask(960,720)
            fixture(image)
            for y=0,719 do image:setPixel(510,y,0,0,0,1) end
            assert(Area.isWalkable(480,600) and Area.isWalkable(540,600))
            local x,y=Area.move(480,600,540,600)
            assert(x<510 and y==600,'a long frame must stop before a painted wall')
            assert(Area.isWalkable(x,y))
            local slideX,slideY=Area.move(x,y,x+6,y+6)
            assert(slideX<510 and slideY>y,'movement should slide along the painted boundary')
            assert(Area.isWalkable(slideX,slideY))
        ''')

    def test_missing_image_keeps_authored_fallback_and_caches_the_failure(self) -> None:
        self.lua.execute(r'''
            fixture()
            assert(Area.isWalkable(480,626))
            assert(not Area.isWalkable(480,466),'missing mask retains the old campfire obstacle')
            assert(not Area.isWalkable(20,20),'missing mask retains the old campsite perimeter')
            local x,y=Area.move(480,550,480,466)
            assert(x==480 and y==550,'legacy fallback movement remains unchanged')
            assert(loads[Area.WALK_MASK]==1,'missing files must not reload on every movement query')
        ''')

    def test_headless_tools_keep_authored_fallback_without_a_loader(self) -> None:
        self.lua.execute(r'''
            love=nil
            assert(Area.isWalkable(480,626))
            assert(not Area.isWalkable(480,466))
            local audit=Area.audit()
            assert(audit.ready,table.concat(audit.errors,'; '))
        ''')


if __name__ == "__main__":
    unittest.main()
