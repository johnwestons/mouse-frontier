"""Exercise the actual track renderer with desktop and phone-packed textures."""
from __future__ import annotations

import json
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
local function quad(x,y,w,h)
    return {x=x,y=y,w=w,h=h,
        getViewport=function(self) return self.x,self.y,self.w,self.h end}
end
love={graphics={push=noop,pop=noop,setColor=noop,newQuad=quad,
    getDimensions=function() return windowWidth,windowHeight end,
    draw=function(image,q,x,y,rotation,sx,sy)
        draws[#draws+1]={kind=image.kind,quad=q,x=x,y=y,sx=sx,sy=sy,
            imageWidth=image.width,frameHeight=image.frameHeight}
    end}}
Train=require('game.train')
function render(baseWidth,baseHeight,ballastWidth,ballastHeight,ww,wh,offset)
    draws={}; windowWidth=ww; windowHeight=wh
    local base={kind='base',width=baseWidth,frameHeight=baseHeight,
        getDimensions=function() return baseWidth,baseHeight end}
    local ballast={image={kind='ballast',width=ballastWidth,frameHeight=ballastHeight},count=4,quads={}}
    for i=1,4 do
        ballast.quads[i]=quad(0,(i-1)*ballastHeight,ballastWidth,ballastHeight)
    end
    assert(Train.drawTracks({base=base,ballastFrames=ballast},960,offset))
    return draws,Train.trackDrawPlan(960,offset,ww,wh)
end
'''


@unittest.skipIf(LuaRuntime is None, "Lua 5.1 runtime unavailable; install Lupa or set LUA_RUNTIME_PYTHONPATH")
class TrainTrackRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        config = json.loads((ROOT / "mobile" / "config.json").read_text(encoding="utf-8"))
        cls.desktop_sizes = []
        cls.mobile_sizes = []
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name, count in (("railway-track-v2.png", 1), ("railway-ballast-pocket-run-4-v1.png", 4)):
                relative = "assets/sprites/tracks/" + name
                with Image.open(ROOT / relative) as image:
                    cls.desktop_sizes.extend((image.width, image.height // count))
                with patch("tools.build_mobile_package.CACHE_ROOT", directory / "cache"):
                    optimize_image(ROOT / relative, directory / name, relative, config)
                with Image.open(directory / name) as image:
                    cls.mobile_sizes.extend((image.width, image.height // count))

    def setUp(self) -> None:
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + "/?.lua;" + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def render(self, sizes: list[int], window: tuple[int, int], offset: float):
        draws, plan = self.lua.globals().render(*sizes, *window, offset)
        return [draws[index] for index in range(1, len(draws) + 1)], plan

    @staticmethod
    def authored_point(draw, x: float, y: float) -> tuple[float, float]:
        # A point expressed on the 2172x724 source canvas must land at the same
        # world position even when its stored texture pixels have been reduced.
        return (
            draw.x + (x * draw.imageWidth / 2172 - draw.quad.x) * draw.sx,
            draw.y + y * draw.frameHeight / 724 * draw.sy,
        )

    def test_packed_base_tiles_touch_at_every_scroll_and_phone_aspect_ratio(self) -> None:
        self.assertNotEqual(self.desktop_sizes, self.mobile_sizes)
        for sizes in (self.desktop_sizes, self.mobile_sizes):
            for window in ((960, 720), (1920, 1080), (2436, 1125), (2400, 1080)):
                for offset in (-501.75, 0, 57.33, 1152, 2303.75, 5000):
                    with self.subTest(sizes=sizes, window=window, offset=offset):
                        draws, plan = self.render(sizes, window, offset)
                        edges = []
                        for draw in draws:
                            if draw.kind != "base":
                                continue
                            end = draw.x + draw.quad.w * draw.sx
                            edges.append((min(draw.x, end), max(draw.x, end)))
                            self.assertAlmostEqual(1152, abs(end - draw.x), places=8)
                            self.assertAlmostEqual(670, self.authored_point(draw, 1000, 354)[1], places=8)
                        for left, right in zip(edges, edges[1:]):
                            self.assertAlmostEqual(left[1], right[0], places=8, msg="track tiles leave a gap")
                        self.assertLessEqual(edges[0][0], plan.visibleLeft)
                        self.assertGreaterEqual(edges[-1][1], plan.visibleRight)

    def test_packed_ballast_stays_on_desktop_rock_positions_in_all_four_frames(self) -> None:
        frames_seen = set()
        for offset in (0, 6, 12, 18, 1152, 2303.75):
            desktop, _ = self.render(self.desktop_sizes, (2400, 1080), offset)
            mobile, _ = self.render(self.mobile_sizes, (2400, 1080), offset)
            self.assertEqual(len(desktop), len(mobile))
            for original, packed in zip(desktop, mobile):
                self.assertEqual(original.kind, packed.kind)
                if original.kind != "ballast":
                    continue
                frames_seen.add(round(original.quad.y / original.quad.h))
                self.assertAlmostEqual(670 + 96 / 181, self.authored_point(packed, 8, 355)[1], places=8,
                                       msg="packed ballast floats above the rail")
                for point in ((8, 355), (1096, 414), (2149, 464)):
                    for source, target in zip(self.authored_point(original, *point), self.authored_point(packed, *point)):
                        self.assertAlmostEqual(source, target, places=8, msg="phone packing moved a track/ballast anchor")
        self.assertEqual({0, 1, 2, 3}, frames_seen)

    def test_desktop_draw_geometry_keeps_existing_crop_and_scale(self) -> None:
        draws, plan = self.render(self.desktop_sizes, (960, 720), 57.33)
        for draw in draws:
            self.assertAlmostEqual(plan.drawScaleX, abs(draw.sx), places=10)
            self.assertAlmostEqual(96 / 181, draw.sy, places=10)
            self.assertAlmostEqual(670 - 354 * 96 / 181, draw.y, places=10)
            self.assertEqual(4 if draw.kind == "base" else 0, draw.quad.x)
            self.assertEqual(2164 if draw.kind == "base" else 2172, draw.quad.w)


if __name__ == "__main__":
    unittest.main()
