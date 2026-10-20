"""Exercise concave walk regions and their authored navigation waypoints."""
from __future__ import annotations

import os
import importlib.util
from pathlib import Path
import sys
import tempfile
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
area=Areas.definition(Areas.BADLANDS_SURFACE_ID)
area.corridors={}; area.clearings={}
area.walkRegions={{id='concave-test',
    points={{100,100},{300,100},{300,200},{200,200},{200,300},{100,300}},
    nodes={{150,150},{250,150},{150,250}}}}
data={location=5,activeExpeditionArea=area.id,expeditions={}}
Areas.ensure(data)
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable")
class ExpeditionPolygonBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_concave_region_includes_edges_but_does_not_fill_its_notch(self):
        self.lua.execute(r'''
            for _,point in ipairs({{100,100},{200,200},{300,150},{100,250},{150,300},{150,150},{275,175},{175,275}}) do
                assert(Areas.isWalkable(data,area.id,point[1],point[2]),'polygon ground or outline must be walkable')
            end
            for _,point in ipairs({{250,250},{301,150},{150,301},{99,150},{150,99}}) do
                assert(not Areas.isWalkable(data,area.id,point[1],point[2]),'outside ground must remain blocked')
            end
        ''')

    def test_region_orientation_and_named_coordinates_do_not_change_collision(self):
        self.lua.execute(r'''
            local reversed={}
            for index=#area.walkRegions[1].points,1,-1 do
                local point=area.walkRegions[1].points[index]
                reversed[#reversed+1]={x=point[1],y=point[2]}
            end
            area.walkRegions[1].points=reversed
            assert(Areas.isWalkable(data,area.id,275,175))
            assert(Areas.isWalkable(data,area.id,200,200))
            assert(not Areas.isWalkable(data,area.id,250,250))
        ''')

    def test_region_waypoints_route_around_the_concave_corner(self):
        self.lua.execute(r'''
            local x,y=275,175
            assert(not Areas.canReach(data,area.id,x,y,175,275),'the direct shortcut crosses the notch')
            for step=1,8 do
                if (x-175)^2+(y-275)^2<.01 then break end
                local nx,ny=Areas.pathTarget(data,area.id,x,y,175,275)
                assert(nx and ny,'interior region nodes must join the visibility graph')
                assert(Areas.canReach(data,area.id,x,y,nx,ny))
                x,y=Areas.move(data,area.id,x,y,nx,ny)
            end
            assert((x-175)^2+(y-275)^2<.01,'the route must reach the other leg of the region')
        ''')

    def test_loaded_mask_remains_authoritative_over_region_fallback(self):
        self.lua.execute(r'''
            love={image={newImageData=function()
                return {getDimensions=function() return area.width,area.height end,
                    getPixel=function() return 0,0,0,1 end}
            end}}
            assert(not Areas.isWalkable(data,area.id,150,150),'black edited pixels override a polygon')
        ''')

    def test_builder_unions_polygon_pixels_without_filling_the_notch(self):
        from PIL import Image

        spec = importlib.util.spec_from_file_location("polygon_mask_builder", ROOT / "tools/build_expedition_walkmask.py")
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        temporary_root = ROOT / ".stabilization/polygon-mask-tests"
        temporary_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as directory:
            fixture_root = Path(directory)
            self.assertEqual(fixture_root.resolve().parent, temporary_root.resolve())
            (fixture_root / "game").mkdir()
            (fixture_root / "game/expedition_areas.lua").write_text(r'''
                return {definition=function()
                    return {width=400,height=400,walkMask='mask.png',background='background.png',
                        corridors={{x1=40,y1=150,x2=150,y2=150,r=10}},clearings={},
                        walkRegions={{id='concave-test',
                            points={{100,100},{300,100},{300,200},{200,200},{200,300},{100,300}}}},
                        interactions={},spawns={}}
                end}
            ''', encoding="utf-8")
            Image.new("RGB", (400, 400), "black").save(fixture_root / "background.png")
            builder.ROOT = fixture_root
            mask_path = builder.build("fixture", fixture_root / "preview")
            with Image.open(mask_path) as mask:
                for point in ((50,150),(150,150),(275,175),(175,275),(200,200)):
                    self.assertEqual(mask.getpixel(point), (255,255,255))
                for point in ((250,250),(301,150),(150,301),(20,20)):
                    self.assertEqual(mask.getpixel(point), (0,0,0))
            self.assertTrue((fixture_root / "preview/fixture-overlay.png").is_file())


if __name__ == "__main__":
    unittest.main()
