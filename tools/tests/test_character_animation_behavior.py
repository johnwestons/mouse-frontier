"""Exercise the production sprite renderer rather than a copied preview timer."""
from pathlib import Path
import json
import os
import sys
import unittest
if os.environ.get('LUA_RUNTIME_PYTHONPATH'):
    sys.path.insert(0, os.environ['LUA_RUNTIME_PYTHONPATH'])
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).resolve().parents[2]

HARNESS = r'''
love = {graphics = {setColor = function() end}}
drawn = nil
love.graphics.draw = function(image, quad, x, y, rotation, sx, sy, ox, oy)
    drawn = {action=image, frame=quad, x=x, y=y, sx=sx, sy=sy, ox=ox, oy=oy}
end
Animation = require('game.character_animation')
Motion = require('game.character_motion')
directions = {{0,-1,'_north'},{1,-1,'_northeast'},{1,0,''},{1,1,'_southeast'},
              {0,1,'_south'},{-1,1,'_southwest'},{-1,0,'_west'},{-1,-1,'_northwest'}}
function makeSet(directional, authoredWest)
    local set={directional=directional,authoredWest=authoredWest,motionProfile=Motion.defaults,baseExtent=512}
    for _,direction in ipairs(directions) do
        for _,prefix in ipairs({'idle','walk','run'}) do
            local action=prefix..direction[3]
            set[action]={image=action,quads={1,2,3,4,5,6,7,8},w=512,h=512,
                count=prefix=='idle' and 2 or 8,visibleExtent=512}
        end
    end
    return {['test.png']=set}
end
function draw(sets, action, clock, actor)
    assert(Animation.draw(sets,'test.png',action,100,200,128,128,1,clock,999,actor))
    return drawn
end
'''

@unittest.skipIf(LuaRuntime is None, 'Lua 5.1 runtime unavailable; set LUA_RUNTIME_PYTHONPATH')
class CharacterAnimationBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = ROOT.as_posix() + '/?.lua;' + self.lua.globals().package.path
        self.lua.execute(HARNESS)

    def test_installed_calibrated_profiles_match_canonical_motion_specs(self):
        for filename, tuning in self.lua.globals().Motion.profiles.items():
            if tuning['runPixelsPerFrame'] is None:
                continue
            with self.subTest(character=filename):
                character = Path(filename).stem
                spec = json.loads((ROOT / 'character-motion' / (character + '.json')).read_text())
                self.assertAlmostEqual(tuning['pixelsPerFrame'], spec['gait']['pixels_per_frame'])
                self.assertAlmostEqual(tuning['runPixelsPerFrame'], spec['run_gait']['pixels_per_frame'])
                for direction in spec['directions'].values():
                    self.assertFalse(direction['mirror_x'])
                    for action in ('walk_animation', 'idle_animation', 'run_animation'):
                        staged = ROOT / spec['animations'][direction[action]]['path']
                        installed = ROOT / 'assets/sprites/character-animations' / character / staged.name
                        self.assertEqual(installed.read_bytes(), staged.read_bytes())

    def test_every_installed_directional_walk_suite_is_loaded_and_used(self):
        root = ROOT / 'assets' / 'sprites' / 'character-animations'
        required = {
            'walk.png', 'walk_north.png', 'walk_northeast.png', 'walk_southeast.png', 'walk_south.png',
            'idle.png', 'idle_north.png', 'idle_northeast.png', 'idle_southeast.png', 'idle_south.png',
        }
        asset_dirs = {
            directory.name: {path.name for path in directory.iterdir() if path.is_file()}
            for directory in root.iterdir() if directory.is_dir()
        }
        suites = {name: files for name, files in asset_dirs.items() if required <= files}
        self.assertGreaterEqual(len(suites), 40, 'the audit should cover the installed directional character roster')

        lua_dirs = self.lua.table()
        for name, files in asset_dirs.items():
            lua_files = self.lua.table()
            for filename in files:
                lua_files[filename] = True
            lua_dirs[name] = lua_files
        self.lua.globals().assetDirs = lua_dirs
        self.lua.globals().directionalSuites = self.lua.table_from(sorted(suites))
        self.lua.execute(r'''
            local noop=function() end
            love.filesystem={
                getDirectoryItems=function(path)
                    if path~='assets/sprites/character-animations' then return {} end
                    local names={}; for name in pairs(assetDirs) do names[#names+1]=name end; table.sort(names); return names
                end,
                getInfo=function(path)
                    if path=='assets/sprites/character-animations' then return {type='directory'} end
                    local directory=path:match('^assets/sprites/character%-animations/([^/]+)$')
                    if directory and assetDirs[directory] then return {type='directory'} end
                    local name,filename=path:match('^assets/sprites/character%-animations/([^/]+)/(.+)$')
                    if name and assetDirs[name] and assetDirs[name][filename] then return {type='file'} end
                    return nil
                end,
            }
            love.graphics.newQuad=function(x,y,w,h)
                return {frame=math.floor(x/w)+1}
            end
            love.graphics.draw=function(image,quad)
                drawn={image=image.path,frame=quad.frame}
            end
            local function imageLoader(path)
                local name,filename=path:match('^assets/sprites/character%-animations/([^/]+)/(.+)$')
                if not (name and assetDirs[name] and assetDirs[name][filename]) then return nil end
                local action=filename:gsub('%.png$','')
                local count=(action:match('^walk') or action:match('^run')) and 8
                    or (action:match('^idle') or action=='sit' or action=='lay' or action=='unconscious') and 2 or 3
                return {path=path,getDimensions=function() return count*64,64 end}
            end
            local manager=Animation.load('assets/sprites/character-animations',imageLoader)
            local directions={{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}}
            local checked=0
            for _,name in ipairs(directionalSuites) do
                local file=name..'.png'
                local set=manager[file]
                assert(set and set.directional, file..' has a suite but was not registered for directional movement')
                for _,direction in ipairs(directions) do
                    local action=Motion.directionalWalkAction(direction[1],direction[2],set.authoredWest)
                    local animation=set[action]
                    assert(animation, file..' is missing selected view '..action)
                    drawn=nil
                    local stride=set.motionProfile.pixelsPerFrame
                    assert(Animation.draw(manager,file,'walk',100,100,82,104,1,0,0,{
                        intentX=direction[1],intentY=direction[2],animationDistance=stride*2,
                    }))
                    assert(drawn.image==animation.image.path, file..' did not draw '..action)
                    assert(drawn.frame==3, file..' did not advance from its traveled distance')
                end
                checked=checked+1
            end
            assert(checked==#directionalSuites)
        ''')

    def test_all_authored_directional_idles_use_the_spec_cadence(self):
        self.lua.execute(r'''
            local sets=makeSet(true,true)
            for _,direction in ipairs(directions) do
                for _,clock in ipairs({0,.2,.8,1.5,1.54,2.9,3.08,4.7}) do
                    local result=draw(sets,'idle',clock,{intentX=direction[1],intentY=direction[2]})
                    assert(result.action=='idle'..direction[3], 'wrong idle sector')
                    assert(result.frame==math.floor(clock*.65)%2+1, 'wrong cadence: '..result.action..' at '..clock)
                    assert(result.sx==.25 and result.sy==.25, 'authored idle must not mirror')
                end
            end
        ''')

    def test_intentionally_mirrored_idles_keep_direction_and_cadence(self):
        self.lua.execute(r'''
            local sets=makeSet(true,false)
            for _,direction in ipairs(directions) do
                local expected,mirror=Motion.directionalIdleAction(direction[1],direction[2],false)
                local result=draw(sets,'idle',1.5,{intentX=direction[1],intentY=direction[2]})
                assert(result.action==expected and result.frame==1)
                assert(result.sx==.25*mirror)
            end
        ''')

    def test_authored_western_idles_never_use_the_fast_action_default(self):
        self.lua.execute(r'''
            local sets=makeSet(true,true)
            for _,direction in ipairs({{-1,0,'_west'},{-1,-1,'_northwest'},{-1,1,'_southwest'}}) do
                local result=draw(sets,'idle',.2,{intentX=direction[1],intentY=direction[2]})
                assert(result.action=='idle'..direction[3] and result.frame==1,
                    'western idle incorrectly uses the 6fps action fallback')
            end
        ''')

    def test_directional_walk_frames_depend_on_distance_not_clock(self):
        self.lua.execute(r'''
            local sets=makeSet(true,true)
            for _,direction in ipairs(directions) do
                for phase=1,8 do
                    for _,clock in ipairs({0,77,999}) do
                        local result=draw(sets,'walk',clock,{intentX=direction[1],intentY=direction[2],animationDistance=(phase-1)*20})
                        assert(result.action=='walk'..direction[3] and result.frame==phase)
                        assert(result.sx==.25 and result.ox==256 and result.oy==512)
                    end
                end
            end
        ''')

    def test_legacy_idle_cadence_is_unchanged(self):
        self.lua.execute(r'''
            local result=draw(makeSet(false,false),'idle',1.5,nil)
            assert(result.frame==2, 'legacy .70 cadence changed')
        ''')

    def test_run_uses_shared_phase_and_all_authored_views(self):
        self.lua.execute(r'''
            local sets=makeSet(true,true);local set=sets['test.png']
            set.runDirectional=true
            set.motionProfile={pixelsPerFrame=2.5625,runPixelsPerFrame=6.005859375}
            assert(Motion.hasRunSet(set))
            for _,direction in ipairs(directions) do
                local a={intentX=direction[1],intentY=direction[2],animationDistance=999,
                    posePhase=4.25,locomotionMode='run'}
                local result=draw(sets,'walk',77,a)
                assert(result.action=='run'..direction[3] and result.frame==5)
                assert(result.sx==.25, 'run equipment was mirrored')
                a.locomotionMode='walk'
                result=draw(sets,'walk',77,a)
                assert(result.action=='walk'..direction[3] and result.frame==5)
                result=draw(sets,'idle',1,a)
                assert(result.action=='idle'..direction[3])
            end
            set.run_west=nil;assert(not Motion.hasRunSet(set))
        ''')

    def test_walk_run_transition_preserves_phase_and_actual_distance(self):
        self.lua.execute(r'''
            local profile={};for k,v in pairs(Motion.defaults) do profile[k]=v end
            profile.pixelsPerFrame=2.5625;profile.runPixelsPerFrame=6.005859375
            profile.runSpeedThreshold=60;profile.runSpeedHysteresis=10
            local a={x=0,y=0};Motion.resetActor(a)
            local sawWalk,sawRun=false,false
            for i=1,120 do
                local phase=a.posePhase or 0;local distance=a.animationDistance
                local moved=Motion.updateActor(a,1,0,1/60,{speed=i<60 and 185 or 32,profile=profile})
                local stride=a.locomotionMode=='run' and profile.runPixelsPerFrame or profile.pixelsPerFrame
                assert(math.abs(a.posePhase-phase-moved/stride)<1e-8)
                assert(math.abs(a.animationDistance-distance-moved)<1e-8)
                sawWalk=sawWalk or a.locomotionMode=='walk';sawRun=sawRun or a.locomotionMode=='run'
                local speed,accel=Motion.sample(phase*profile.pixelsPerFrame,profile)
                assert(math.abs(a.gaitSpeedMultiplier-speed)<1e-8)
                assert(math.abs(a.gaitAccelerationMultiplier-accel)<1e-8)
            end
            assert(sawWalk and sawRun and a.locomotionMode=='walk')
            local phase,distance=a.posePhase,a.animationDistance
            for i=1,30 do Motion.updateActor(a,1,0,1/60,{speed=185,profile=profile,
                move=function(x,y) return x,y end}) end
            assert(a.posePhase==phase and a.animationDistance==distance)
        ''')

    def test_run_hysteresis_and_legacy_profile_do_not_flicker(self):
        self.lua.execute(r'''
            local p={};for k,v in pairs(Motion.defaults) do p[k]=v end
            p.pixelsPerFrame=2.5625;p.runPixelsPerFrame=6;p.runSpeedThreshold=60;p.runSpeedHysteresis=10
            local a={x=0,y=0};Motion.resetActor(a)
            local function step(speed)
                a.velocityX=speed
                Motion.updateActor(a,1,0,.01,{speed=speed,profile=p})
            end
            step(70);assert(a.locomotionMode=='run')
            step(55);assert(a.locomotionMode=='run')
            step(40);assert(a.locomotionMode=='walk')
            step(55);assert(a.locomotionMode=='walk')
            local legacy={x=0,y=0};Motion.resetActor(legacy)
            Motion.updateActor(legacy,1,0,.1,{speed=185})
            assert(legacy.posePhase==nil and legacy.locomotionMode==nil)
            assert(Motion.frameForActor(8,legacy,Motion.defaults)==Motion.frameForDistance(8,legacy.animationDistance,20))
        ''')

    def test_stopping_preserves_idle_view_after_actual_motion(self):
        self.lua.execute(r'''
            local sets=makeSet(true,true)
            for _,direction in ipairs(directions) do
                local actor={x=0,y=0,facing=1}; Motion.resetActor(actor)
                Motion.updateActor(actor,direction[1],direction[2],.1,{speed=185})
                for i=1,100 do Motion.updateActor(actor,0,0,.02,{speed=185}) end
                assert(not actor.moving)
                local result=draw(sets,'idle',actor.idleClock,actor)
                assert(result.action=='idle'..direction[3])
                assert(result.frame==math.floor(actor.idleClock*.65)%2+1)
            end
        ''')

if __name__ == '__main__':
    unittest.main()
