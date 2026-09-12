"""Keep the actual bogie renderer anchored after mobile texture packing."""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

if os.environ.get("LUA_RUNTIME_PYTHONPATH"):
    sys.path.insert(0, os.environ["LUA_RUNTIME_PYTHONPATH"])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.build_mobile_package import optimize_image  # noqa: E402


HARNESS = r'''
local function noop() end
love={graphics={push=noop,pop=noop,setColor=noop,setShader=noop,
    circle=function(mode,x,y,radius)
        wheels[#wheels+1]={x=x,y=y,radius=radius}
    end,
    draw=function(image,quad,x,y,rotation,sx,sy,ox,oy)
        draws[#draws+1]={frame=quad.frame,x=x,y=y,sx=sx,sy=sy,ox=ox,oy=oy,
            width=quad.width,height=quad.height}
    end}}
Train=require('game.train')
function render(frameWidth,frameHeight,carX,carWidth,distance)
    draws={}; wheels={}
    local atlas={image={},count=4,quads={}}
    for frame=1,4 do
        atlas.quads[frame]={frame=frame,width=frameWidth,height=frameHeight,
            getViewport=function(self)
                return (self.frame-1)*self.width,0,self.width,self.height
            end}
    end
    assert(Train.drawCarRunningGear(atlas,{x=carX,w=carWidth},distance))
    return draws,wheels
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class TrainBogieRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        config = json.loads((ROOT / "mobile" / "config.json").read_text(encoding="utf-8"))
        relative = "assets/sprites/train/animations/train-car-bogie-run-4-v1.png"
        with Image.open(ROOT / relative) as image:
            cls.desktop_size = (image.width / 4, image.height)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            packed = directory / "bogie.png"
            with patch("tools.build_mobile_package.CACHE_ROOT", directory / "cache"):
                optimize_image(ROOT / relative, packed, relative, config)
            with Image.open(packed) as image:
                cls.mobile_size = (image.width / 4, image.height)

    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def render(self, size, car_x=429, car_width=620, distance=0):
        draws, wheels = self.lua.globals().render(*size, car_x, car_width, distance)
        return ([draws[index] for index in range(1, len(draws) + 1)],
                [wheels[index] for index in range(1, len(wheels) + 1)])

    @staticmethod
    def authored_point(draw, x, y):
        return (draw.x + (x * draw.width / 543 - draw.ox) * draw.sx,
                draw.y + (y * draw.height / 724 - draw.oy) * draw.sy)

    def test_packed_bogies_preserve_every_frame_anchor_at_all_car_sizes(self):
        self.assertNotEqual(self.desktop_size, self.mobile_size)
        frames = set()
        for car_x, car_width in ((429, 620), (-30, 310), (700, 930)):
            # Mid-frame samples avoid floating-point ambiguity at phase boundaries.
            for distance in [22.5 * math.tau * (index + .125) / 4 for index in range(4)] + [-137.4, 6000]:
                with self.subTest(car_x=car_x, car_width=car_width, distance=distance):
                    desktop, original_wheels = self.render(self.desktop_size, car_x, car_width, distance)
                    mobile, packed_wheels = self.render(self.mobile_size, car_x, car_width, distance)
                    self.assertEqual(2, len(mobile))
                    self.assertEqual(4, len(packed_wheels))
                    for original, packed in zip(desktop, mobile):
                        frames.add(packed.frame)
                        self.assertEqual(original.frame, packed.frame)
                        for x, y in ((270.5, 448), (39, 265), (504, 448), (102, 378), (439, 378)):
                            for before, after in zip(self.authored_point(original, x, y), self.authored_point(packed, x, y)):
                                self.assertAlmostEqual(before, after, places=8)
                    for original, packed in zip(original_wheels, packed_wheels):
                        self.assertAlmostEqual(original.x, packed.x, places=8)
                        self.assertAlmostEqual(original.y, packed.y, places=8)
                        self.assertAlmostEqual(original.radius, packed.radius, places=8)
        self.assertEqual({1, 2, 3, 4}, frames)

    def test_contact_and_centers_stay_on_car_anchors_under_uniform_view_scaling(self):
        for size in (self.desktop_size, self.mobile_size):
            for car_width in (310, 620, 930):
                draws, wheels = self.render(size, 429, car_width, 93.4)
                for view_scale, offset_x, offset_y in ((.7, 80, 25), (1, 0, 0), (1.8, -350, -440)):
                    for draw, source_center in zip(draws, (154.5, 483.5)):
                        center_x, contact_y = self.authored_point(draw, 270.5, 448)
                        expected_x = 429 + (source_center - 10) * car_width / 620
                        self.assertAlmostEqual(expected_x * view_scale + offset_x,
                                               center_x * view_scale + offset_x, places=8)
                        self.assertAlmostEqual(670 * view_scale + offset_y,
                                               contact_y * view_scale + offset_y, places=8)
                    for wheel in wheels:
                        self.assertAlmostEqual(670 * view_scale + offset_y,
                                               (wheel.y + wheel.radius) * view_scale + offset_y, places=8)

    def test_desktop_draw_keeps_approved_origin_scale_and_bogie_spacing(self):
        draws, _ = self.render(self.desktop_size)
        for draw in draws:
            self.assertAlmostEqual(32 / 99, draw.sx, places=10)
            self.assertAlmostEqual(32 / 99, draw.sy, places=10)
            self.assertAlmostEqual(270.5, draw.ox, places=10)
            self.assertAlmostEqual(448, draw.oy, places=10)
            self.assertAlmostEqual(670, draw.y, places=10)
        self.assertAlmostEqual(329, draws[1].x - draws[0].x, places=10)


if __name__ == "__main__":
    unittest.main()
