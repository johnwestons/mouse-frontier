"""Authored transitions, one-shot actions and held-item frame synchronization."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class CharacterActionPlaybackTests(unittest.TestCase):
    def test_downed_facing_stays_fixed_until_recovery_and_is_actor_local(self):
        self.lua.execute('''
            draw('death',0,10,1); assert(drawn.sx>0 and drawn.frame==1)
            draw('death',.5,10.5,-1); assert(drawn.sx>0 and drawn.frame>1)
            draw('unconscious',0,11,-1); assert(drawn.sx>0)
            draw('unconscious',2,13,-1); assert(drawn.sx>0 and drawn.image=='unconscious')
            local first=actor; actor={}
            draw('unconscious',0,13,-1); assert(drawn.sx<0)
            actor=first; draw('unconscious',3,14,-1); assert(drawn.sx>0)
            draw('idle',0,15,-1)
            draw('death',0,16,-1); assert(drawn.sx<0)
        ''')

    def test_explicit_preview_direction_change_restarts_the_collapse(self):
        self.lua.execute('''
            local phase,state=A.previewSample(nil,'test.png','unconscious',10,set.unconscious,'E')
            A.draw(sets,'test.png','unconscious',0,0,82,104,1,phase,10,state.motion)
            local original=state.motion
            phase,state=A.previewSample(state,'test.png','unconscious',12,set.unconscious,'E')
            A.draw(sets,'test.png','unconscious',0,0,82,104,1,phase,12,state.motion)
            assert(drawn.image=='unconscious')
            phase,state=A.previewSample(state,'test.png','unconscious',13,set.unconscious,'W')
            assert(phase==0 and state.motion~=original)
            A.draw(sets,'test.png','unconscious',0,0,82,104,-1,phase,13,state.motion)
            assert(drawn.sx<0 and drawn.image=='death' and drawn.frame==1)
        ''')

    def test_viewer_lists_available_actions_and_groups_only_complete_direction_families(self):
        self.lua.execute('''
            local function animation()return {image=true,quads={1}}end
            local s={idle=animation(),walk=animation(),walk_north=animation(),sweep=animation(),
                carry=animation(),tend=animation(),wave=animation(),notAnimation={},directional=true}
            local movement,poses=A.previewActions(s)
            assert(table.concat(movement,',')=='idle,walk')
            assert(table.concat(poses,',')=='sweep,carry,tend,wave')
            s.directional=false
            movement,poses=A.previewActions(s)
            assert(table.concat(poses,',')=='sweep,carry,tend,walk_north,wave')
            movement,poses=A.previewActions(nil); assert(#movement==0 and #poses==0)
        ''')

    def test_profile_preview_starts_actions_locally_and_keeps_the_pose_actor(self):
        self.lua.execute('''
            local state
            local function preview(action,clock)
                local phase
                phase,state=A.previewSample(state,'test.png',action,clock,set[action])
                assert(A.draw(sets,'test.png',action,100,200,82,104,1,phase,clock,state.motion))
                return phase
            end
            assert(preview('melee',999)==0 and drawn.frame==1)
            local actor=state.motion
            preview('melee',999.15); assert(drawn.frame==3)
            preview('melee',999.7); assert(drawn.frame==6)
            preview('melee',1000.35); assert(drawn.frame==1)
            preview('sit',1001); assert(drawn.frame==1 and state.motion==actor)
            preview('sit',1001.28); assert(drawn.frame==3 and state.motion==actor)
            preview('sit',1002); assert(drawn.frame>=5)
            preview('idle',1002.1); assert(drawn.image=='sit' and drawn.frame==4)
        ''')

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={graphics={setColor=function() end}}
            love.graphics.draw=function(image,quad,x,y,r,sx,sy,ox,oy)
                drawn={image=image,frame=quad,sx=sx,sy=sy,x=x,y=y,ox=ox,oy=oy}
            end
            A=require('game.character_animation')
            local profiles=require('game.character_action_profiles')
            set={baseExtent=512}
            for action,p in pairs(profiles.actions) do
                set[action]={image=action,quads={1,2,3,4,5,6},count=6,w=512,h=256,
                    visibleExtent=512,bodyExtent=256,playback=p}
            end
            set.idle={image='idle',quads={1,2},count=2,w=512,h=512,visibleExtent=512}
            sets={['test.png']=set}; actor={intentX=1,intentY=0,moving=false}
            function draw(action,phase,clock,facing)
                assert(A.draw(sets,'test.png',action,100,200,82,104,facing or 1,phase,clock,actor))
                return drawn
            end
        ''')

    def test_actions_reach_every_authored_frame_and_hold_the_end(self):
        self.lua.execute('''
            for _,action in ipairs({'melee','ranged','use','hit','death'}) do
                local animation=set[action]; local duration=animation.playback.duration
                for frame=1,6 do
                    draw(action,(frame-1+.1)/6*duration,100)
                    assert(drawn.frame==frame,action..' skipped frame '..frame)
                end
                draw(action,duration*3,100)
                assert(drawn.frame==6,action..' looped instead of holding recovery')
            end
        ''')

    def test_sit_and_lay_enter_once_hold_and_reverse_when_standing(self):
        self.lua.execute('''
            for _,action in ipairs({'sit','lay'}) do
                actor={intentX=1,intentY=0,moving=false}
                local p=set[action].playback
                draw(action,999,100)
                assert(drawn.frame==1 and drawn.sy==82/256 and drawn.y==200 and drawn.sx>0)
                for frame=2,4 do
                    draw(action,999,100+(frame-1+.1)/p.fps)
                    assert(drawn.frame==frame)
                end
                for seconds=1,20 do
                    draw(action,999,100+seconds)
                    assert(drawn.frame>=5,'standing frames repeated while resting')
                end
                draw('idle',999,121)
                assert(drawn.image==action and drawn.frame==4,'standing skipped the rise transition')
                draw('idle',999,121+2.1/p.fps)
                assert(drawn.image==action and drawn.frame==2)
                draw('idle',999,122)
                assert(drawn.image=='idle','rise transition did not finish')
            end
        ''')

    def test_downed_body_collapses_before_its_breathing_loop(self):
        self.lua.execute('''
            draw('unconscious',999,50)
            assert(drawn.image=='death' and drawn.frame==1)
            draw('unconscious',999,50.5)
            assert(drawn.image=='death' and drawn.frame>1)
            draw('unconscious',999,51)
            assert(drawn.image=='unconscious' and drawn.frame==1)
            draw('unconscious',999,54)
            assert(drawn.image=='unconscious' and drawn.frame>1)
        ''')

    def test_cancelled_lowering_rises_from_the_current_pose(self):
        self.lua.execute('''
            draw('sit',999,10)
            draw('sit',999,10.13)
            assert(drawn.frame==2)
            draw('idle',999,10.14)
            assert(drawn.image=='sit' and drawn.frame==2,'cancel jumped to fully seated')
            draw('idle',999,10.27)
            assert(drawn.image=='sit' and drawn.frame==1)
            draw('idle',999,10.5)
            assert(drawn.image=='idle')
        ''')

    def test_turning_or_walking_interrupts_pose_without_restarting_its_intro(self):
        self.lua.execute('''
            draw('sit',0,10)
            draw('sit',0,12,-1)
            assert(drawn.frame>=5 and drawn.sx<0)
            actor.moving=true; actor.animationDistance=40
            set.walk={image='walk',quads={1,2,3,4,5,6},count=6,w=512,h=512}
            draw('walk',0,12.1)
            assert(drawn.image=='walk' and drawn.frame==3,'pose animation blocked walking')
            actor.moving=false; draw('sit',0,12.2)
            assert(drawn.frame==1,'a fresh sit did not restart lowering')
        ''')

    def test_weapon_uses_the_same_new_body_frame_scale_and_hand_point(self):
        self.lua.execute('''
            local W=require('game.weapon_attachment')
            love.graphics.newQuad=function() return 'patch' end
            local animation=set.ranged
            animation.handPoints={}
            for i=1,6 do animation.handPoints[i]={x=.4+i*.02,y=.5,side=1} end
            local calls={}
            love.graphics.draw=function(image,quad,x,y,r,sx,sy,ox,oy)
                calls[#calls+1]={image=image,quad=quad,x=x,y=y,sx=sx,sy=sy}
            end
            local phase=.25
            A.draw(sets,'test.png','ranged',100,200,82,104,1,phase,999,actor)
            assert(calls[1].quad==5)
            local sprite={image='weapon',quad='weapon-quad',w=100,h=40}
            assert(W.draw(sets,'test.png','frontier-rifle',sprite,100,200,82,104,1,phase,'ranged',{}))
            local expectedX=100+(.5*512-256)*82/256
            local expectedY=200+(.5*256-256)*82/256
            assert(math.abs(calls[2].x-expectedX)<.00001 and math.abs(calls[2].y-expectedY)<.00001)
            assert(calls[3].sx==calls[1].sx,'hand patch and body scale differ')
        ''')

    def test_loader_uses_six_frames_and_decoded_mobile_body_extent(self):
        self.lua.execute('''
            local profiles=require('game.character_action_profiles')
            profiles.characters['test.png']={hands={}}
            love.filesystem={getDirectoryItems=function() return {'test'} end,
                getInfo=function(path) return {type=path:match('%.png$') and 'file' or 'directory'} end}
            love.graphics.newQuad=function(x,y,w,h) return {x=x,w=w,h=h} end
            local manager=A.load('test-root',function(path)
                local action=path:match('/([^/]+)%.png$')
                local profile=action~='idle' and profiles.actions[action]
                local count=profile and 6 or 2
                local width=profile and 256*count or 128*count
                return {getDimensions=function() return width,128 end}
            end)
            local animation=manager['test.png'].melee
            assert(animation.count==6 and animation.w==256 and animation.h==128)
            assert(animation.bodyExtent==128,'mobile sheet retained the desktop pixel extent')
            assert(animation.quads[6].x==1280,'loader cut the last mobile action frame incorrectly')
            A.draw(manager,'test.png','melee',0,0,82,104,1,.25,100,actor)
            assert(math.abs(drawn.sx-82/128)<.00001 and drawn.frame==animation.quads[5])
        ''')


if __name__ == '__main__':
    unittest.main()
