"""Authored enemy combat playback, shared asset ownership, and mobile sizing."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import sys
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime
import test_battle_ui_behavior as battle_fixture
from test_lazy_scene_asset_loading import AllocationProbe


class MobCombatAnimationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Mob=require('game.mob_combat_animation')
            function image(w,h)
                return {getDimensions=function() return w,h end}
            end
            calls={}
            love={graphics={setColor=function() end,
                newQuad=function(x,y,w,h) return {x=x,y=y,w=w,h=h} end,
                draw=function(img,quad,x,y,angle,sx,sy,ox,oy)
                    calls[#calls+1]={image=img,quad=quad,x=x,y=y,sx=sx,sy=sy,ox=ox,oy=oy}
                end}}
        ''')

    def test_all_mobs_have_full_suites_and_generated_art_matches_reviewed_hashes(self):
        profiles = self.lua.globals().Mob.profiles
        ordinary = {path.name for path in (ROOT / 'assets/sprites/Mobs').glob('*.png')}
        self.assertEqual(ordinary | {'sludge-bandit.png', 'sludge-badger-boss.png'}, set(profiles))
        generated = []
        for name, profile in profiles.items():
            self.assertGreater(profile.bodyExtent, 0)
            self.assertIn(profile.baseFacing, (-1, 1))
            self.assertEqual({'melee', 'ranged', 'hit', 'death'}, set(profile.paths))
            for action, relative in profile.paths.items():
                with self.subTest(mob=name, action=action), Image.open(ROOT / relative) as opened:
                    strip = opened.convert('RGBA')
                    self.assertEqual((3072, 256), strip.size)
                    frames = [strip.crop((i * 512, 0, (i + 1) * 512, 256)) for i in range(6)]
                    self.assertEqual(6, len({frame.tobytes() for frame in frames}))
                    for frame in frames:
                        self.assertEqual(0, frame.getpixel((0, 0))[3])
                        box = frame.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
                        self.assertIsNotNone(box)
                        self.assertGreater(min(box[0], box[1], 512 - box[2], 256 - box[3]), 2)
            spec_path = ROOT / f'mob-motion/combat/{name[:-4]}.json'
            if spec_path.exists():
                spec = json.loads(spec_path.read_text(encoding='utf-8'))
                self.assertEqual('reviewed_and_installed', spec['status'])
                self.assertEqual('combat-only', spec['scope'])
                for action, relative in profile.paths.items():
                    self.assertEqual(spec['hashes'][action], hashlib.sha256((ROOT / relative).read_bytes()).hexdigest())
                generated.append(name)
        self.assertEqual(18, len(generated))

    def test_attack_hit_priority_restart_and_death_play_once_then_hold(self):
        self.lua.execute('''
            local unit={file='cactus-rat.png',hp=10,action='melee',actionTimer=.68}
            for frame=1,6 do
                unit.actionTimer=.68*(1-(frame-1)/6)
                local action,index=Mob.frame(unit,(frame-1)*.1,1)
                assert(action=='melee' and index==frame,'attack frame '..frame..' was skipped')
            end
            unit.actionTimer=.68
            local _,index=Mob.frame(unit,.7,1);assert(index==1,'new strike did not restart')
            for frame=1,6 do
                unit.hitTimer=.58*(1-(frame-1)/6)
                local action,index=Mob.frame(unit,.8+(frame-1)*.1,1)
                assert(action=='hit' and index==frame,'hit frame '..frame..' was skipped')
            end
            unit.hp=0
            for frame=1,6 do
                local action,index,facing=Mob.frame(unit,2+(frame-1)*.85/6,frame==1 and -1 or 1)
                assert(action=='death' and index==frame,'collapse frame '..frame..' was skipped')
                assert(facing==-1,'fallen mob turned around')
            end
            local _,index=Mob.frame(unit,50,1);assert(index==6,'death looped or returned to standing')
            unit.hp=10;unit.hitTimer=0;unit.actionTimer=0
            assert(Mob.frame(unit,51,1)==nil,'surviving idle changed')
            unit.hp=0;local _,index=Mob.frame(unit,52,1);assert(index==1,'new collapse did not restart')
        ''')

    def test_guest_snapshot_replacements_keep_collapse_and_facing_until_new_encounter(self):
        self.lua.execute('''
            local ctx={ui={},battle={encounterId='one'},mobDeathImages={['cactus-rat.png@combat']=image(3072,256)}}
            local function draw(t,facing)
                -- Network projection replaces the unit table every revision.
                local unit={id='enemy1',file='cactus-rat.png',hp=0}
                assert(Mob.draw(ctx,unit,100,150,76,96,facing,t))
                return calls[#calls]
            end
            assert(draw(0,-1).quad.x==0)
            local last=draw(2,1);assert(last.quad.x==5*512 and last.sx<0)
            ctx.battle={encounterId='two'}
            assert(draw(3,1).quad.x==0,'new encounter reused an old collapse')
        ''')

    def test_mobile_and_desktop_decode_different_cell_sizes_at_identical_world_scale(self):
        self.lua.execute('''
            local ctx={ui={},battle={},mobAttackImages={}}
            local unit={file='mouse-bandit.png',hp=10,action='melee',actionTimer=.68}
            for _,height in ipairs({256,128}) do
                ctx.mobAttackImages['mouse-bandit.png@combat']=image(height*12,height)
                assert(Mob.draw(ctx,unit,400,300,76,96,1,0))
            end
            local a,b=calls[1],calls[2]
            assert(a.quad.w==512 and b.quad.w==256)
            assert(math.abs(a.quad.h*a.sy-b.quad.h*b.sy)<.00001,'mobile body scale changed')
            assert(a.x==b.x and a.y==b.y and a.oy*a.sy==b.oy*b.sy,'mobile anchor moved')
        ''')

    def test_mobile_packaging_preserves_complete_six_frame_cells(self):
        spec = importlib.util.spec_from_file_location('mob_mobile_builder', ROOT / 'tools/build_mobile_package.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for path in (ROOT / 'assets/sprites/Mobs/combat').rglob('*.png'):
            relative = path.relative_to(ROOT).as_posix()
            self.assertTrue(module.runtime_asset(path))
            self.assertEqual((1536, 128), module.image_bounds(relative, {'characterAnimationFrameSize': 128}, (3072, 256)))
        with self.assertRaises(ValueError):
            module.image_bounds('assets/sprites/Mobs/combat/test/hit.png', {'characterAnimationFrameSize': 128}, (1000, 256))

    def test_lazy_combat_images_keep_field_sprites_and_retain_by_original_mob_key(self):
        probe = AllocationProbe()
        probe.lua.execute('''
            local file='cactus-rat.png'
            local old=targets.mobAttackImages[file]
            local clip=targets.mobAttackImages[file..'@combat']
            assert(old~=clip,'battle art replaced the field sprite')
            assert(targets.mobAttackImages[file..'@combat']==clip,'warm combat art was reloaded')
            Assets.retainAnimationImages({targets.mobAttackImages},{[file]=true})
            assert(rawget(targets.mobAttackImages,file..'@combat')==clip,'visible mob lost its combat sheet')
            Assets.retainAnimationImages({targets.mobAttackImages},{})
            assert(rawget(targets.mobAttackImages,file..'@combat')==nil,'departed mob retained combat art')
        ''')


class MobCombatBattleUITests(unittest.TestCase):
    setUp = battle_fixture.BattleUIBehaviorTests.setUp

    def test_enemy_battle_draw_uses_one_action_cell_and_preserves_alive_idle(self):
        self.lua.execute('''
            local enemy=ctx.battle.units[3];enemy.file='cactus-rat.png';enemy.action='melee';enemy.actionTimer=.68
            local clip={getDimensions=function() return 3072,256 end}
            ctx.mobAttackImages['cactus-rat.png@combat']=clip
            local draws={}
            love.graphics.newQuad=function(x,y,w,h) return {x=x,y=y,w=w,h=h} end
            love.graphics.draw=function(image,quad) if image==clip then draws[#draws+1]=quad end end
            UI.draw(ctx);assert(#draws==1 and draws[1].w==512 and draws[1].x==0)
            enemy.actionTimer=.2;ctx.animationClock=.48
            UI.draw(ctx);assert(#draws==2 and draws[2].x>=4*512)
            enemy.actionTimer=0;UI.draw(ctx);assert(#draws==2,'ordinary idle was replaced by combat art')
        ''')


if __name__ == '__main__':
    unittest.main()
