"""The home yard has its own actors, floor and streamed art before Stop 1."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/coop-python-deps')))
from lupa.lua51 import LuaRuntime


class HomeSceneTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            Home=require('game.home_stop')
            data={scene='stop',location=1,homeStop=Home.newState(),npcStates={},stopLayouts={}}
        ''')

    def test_conductor_only_appears_inside_the_office(self):
        self.lua.execute('''
            local NPCs=require('game.scene_npcs')
            assert(NPCs.prepare(data,{})==nil)
            data.homeStop.inOffice=true
            local actor=NPCs.prepare(data,{})
            assert(data.currentNPC=='tortoise-conductor.png')
            assert(actor.x==Home.points.conductor.x and actor.y==Home.points.conductor.y)
            assert(not actor.family and not actor.weapon and not actor.targetX and not actor.moving)
            assert(data.npcStates['stop:1']==nil)
            actor.x=800; actor.targetX=900; actor.moving=true
            assert(NPCs.prepare(data,{})==actor and actor.x==Home.points.conductor.x)
            assert(not actor.targetX and not actor.moving)
        ''')

    def test_host_and_prediction_use_the_yard_floor_until_departure(self):
        self.lua.execute('''
            local Settlements=require('game.settlements')
            local calls=0
            Settlements.move=function(_,ox,oy,x,y) calls=calls+1; return ox,oy end
            local collision=require('game.coop_collision').new({car={},scenery={}})
            local x,y=collision(data,{},420,565,950,700)
            assert(x==930 and y==650 and calls==0,tostring(x)..','..tostring(y))
            x,y=collision(data,{},420,565,20,40)
            assert(x>=50 and y>=280 and calls==0)
            data.homeStop.stage='departed'
            x,y=collision(data,{},420,565,480,565)
            assert(x==420 and y==565 and calls>0)
        ''')

    def test_home_background_is_lazy_and_can_be_released_and_reopened(self):
        self.lua.execute('''
            local loaded,released,drawn=0,0,{}
            local background={getWidth=function() return 1200 end,getHeight=function() return 900 end,
                setFilter=function() end,release=function() released=released+1 end}
            love={filesystem={getInfo=function(path) assert(path=='assets/sprites/stops/home-yard-v3.png' or path=='assets/sprites/stops/home-office-exterior-v2.png'); return {} end},
                graphics={newImage=function() loaded=loaded+1; return background end,setColor=function() end,
                    draw=function(image) drawn[#drawn+1]=image end}}
            local Art=require('game.home_stop_art')
            assert(loaded==0)
            Art.draw({},960,720)
            Art.draw({},960,720)
            assert(loaded==2 and #drawn==4 and drawn[1]==background and drawn[2]==background)
            Art.release(); Art.release(); assert(released==2)
            Art.draw({},960,720); assert(loaded==4)
        ''')

    def test_parked_train_blocks_crossing_but_all_preparation_points_remain_reachable(self):
        self.lua.execute('''
            local x,y=Home.clamp(800,500)
            assert(x==780 and y==500)
            x,y=Home.clamp(880,570)
            assert(x==885 and y==570)
            x,y=Home.move(770,480,820,500)
            assert(math.abs(x-780)<.001 and math.abs(y-500)<.001)
            x,y=Home.move(880,650,650,420)
            assert(x<=780 or y>=580)
            assert(y>420,'long corrections must slide around the train rather than pass through it')
            local px,py=420,565
            for _,name in ipairs({'officeDoor','supplies','repair','train'}) do
                local target=Home.points[name]
                px,py=Home.move(px,py,target.x,target.y)
                assert(math.abs(px-target.x)<.001 and math.abs(py-target.y)<.001,name..' is unreachable')
            end
        ''')

    def test_host_and_prediction_reach_the_upper_office_floor(self):
        self.lua.execute('''
            data.homeStop.inOffice=true
            local collision=require('game.coop_collision').new({car={},scenery={}})
            local tx,ty=Home.officeStandingPoint(430,295)
            local x,y=collision(data,{},Home.officeSpawn.x,Home.officeSpawn.y,tx,ty)
            assert(x==tx and y==ty and Home.officeWalkable(x,y))
            local px,py=Home.move(Home.officeSpawn.x,Home.officeSpawn.y,tx,ty,data)
            assert(px==x and py==y,'host and prediction disagree on office walk mask')
        ''')

    def test_yard_retains_conductor_motion_without_loading_stop_one_background(self):
        self.lua.execute('''
            local Animation=require('game.character_animation')
            local Assets=require('game.assets')
            local retained
            Animation.retain=function(_,keep) retained=keep end
            Assets.retainAnimationImages=function() end
            local streamer=require('game.asset_streamer').new({characterAnimations={},interiorFiles={}})
            streamer:update('game','stop',data)
            assert(retained['tortoise-conductor.png'] and streamer.lastSettlement==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
