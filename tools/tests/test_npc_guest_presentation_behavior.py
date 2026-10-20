"""Guest resident smoothing never simulates or changes authoritative bodies."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class GuestResidentPresentationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            Presentation=require('game.npc_presentation'); NPCs=require('game.scene_npcs')
            Codec=require('game.net.codec'); Settlements=require('game.settlements')
            source={file='trail-fox.png',scene='stop',homeDoor=1,x=300,y=450,
                animationDistance=40,routineStep=4,routinePhase='travel',moving=true,facing=1,intentX=1,intentY=0}
            data={location=4,scene='stop',activeHouseDoor=1,currentNPC=source.file,
                stopLayouts={['4']={residentVersion=1,residentKeys={'resident:4:trail-fox.png'},npcOffers={}}},
                npcStates={['resident:4:trail-fox.png']=source}}
            runtime={saveData=data,scene='stop',player={x=300,y=470}}
            Presentation.update(runtime,0)
        ''')

    def test_checked_snapshot_is_followed_with_distance_gait_without_mutating_source(self):
        self.lua.execute('''
            source.x=332; source.animationDistance=72
            local encoded=assert(Codec.encode(source)); local initial=runtime.npcActor.animationDistance
            local oldX,oldY=runtime.npcActor.x,runtime.npcActor.y; local distance=0
            for i=1,30 do
                Presentation.update(runtime,.05)
                local actor=runtime.npcActor
                local moved=math.sqrt((actor.x-oldX)^2+(actor.y-oldY)^2)
                assert(moved<=48*.05+.001,'unbounded presentation motion')
                distance=distance+moved; oldX,oldY=actor.x,actor.y
            end
            assert(runtime.npcActor~=source and math.abs(runtime.npcActor.x-source.x)<=1)
            assert(math.abs(runtime.npcActor.animationDistance-initial-distance)<.001)
            assert(Codec.encode(source)==encoded,'presentation changed canonical actor')
            local gait=runtime.npcActor.animationDistance
            for i=1,30 do Presentation.update(runtime,.05) end
            assert(not runtime.npcActor.moving and runtime.npcActor.animationDistance==gait)
        ''')

    def test_home_transition_removes_outside_copy_immediately(self):
        self.lua.execute('''
            source.scene='house'; source.x=400; source.y=440
            Presentation.update(runtime,.05)
            assert(#runtime.npcActors==0 and runtime.npcActor==nil)
            runtime.scene='house'; data.scene='house'; data.activeHouseDoor=2
            Presentation.update(runtime,.05); assert(#runtime.npcActors==0)
            data.activeHouseDoor=1; Presentation.update(runtime,.05)
            assert(#runtime.npcActors==1 and runtime.npcActor.file==source.file)
            assert(runtime.npcActor.x==400 and runtime.npcActor.y==440)
        ''')

    def test_interpolation_uses_walkable_detour_and_waits_to_play_stationary_chore(self):
        self.lua.execute('''
            Settlements.isWalkable=function(_,x,y)
                return x>=100 and x<=800 and y>=395 and y<=650 and not (x>330 and x<345 and y<485)
            end
            source.x=375; source.routineAction='sweep'; source.moving=false; source.routinePhase='wait'
            local moved=false
            for i=1,140 do
                Presentation.update(runtime,.05)
                local actor=runtime.npcActor
                assert(Settlements.isWalkable(4,actor.x,actor.y))
                if actor.moving then moved=true; assert(not actor.routineAction) end
            end
            assert(moved and math.abs(runtime.npcActor.x-source.x)<=1)
            assert(runtime.npcActor.routineAction=='sweep')
        ''')

    def test_open_panel_selection_survives_another_resident_becoming_nearer(self):
        self.lua.execute('''
            local key='resident:4:cook-mouse.png'
            data.stopLayouts['4'].residentKeys[2]=key
            data.npcStates[key]={file='cook-mouse.png',scene='stop',homeDoor=2,x=600,y=450}
            runtime.peopleOpen=true; runtime.player.x=600
            Presentation.update(runtime,.05); assert(runtime.npcActor.file==source.file)
            runtime.peopleOpen=false; Presentation.update(runtime,.05)
            assert(runtime.npcActor.file=='cook-mouse.png')
        ''')


if __name__ == '__main__':
    unittest.main()
