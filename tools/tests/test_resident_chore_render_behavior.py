"""Guard the body scale and authored cadence of wide chore strips."""
from pathlib import Path
import hashlib
import json
import os
import sys
import unittest
from PIL import Image

if os.environ.get('LUA_RUNTIME_PYTHONPATH'):
    sys.path.insert(0, os.environ['LUA_RUNTIME_PYTHONPATH'])
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]


class ResidentChoreRenderTests(unittest.TestCase):
    def test_legacy_resident_walk_also_freezes_at_actual_distance(self):
        lua = LuaRuntime()
        lua.globals().package.path = ROOT.as_posix() + '/?.lua;' + lua.globals().package.path
        lua.execute('''
            love={graphics={setColor=function() end}}
            local frame
            love.graphics.draw=function(_,quad) frame=quad end
            local Animation=require('game.character_animation')
            local set={walk={image={},quads={1,2,3,4,5,6},w=160,h=160,count=6}}
            local actor={animationDistance=40,intentX=1,intentY=0,moving=false}
            for clock=1,20 do
                assert(Animation.draw({['legacy.png']=set},'legacy.png','walk',0,0,82,104,1,clock,clock,actor))
                assert(frame==3)
            end
            actor.animationDistance=60
            Animation.draw({['legacy.png']=set},'legacy.png','walk',0,0,82,104,1,999,999,actor)
            assert(frame==4)
        ''')

    def test_chore_canvas_preserves_body_scale_and_tool_side(self):
        lua = LuaRuntime()
        lua.globals().package.path = ROOT.as_posix() + '/?.lua;' + lua.globals().package.path
        lua.execute('''
            love={graphics={setColor=function() end}}
            local drawn
            love.graphics.draw=function(image,quad,x,y,rotation,sx,sy,ox,oy)
                drawn={frame=quad,sx=sx,sy=sy,ox=ox,oy=oy}
            end
            local Animation=require('game.character_animation')
            local set={baseExtent=512}
            for _,action in ipairs({'sweep','carry','tend'}) do
                set[action]={image={},quads={1,2,3,4},w=512,h=256,count=4,visibleExtent=512}
            end
            for action,rate in pairs({sweep=3,carry=2,tend=3}) do
                for frame=1,4 do
                    assert(Animation.draw({['resident.png']=set},'resident.png',action,
                        100,200,82,104,-1,(frame-1)/rate+.001,999,{intentX=-1,intentY=0}))
                    assert(drawn.frame==frame)
                    assert(math.abs(drawn.sx-82/256)<.00001 and drawn.sy==drawn.sx)
                    assert(drawn.ox==256 and drawn.oy==256)
                end
            end
        ''')

    def test_entire_character_roster_has_reviewed_unique_chore_frames(self):
        directory = ROOT / 'assets/sprites/character-animations'
        roster = {p.name for p in directory.iterdir() if p.is_dir()}
        ledger = json.loads((ROOT / 'character-motion/chores/acceptance.json').read_text())['characters']
        self.assertEqual(roster, set(ledger))
        for character in sorted(roster):
            record = ledger[character]
            self.assertEqual(record['status'], 'reviewed_and_installed')
            self.assertEqual(record['chore_audit']['errors'], 0)
            for action, rate in {'sweep': 3, 'carry': 2, 'tend': 3}.items():
                with self.subTest(character=character, action=action):
                    definition = record['actions'][action]
                    path = ROOT / definition['path']
                    self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), definition['sha256'])
                    self.assertEqual(definition['fps'], rate)
                    with Image.open(path) as source:
                        strip = source.convert('RGBA')
                        self.assertEqual(strip.size, (2048, 256))
                        frames = [strip.crop((i*512, 0, (i+1)*512, 256)) for i in range(4)]
                        self.assertEqual(len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames}), 4)
                        for frame in frames:
                            self.assertEqual(frame.getpixel((0, 0))[3], 0)
                            self.assertIsNotNone(frame.getchannel('A').getbbox())


if __name__ == '__main__':
    unittest.main()
