"""Office transitions and the mechanic's route are real gameplay state."""
from pathlib import Path
import os
import sys
import unittest
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,os.environ.get('LUA_RUNTIME_PYTHONPATH',str(ROOT/'.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime

class HomeOfficeFoxTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root=ROOT.as_posix()
        self.lua.execute("package.path=root..'/?.lua;'..package.path; Home=require('game.home_stop'); Fox=require('game.home_stop_fox'); data={scene='stop',location=1,homeStop=Home.newState(),resources={},npcStates={},stopLayouts={}}")

    def test_office_entry_exit_talk_and_resume_are_separate_from_the_yard(self):
        self.lua.execute('''
            assert(Home.target(data).action=='enterOffice')
            assert(not Home.canAdvance(data,'talk',Home.points.officeDoor))
            assert(not Home.canAdvance(data,'enterOffice',{x=700,y=500}))
            assert(Home.canAdvance(data,'enterOffice',Home.points.officeDoor))
            assert(Home.advance(data,'enterOffice').homeOfficeTransition)
            assert(Home.isOffice(data) and Home.target(data).action=='talk')
            assert(Home.advance(data,'talk').line==1)
            assert(not Home.canAdvance(data,'exitOffice',Home.points.officeExit))
            local copy=assert(require('game.save_schema').copy(data))
            assert(Home.isOffice(copy) and copy.homeStop.dialogueLine==1)
            for _=2,6 do assert(Home.advance(data,'talk')) end
            assert(Home.target(data).action=='exitOffice')
            assert(Home.advance(data,'exitOffice') and not Home.isOffice(data))
            assert(Home.target(data).action=='supplies')
            assert(require('game.scene_npcs').prepare(data,{})==nil)
        ''')

    def test_patrol_reaches_all_four_work_stops_and_completes_the_marked_loop(self):
        self.lua.execute('''
            local seen={}; local actor=Fox.ensure(data); local maxWork=0
            for _=1,15000 do
                local x,y,phase=actor.x,actor.y,actor.animationDistance
                Fox.update(data,.025)
                if actor.work then
                    seen[actor.routeIndex]=true
                    if actor.workTime>.2 then
                        assert(actor.x==x and actor.y==y and actor.animationDistance==phase,'working fox slides')
                        maxWork=math.max(maxWork,actor.workTime)
                    end
                end
                assert((actor.x-x)^2+(actor.y-y)^2<9,'patrol jumps or crosses geometry')
                if actor.rounds>=1 then break end
            end
            assert(seen[1] and seen[5] and seen[9] and seen[15],'work stop skipped at '..actor.routeIndex..' '..actor.x..','..actor.y)
            assert(actor.rounds>=1 and maxWork>3,'patrol never completed its loop')
            assert(actor.animationDistance>1000)
        ''')

    def test_patrol_resume_keeps_its_work_receipt_and_animation_distance(self):
        self.lua.execute('''
            local actor=Fox.ensure(data)
            for _=1,90 do Fox.update(data,.025) end
            local copy=assert(require('game.save_schema').copy(data))
            assert(copy.npcStates[Fox.KEY].workTime==actor.workTime)
            Fox.update(copy,.025)
            assert(copy.npcStates[Fox.KEY].workTime>actor.workTime)
            data.homeStop.stage='departed'; local time=actor.workTime
            Fox.update(data,.1); assert(actor.workTime==time)
        ''')

    def test_room_floor_and_far_train_platform_are_reachable_but_engine_is_solid(self):
        self.lua.execute('''
            local x,y=Home.move(780,500,810,500)
            assert(x==780 and y==500)
            x,y=Home.move(900,620,897,503)
            assert(math.abs(x-897)<.001 and math.abs(y-503)<.001)
            data.homeStop.inOffice=true
            local approachX,approachY=Home.officePoint(600,435)
            x,y=Home.move(Home.officeSpawn.x,Home.officeSpawn.y,approachX,approachY,data)
            assert(x==approachX and y==approachY)
            assert(Home.interaction(data,{x=x,y=y}).action=='talk')
            local edgeX,edgeY=Home.officeStandingPoint(820,575)
            x,y=Home.clamp(900,700,data); assert(x==edgeX and y==edgeY)
            local wallX,wallY=Home.officeStandingPoint(600,290)
            x,y=Home.move(approachX,approachY,wallX,wallY,data)
            local floorX,floorY=Home.officeStandingPoint(600,360)
            assert(math.abs(x-floorX)<.001 and math.abs(y-floorY)<.001,'desk is not solid')
        ''')

    def test_office_floor_reaches_rear_left_right_and_threshold_without_crossing_furniture(self):
        self.lua.execute('''
            data.homeStop.inOffice=true
            local x,y=Home.officeSpawn.x,Home.officeSpawn.y
            for _,point in ipairs({{430,450},{430,295},{240,320},{220,420},{270,560},
                {480,600},{755,535},{780,390},{620,410},{480,685}}) do
                local tx,ty=Home.officeStandingPoint(point[1],point[2])
                assert(Home.officeWalkable(tx,ty),'visible floor excluded')
                x,y=Home.move(x,y,tx,ty,data)
                assert(math.abs(x-tx)<.001 and math.abs(y-ty)<.001,'floor route blocked at '..point[1]..','..point[2])
            end
            for _,point in ipairs({{650,300},{430,200},{100,400},{120,330},{130,560},{900,500},{505,730}}) do
                local tx,ty=Home.officeStandingPoint(point[1],point[2])
                assert(not Home.officeWalkable(tx,ty),'furniture or outside room is walkable')
                local px,py=Home.clamp(tx,ty,data)
                assert(Home.officeWalkable(px,py),'clamp failed to return to floor')
            end
            local Art=require('game.home_stop_art')
            assert(Art.drawWaypoint==nil,'floating scene labels returned')
        ''')

    def test_fox_talk_is_nearby_outside_only_and_does_not_advance_the_intro(self):
        self.lua.execute('''
            local actor=Fox.ensure(data)
            local player={x=actor.x+30,y=actor.y+30}
            local target=assert(Fox.interaction(data,player))
            assert(target.kind=='homeFox' and target.action=='talk')
            local Router=require('game.interaction_router')
            assert(Router.keyAction({selected=target},'e')=='talkHomeFox')
            assert(Router.mouseAction({kind='homeFox',hovered=true},1)=='routeKey')
            assert(data.homeStop.stage=='briefing' and not data.homeStop.dialogueLine)
            assert(not Fox.interaction(data,{x=900,y=600}))
            data.homeStop.inOffice=true; assert(not Fox.interaction(data,player))
            data.homeStop.inOffice=false; data.homeStop.stage='departed'
            assert(not Fox.interaction(data,player))
        ''')

    def test_talking_preserves_work_and_walk_phase_then_resumes_the_same_route(self):
        self.lua.execute('''
            local actor=Fox.ensure(data); actor.work='checklist'
            Fox.ensure(data); assert(actor.work=='crates' and actor.file==Home.FOX)
            Fox.update(data,.1); local time=actor.workTime
            local x,y,distance=actor.x,actor.y,actor.animationDistance
            Fox.update(data,.1,{x=x-20,y=y+40})
            assert(actor.x==x and actor.y==y and actor.workTime==time and actor.animationDistance==distance)
            assert(not actor.moving and actor.intentX<0 and actor.intentY>0)
            Fox.update(data,.1); assert(actor.workTime>time and actor.routeIndex==1)
            actor.work=nil; actor.routeIndex=2
            Fox.update(data,.1); distance=actor.animationDistance; x,y=actor.x,actor.y
            Fox.update(data,.1,{x=x+30,y=y})
            assert(actor.animationDistance==distance and actor.x==x and actor.y==y)
            Fox.update(data,.1)
            assert(actor.animationDistance>distance and actor.routeIndex==2)
        ''')

    def test_every_state_renders_the_same_body_canvas_and_foot_anchor(self):
        self.lua.execute('''
            local calls,paths={},{}
            local g={setColor=function() end,ellipse=function() end,
                newQuad=function(...) return {...} end,
                draw=function(image,quad,x,y,rotation,sx,sy,ox,oy)
                    calls[#calls+1]={x=x,y=y,sx=sx,sy=sy,ox=ox,oy=oy,image=image}
                end}
            function g.newImage(path)
                assert(path:find('assets/sprites/home-stop/adult-tinker-fox/',1,true)==1,path)
                paths[#paths+1]=path
                local count=path:find('/walk',1,true) and 8 or path:find('/idle',1,true) and 2 or 4
                return {path=path,getDimensions=function() return 512*count,512 end,setFilter=function() end,release=function() end}
            end
            love={graphics=g,filesystem={getInfo=function() return {} end}}
            local actor=Fox.ensure(data); actor.intentX=1; actor.intentY=0
            for _,state in ipairs({'idle','walk','crates','wrench','oil','talk'}) do
                actor.work=(state=='crates' or state=='wrench' or state=='oil') and state or nil
                actor.moving=state=='walk'
                Fox.draw({},data,1,state=='talk')
                local c=calls[#calls]
                assert(c.sx==82/512 and c.sy==82/512,state..' changes scale')
                assert(c.ox==256,state..' changes center')
                assert(math.abs(c.y+(458-c.oy)*c.sy-actor.y)<.000001,state..' changes foot baseline')
            end
            actor.work=nil; actor.moving=true
            for _,direction in ipairs({{1,0,'walk'},{1,-1,'walk_northeast'},{0,-1,'walk_north'},
                {-1,-1,'walk_northwest'},{-1,0,'walk_west'},{-1,1,'walk_southwest'},{0,1,'walk_south'},{1,1,'walk_southeast'}}) do
                actor.intentX,actor.intentY=direction[1],direction[2]
                Fox.draw({},data,1)
                assert(calls[#calls].image.path==Fox.motionRoot..direction[3]..'.png')
            end
            assert(#paths==19)
            Fox.release()
        ''')

    def test_production_adult_frames_have_uniform_cells_scale_and_baseline(self):
        spec=json.loads((ROOT/'character-motion/home-tinker-fox.json').read_text())
        medians=[]
        for name,definition in spec['animations'].items():
            self.assertTrue(definition['path'].startswith('assets/sprites/home-stop/adult-tinker-fox/'))
            self.assertEqual((definition['frame_width'],definition['frame_height']),(512,512))
            with Image.open(ROOT/definition['path']) as sheet:
                self.assertEqual(sheet.size,(512*definition['frame_count'],512))
                heights=[]
                for index in range(definition['frame_count']):
                    alpha=sheet.crop((index*512,0,(index+1)*512,512)).getchannel('A').point(lambda a:255 if a>16 else 0)
                    box=alpha.getbbox(); self.assertIsNotNone(box,name)
                    self.assertGreaterEqual(box[0],2); self.assertLessEqual(box[2],510)
                    self.assertLessEqual(abs(box[3]-458),2,name)
                    heights.append(box[3]-box[1])
                if name!='crates':
                    self.assertGreater(min(heights)/max(heights),.90,name)
                    medians.append(sorted(heights)[len(heights)//2])
        self.assertLess(max(medians)/min(medians),1.06)

if __name__=='__main__': unittest.main()
