"""Resident occupancy, interrupted chores and real collision-resolved routes."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get('LUA_RUNTIME_PYTHONPATH', str(ROOT / '.stabilization/python-deps')))
from lupa.lua51 import LuaRuntime


class ResidentRoutineTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Catalog=require('game.catalog')
            NPCs=require('game.scene_npcs'); Routines=require('game.npc_routines')
            Settlements=require('game.settlements'); Stops=require('game.stops')
            Schema=require('game.save_schema'); Codec=require('game.net.codec')
            data=F.campaign(4,{scene='stop',npcRoster={'trail-fox.png','cook-mouse.png','botanist-frog.png','watch-raccoon.png'}})
            count=0
            rng=function()
                count=count+1
                return (count*37%97)/97
            end
            ready=function(actor,step,phase)
                Routines.update(data,actor,.05)
                actor.routineDelay=0
                actor.routineStep=step or actor.routineStep
                actor.routinePhase=phase or 'travel'; actor.routineClock=0
            end
        ''')

    def load_interior_files(self):
        self.lua.globals().interiorFiles = self.lua.table_from([
            'frontier-cabin.png', 'railway-cottage.png', 'desert-adobe.png',
            'forest-homestead.png', 'station-house.png',
        ] + sorted(path.name for path in (ROOT / 'assets/sprites/interiors').glob('stop??-interior-??.png')))

    def test_legacy_interior_migration_replaces_live_route_and_return_doorway(self):
        self.load_interior_files()
        self.lua.execute('''
            data=F.campaign(6,{scene='stop',npcRoster={'trail-fox.png','cook-mouse.png','botanist-frog.png','watch-raccoon.png'}})
            NPCs.prepare(data,Catalog,rng)
            local layout=data.stopLayouts['6']; local home=layout.houseDoors['2']
            local actor
            for _,key in ipairs(layout.residentKeys) do
                if data.npcStates[key].homeDoor==2 then actor=data.npcStates[key] end
            end
            assert(actor and interiorFiles[2]=='railway-cottage.png' and interiorFiles[32]=='stop06-interior-02.png')
            home.interior=2; layout.interior=2
            actor.scene='house'; actor.x,actor.y=500,420; ready(actor,2)
            for i=1,10 do Routines.update(data,actor,.05,{interiorFiles=interiorFiles}) end
            local Doors=require('game.interior_doors'); local oldX,oldY=Doors.spawnPoint(2,interiorFiles)
            assert(actor.targetX==oldX and actor.targetY==oldY and actor.velocityX<0)
            data.scene='house'; data.activeHouseDoor=2
            require('game.house').ensure(data,Catalog,function(name) return Catalog.storageCapacities[name]~=nil end,rng)
            assert(home.interior==32,'legacy room did not migrate to its stop painting')
            local newX,newY=Doors.spawnPoint(32,interiorFiles)
            Routines.update(data,actor,.05,{interiorFiles=interiorFiles})
            assert(actor.targetX==newX and actor.targetY==newY and actor.velocityX>0,
                'resident kept the old left-door route after the new right-door painting loaded')
            for i=1,500 do
                Routines.update(data,actor,.05,{interiorFiles=interiorFiles})
                if actor.scene=='stop' then break end
            end
            assert(actor.scene=='stop','resident could not exit the migrated room')
            actor.routineStep=7; actor.routinePhase='travel'; actor.routineDelay=0
            Routines.update(data,actor,.05,{interiorFiles=interiorFiles})
            assert(actor.scene=='house' and actor.x==newX and actor.y==newY,
                'returning home used the stale arrival doorway')
        ''')

    def test_assignment_is_unique_and_repeat_preparation_preserves_progress(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local layout=data.stopLayouts['4']; assert(#layout.residentKeys==4)
            local identities={}
            for _,key in ipairs(layout.residentKeys) do
                local actor=data.npcStates[key]; assert(not identities[actor.file]); identities[actor.file]=true
                assert(layout.houseDoors[tostring(actor.homeDoor)])
            end
            local actor=data.npcStates[layout.residentKeys[1]]
            actor.routineStep=5; actor.routineClock=1.3; actor.x=400
            local calls=count
            NPCs.prepare(data,Catalog,rng)
            assert(count==calls,'repeat preparation consumed random generation')
            assert(actor.routineStep==5 and actor.routineClock==1.3 and actor.x==400)
        ''')

    def test_complete_routine_changes_one_body_between_home_and_stop(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local actor=data.npcStates[data.stopLayouts['4'].residentKeys[2]]
            local seen,actions={},{}
            local transfers=0; local previous=actor.scene
            local moved=0
            for i=1,30000 do
                local x,y=actor.x,actor.y
                Routines.update(data,actor,.05)
                moved=moved+math.sqrt((actor.x-x)^2+(actor.y-y)^2)
                seen[actor.routineStep]=true
                if actor.routineAction then actions[actor.routineAction]=true end
                if actor.scene~=previous then transfers=transfers+1; previous=actor.scene end
                local outside=NPCs.find(data,actor.file,'stop')
                local inside=NPCs.find(data,actor.file,'house',actor.homeDoor)
                assert((outside==actor)~=(inside==actor),'resident has duplicate or absent occupancy')
                assert(not NPCs.find(data,actor.file,'house',actor.homeDoor%3+1),'wrong home contains resident')
                if actor.scene=='stop' then assert(Settlements.isWalkable(4,actor.x,actor.y)) end
            end
            for i=1,8 do assert(seen[i],'missing routine step '..i) end
            assert(actions.sweep and actions.carry and actions.tend)
            assert(transfers>=2 and moved>300 and actor.animationDistance>0)
        ''')

    def test_pause_holds_position_phase_and_gait_then_resumes(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local actor=data.npcStates[data.stopLayouts['4'].residentKeys[1]]
            ready(actor,4)
            for i=1,8 do Routines.update(data,actor,.05) end
            local x,y,step,clock,gait=actor.x,actor.y,actor.routineStep,actor.routineClock,actor.animationDistance
            local random,delay=actor.routineRandom,actor.routineDelay
            for i=1,200 do Routines.update(data,actor,.05,{held=true}) end
            assert(actor.x==x and actor.y==y and actor.routineStep==step and actor.routineClock==clock)
            assert(actor.animationDistance==gait and not actor.moving and not actor.routineAction)
            assert(actor.routineRandom==random and actor.routineDelay==delay)
            for i=1,80 do Routines.update(data,actor,.05) end
            assert(actor.x~=x or actor.y~=y or actor.routineStep~=step)
        ''')

    def test_residents_start_at_different_times_and_do_not_consume_global_randomness(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            math.random=function() error('resident schedule used shared randomness') end
            local delays,durations,steps={},{},{}
            local smallest,largest=1000,0
            for _,key in ipairs(data.stopLayouts['4'].residentKeys) do
                local actor=data.npcStates[key]; local x,y=actor.x,actor.y
                Routines.update(data,actor,.05)
                assert(actor.routineVersion==Routines.VERSION and not actor.moving and not actor.routineAction)
                assert(actor.x==x and actor.y==y and actor.routineDelay>=7.9 and actor.routineDelay<=50)
                assert(not delays[actor.routineDelay],'residents share an initial departure time')
                delays[actor.routineDelay]=true; durations[actor.routineDuration]=true; steps[actor.routineStep]=true
                smallest=math.min(smallest,actor.routineDelay); largest=math.max(largest,actor.routineDelay)
            end
            assert(largest-smallest>10,'initial work is still clustered together')
            local count=0; for _ in pairs(steps) do count=count+1 end
            assert(count>1,'everyone starts with the same activity')
        ''')

    def test_chores_have_long_breaks_cooldowns_and_paired_supply_delivery(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local actor=data.npcStates[data.stopLayouts['4'].residentKeys[1]]
            ready(actor,3,'wait'); actor.routineDuration=1; actor.routineClock=1
            actor.routineOutdoorRemaining=3
            Routines.update(data,actor,.05)
            assert(actor.routineStep==4 or actor.routineStep==6,'sweeping immediately repeated')
            assert(actor.routineCooldowns.sweep>=85 and actor.routineCooldowns.sweep<=160)
            assert(actor.routineDelay>=18 and actor.routineDelay<=45)
            local x,y,step=actor.x,actor.y,actor.routineStep
            for i=1,300 do Routines.update(data,actor,.05) end
            assert(actor.x==x and actor.y==y and not actor.moving and not actor.routineAction)
            assert(actor.routineStep==step,'no real pause separated chores')
            actor.routineStep=4; actor.routinePhase='wait'; actor.routineClock=5
            actor.routineDuration=3; actor.routineDelay=0
            Routines.update(data,actor,.05)
            assert(actor.routineStep==5 and actor.routineDelay==0,'supplies were abandoned after loading')
            actor.routinePhase='wait'; actor.routineClock=5; actor.routineOutdoorRemaining=1
            Routines.update(data,actor,.05)
            assert(actor.routineStep==7 and actor.routineLastChore=='carry')
            assert(actor.routineDelay>=18,'delivery had no break')
            local doorX,doorY=Settlements.doorPoint(data.location,actor.homeDoor)
            actor.x,actor.y=Settlements.clamp(doorX,doorY+18,data.location); actor.routineDelay=0
            Routines.update(data,actor,.05)
            assert(actor.scene=='house' and actor.routineStep==8)
            assert(actor.routineDuration>=40 and actor.routineDuration<=110,'home break was still short')
        ''')

    def test_chore_order_and_outing_lengths_vary_without_synchronized_repeats(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local residents={}
            for _,key in ipairs(data.stopLayouts['4'].residentKeys) do
                residents[#residents+1]=data.npcStates[key]
            end
            local histories,counts,firstStarts={},{},{}
            local outingSizes,nextAfterSweep={},{}
            for _,actor in ipairs(residents) do histories[actor]={}; counts[actor]=0 end
            for tick=1,24000 do
                for _,actor in ipairs(residents) do
                    local previous,scene=actor.routineStep,actor.scene
                    Routines.update(data,actor,.05)
                    if actor.routineAction and not firstStarts[actor] then firstStarts[actor]=tick end
                    if previous~=actor.routineStep and actor.scene=='stop' then
                        local action=previous==3 and 'sweep' or previous==5 and 'carry' or previous==6 and 'tend'
                        if action then
                            local history=histories[actor]
                            assert(history[#history]~=action,'resident repeated the same outdoor chore back to back')
                            history[#history+1]=action; counts[actor]=counts[actor]+1
                            if previous==3 then nextAfterSweep[actor.routineStep]=true end
                        end
                    end
                    if scene=='stop' and actor.scene=='house' then
                        if counts[actor]>0 then outingSizes[counts[actor]]=true end
                        counts[actor]=0
                    end
                end
            end
            local signatures={}; local timings={}; local sizeCount=0; local successorCount=0
            for _,actor in ipairs(residents) do
                local history=histories[actor]
                assert(#history>=5,'resident spent the entire visit idle')
                signatures[table.concat(history,',')]=true; timings[firstStarts[actor]]=true
            end
            for _ in pairs(outingSizes) do sizeCount=sizeCount+1 end
            for _ in pairs(nextAfterSweep) do successorCount=successorCount+1 end
            local orderCount=0; for _ in pairs(signatures) do orderCount=orderCount+1 end
            local timeCount=0; for _ in pairs(timings) do timeCount=timeCount+1 end
            assert(orderCount==#residents and timeCount==#residents,'residents kept matching schedules')
            assert(sizeCount>=2 and successorCount>=2,'work still follows the same chore loop')
        ''')

    def test_recruited_resident_has_no_second_body_or_running_routine(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local actor=data.npcStates[data.stopLayouts['4'].residentKeys[1]]
            data.passengers={{npc=actor.file,origin=4,destination=7}}
            local x,y,step=actor.x,actor.y,actor.routineStep
            NPCs.update(data,.1)
            assert(actor.x==x and actor.y==y and actor.routineStep==step)
            assert(not NPCs.find(data,actor.file,'stop'))
            assert(not NPCs.find(data,actor.file,'house',actor.homeDoor))
            Stops.ensure(data,Catalog,'stop',rng); assert(data.currentNPC~=actor.file)
        ''')

    def test_existing_second_door_assignment_is_preserved_during_upgrade(self):
        self.lua.execute('''
            Stops.ensureDoor(data,Catalog,2,rng)
            local layout=data.stopLayouts['4']; local occupant=layout.houseDoors['2'].npc
            data.scene='house'; data.activeHouseDoor=2
            NPCs.prepare(data,Catalog,rng)
            local resident=assert(NPCs.find(data,occupant,'house',2))
            assert(resident.homeDoor==2 and not NPCs.find(data,occupant,'house',1))
            assert(layout.interior==layout.houseDoors['2'].interior and layout.npcInside==occupant)
        ''')

    def test_open_panel_keeps_selection_until_closed_and_layout_reads_do_not_replace_it(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local keys=data.stopLayouts['4'].residentKeys
            local a,b=data.npcStates[keys[1]],data.npcStates[keys[2]]
            a.scene,b.scene='stop','stop'; a.x,a.y=200,450; b.x,b.y=650,450
            local runtime={saveData=data,scene='stop',player={x=200,y=450}}
            NPCs.refresh(runtime); assert(runtime.npcActor==a)
            runtime.tradeOpen=true; runtime.player.x=650
            NPCs.refresh(runtime,NPCs.locked(runtime)); assert(runtime.npcActor==a)
            Stops.ensure(data,Catalog,'stop',rng); assert(data.currentNPC==a.file)
            runtime.tradeOpen=false; NPCs.refresh(runtime); assert(runtime.npcActor==b)
            data.scene='house'; runtime.scene='house'; data.activeHouseDoor=3
            a.scene,b.scene='stop','stop'
            NPCs.refresh(runtime); assert(not runtime.npcActor or runtime.npcActor.homeDoor==3)
        ''')

    def test_save_reload_keeps_occupancy_chore_and_route_continuity(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local key=data.stopLayouts['4'].residentKeys[1]; local actor=data.npcStates[key]
            ready(actor,3,'wait'); actor.routineClock=2.5; actor.routineDuration=7
            actor.routineCooldowns={carry=17.25}; actor.routineOutdoorRemaining=2
            local original=actor
            local originalRandom=actor.routineRandom
            assert(require('game.item_instances').ensure(data))
            love.filesystem=F.filesystem()
            local Save=require('game.save'); assert(Save.write(1,data)); data=assert(Save.read(1))
            NPCs.prepare(data,Catalog,rng); actor=data.npcStates[key]
            assert(actor~=original and actor.routineStep==3 and actor.routineClock==2.5 and actor.scene=='stop')
            assert(actor.routineVersion==Routines.VERSION and actor.routineRandom==originalRandom)
            assert(actor.routineDuration==7 and actor.routineCooldowns.carry==17.25)
            Routines.update(data,actor,.05)
            assert(actor.routineAction=='sweep' and actor.routineClock==2.55 and actor.facing==1)
            for i=1,120 do Routines.update(data,actor,.05) end
            assert(actor.routineStep==6 and actor.routineDelay>16,'saved cooldown and chore choice were lost')
            local expectedStep,expectedRandom,expectedDelay=actor.routineStep,actor.routineRandom,actor.routineDelay
            data=assert(Save.read(1)); NPCs.prepare(data,Catalog,rng); actor=data.npcStates[key]
            for i=1,121 do Routines.update(data,actor,.05) end
            assert(actor.routineStep==expectedStep and actor.routineRandom==expectedRandom
                and math.abs(actor.routineDelay-expectedDelay)<.00001,'reload rerolled the next activity')
        ''')

    def test_navigation_routes_around_obstacles_and_rejects_disconnected_target(self):
        self.lua.execute('''
            Settlements.isWalkable=function(_,x,y)
                return x>=100 and x<=800 and y>=100 and y<=650 and not (x>390 and x<450 and y<500)
            end
            local points=assert(Routines.path(4,300,250,550,250))
            assert(#points>1)
            local x,y=300,250
            for _,point in ipairs(points) do
                local count=math.ceil(math.sqrt((point.x-x)^2+(point.y-y)^2))
                for i=0,count do assert(Settlements.isWalkable(4,x+(point.x-x)*i/count,y+(point.y-y)*i/count)) end
                x,y=point.x,point.y
            end
            Settlements.isWalkable=function(_,x,y) return x>=100 and x<=800 and y>=100 and y<=650 and (x<390 or x>450) end
            -- A new mask identity invalidates cached navigation nodes/edges.
            Settlements.walkMasks={[4]={}}
            assert(not Routines.path(4,300,250,550,250))
        ''')

    def test_blocked_motion_never_advances_distance_animation(self):
        self.lua.execute('''
            NPCs.prepare(data,Catalog,rng)
            local actor=data.npcStates[data.stopLayouts['4'].residentKeys[1]]
            ready(actor,4); actor.animationDistance=12
            Settlements.move=function(_,x,y) return x,y end
            local x,y=actor.x,actor.y
            for i=1,100 do Routines.update(data,actor,.05) end
            assert(actor.x==x and actor.y==y and actor.animationDistance==12 and not actor.moving)
            assert(actor.routineStep~=4,'a blocked route was retried forever')
        ''')

    def test_residents_finish_chores_and_return_home_on_authored_stop_masks(self):
        from PIL import Image
        self.load_interior_files()
        for stop in range(1, 51):
            with self.subTest(stop=stop):
                image = Image.open(ROOT / f'assets/sprites/stops/walkmask-{stop:02d}.png').convert('RGB')
                width, height = image.size
                pixels = image.getchannel('R').point(lambda value: 49 if value > 127 else 48).tobytes()
                self.lua.globals().maskRows = self.lua.table_from([
                    pixels[y * width:(y + 1) * width].decode('ascii') for y in range(height)
                ])
                self.lua.globals().maskWidth = width
                self.lua.globals().maskHeight = height
                self.lua.globals().stopNumber = stop
                self.lua.execute('''
                    local rows,w,h=maskRows,maskWidth,maskHeight
                    Settlements.walkMasks=Settlements.walkMasks or {}
                    Settlements.walkMasks[stopNumber]={getDimensions=function() return w,h end,
                        getPixel=function(_,x,y) return rows[y+1]:byte(x+1)==49 and 1 or 0 end}
                    data=F.campaign(stopNumber,{scene='stop',npcRoster={
                        'trail-fox.png','cook-mouse.png','botanist-frog.png','watch-raccoon.png',
                        'farm-hedgehog.png','harbor-mouse.png','cook-frog.png','conductor-cat.png'}})
                    NPCs.prepare(data,Catalog,rng)
                    for _,key in ipairs(data.stopLayouts[tostring(stopNumber)].residentKeys) do
                        local actor=data.npcStates[key]; local actions={}; local exited,entered=false,false
                        local previous=actor.scene
                        for i=1,30000 do
                            Routines.update(data,actor,.05,{interiorFiles=interiorFiles})
                            if actor.scene~=previous then
                                if actor.scene=='stop' then exited=true else entered=true end
                                previous=actor.scene
                            end
                            if actor.routineAction then actions[actor.routineAction]=true end
                            if actor.scene=='stop' then
                                assert(Settlements.isWalkable(stopNumber,actor.x,actor.y),'left mask '..key)
                            end
                            if actions.sweep and actions.carry and actions.tend and entered and exited then break end
                        end
                        assert(actions.sweep and actions.carry and actions.tend and entered and exited,
                            'incomplete route '..key..' step '..tostring(actor.routineStep)..' at '..actor.x..','..actor.y)
                    end
                ''')


if __name__ == '__main__':
    unittest.main()
