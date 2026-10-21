"""Host scene transactions include both actors, generation and travel receipts."""
from pathlib import Path
import os
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, os.environ.get("LUA_RUNTIME_PYTHONPATH", str(ROOT / ".stabilization/python-deps")))
from lupa.lua51 import LuaRuntime


class CoopSceneTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            love={math={random=math.random}}
            F=require('tools.tests.lua.coop_fixtures'); Schema=require('game.save_schema')
            Catalog=require('game.catalog'); Authority=require('game.coop_authority')
            Scenes=require('game.coop_scenes'); Party=require('game.party_scene')
            Players=require('game.coop_players'); Settlements=require('game.settlements')
            Caravans=require('game.crow_caravans'); Caravan=require('game.crow_caravan_area')
            Areas=require('game.expedition_areas')
            data=F.campaign(2,{scene='train',npcRoster={'farm-hedgehog.png','harbor-mouse.png'}})
            assert(F.enroll(data)); data.events['2']={id='resolved'}
            data.players.companion.playerX,data.players.companion.playerY=240,250
            fs,files=F.filesystem(); love.filesystem=fs; Save=require('game.save')
            canSave=true; travelTime=0; writes=0
            context={catalog=Catalog,isFurniture=function(name) return Catalog.storageCapacities[name]~=nil end,
                trainSpawn=function() return 430,430 end,
                trainClamp=function(d,id,x,y) return math.max(150,math.min(800,x)),math.max(400,math.min(450,y)) end,
                actorState=function(id)
                    local actor=Players.get(data,id)
                    if actor then return {screen='game',scene=Players.forActor(data,id).scene,x=actor.playerX,y=actor.playerY,travelTime=travelTime} end
                end}
            function create()
                service=Authority.new({campaign=data,sessionId='scene-test',randomSeed=321,
                    checkpoint=function(value) writes=writes+1; return canSave and Save.write(1,value) end})
                service:admit('companion',1); Scenes.install(service,context)
            end
            create()
            function run(name,args)
                local reply=service:submitLocal(name,args or {})
                assert(reply.ok,name..': '..tostring(reply.reason)); return reply
            end
            function approachDoor(index)
                data.playerX,data.playerY=Settlements.doorPoint(data.location,index)
            end
            function distinct()
                local a,b=data.players.host,data.players.companion
                return (a.playerX-b.playerX)^2+(a.playerY-b.playerY)^2>=24^2
            end
            function caravanStop()
                data.location=9; data.scene='stop'
                data.crowCaravans={scheduledStops={9,24,40},scheduleVersion=1,scheduleMode='journey',camps={}}
                local gate=assert(Caravan.stopEntrance(9)); data.playerX,data.playerY=gate.x,gate.y
                data.players.companion.playerX,data.players.companion.playerY=180,500
                return gate
            end
            function expeditionStop(stop)
                data.location=stop or 6; data.scene='stop'; data.activeExpeditionArea=nil
                local gate=assert(Areas.entrance(data.location)); data.playerX,data.playerY=gate.x,gate.y
                data.players.companion.playerX,data.players.companion.playerY=180,500
                return gate
            end
            function enterExpedition(stop)
                local gate=expeditionStop(stop)
                return run('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn})
            end
            function approachExpedition(id)
                for _,gate in ipairs(Areas.current(data).interactions) do
                    if gate.id==id then data.playerX,data.playerY=gate.x,gate.y; return gate end
                end
                error('missing gate '..id)
            end
        ''')

    def test_guest_cannot_progress_any_major_scene_or_travel_stage(self):
        self.lua.execute('''
            local before=assert(Schema.copy(data)); local id=0
            for _,name in ipairs({'travel.depart','travel.arrive','travel.finish'}) do
                id=id+1
                local reply=service:execute('companion',1,{sessionId=service.sessionId,requestId=id,
                    sceneEpoch=data.coop.sceneEpoch,command=name,args={},expected={}})
                assert(not reply.ok and reply.reason=='host_only')
            end
            assert(data.scene==before.scene and data.location==before.location and data.resources.coal==before.resources.coal)
            assert(data.coop.revision==before.coop.revision and writes==1)
        ''')

    def test_train_house_and_return_preserve_other_traveler_and_create_loot_once(self):
        self.lua.execute('''
            local epoch=data.coop.sceneEpoch
            local reply=run('scene.leaveTrain'); assert(reply.durable and data.scene=='stop' and distinct())
            assert(data.coop.sceneEpoch==epoch and Settlements.isWalkable(data.location,data.playerX,data.playerY))
            assert(Players.forActor(data,'companion').scene=='train' and data.players.companion.playerX==240)
            approachDoor(1); reply=run('scene.enterHouse',{door=1})
            assert(reply.durable and data.scene=='house' and distinct() and data.lootRolls['2:1'])
            local count=#data.droppedItems; local randomState=data.coop.randomState
            run('scene.exitHouse'); approachDoor(1); run('scene.enterHouse',{door=1})
            assert(#data.droppedItems==count and data.coop.randomState==randomState)
            run('scene.returnTrain'); assert(data.scene=='train' and distinct() and not data.activeHouseDoor)
            local saved=assert(Save.read(1)); assert(saved.players.companion.playerX==data.players.companion.playerX)
        ''')

    def test_unopened_stop_invalid_door_and_forged_coordinates_are_rejected(self):
        self.lua.execute('''
            data.events['2']=nil
            assert(service:submitLocal('scene.leaveTrain',{}).reason=='stop_not_open')
            data.events['2']={id='resolved'}; run('scene.leaveTrain')
            assert(service:submitLocal('scene.enterHouse',{door=99}).reason=='door_unavailable')
            approachDoor(1)
            assert(service:submitLocal('scene.enterHouse',{door=1,x=300,y=400}).reason=='invalid_arguments')
            assert(data.scene=='stop' and not data.houseInitialized['2:1'])
        ''')

    def test_world_generation_uses_transaction_rng_and_rolls_back_with_invalid_spawn(self):
        self.lua.execute('''
            love.math.random=function() error('global RNG touched') end
            run('scene.leaveTrain'); approachDoor(1)
            local before=data.coop.randomState; local count=#data.droppedItems
            local place=Party.place; Party.place=function() return nil,'injected_spawn_failure' end
            local reply=service:submitLocal('scene.enterHouse',{door=1})
            Party.place=place
            assert(not reply.ok and reply.reason=='injected_spawn_failure')
            assert(data.coop.randomState==before and #data.droppedItems==count and data.scene=='stop')
            run('scene.enterHouse',{door=1}); assert(data.coop.randomState~=before)
        ''')

    def test_local_transition_keeps_other_actors_lease_and_rejects_old_departure(self):
        self.lua.execute('''
            local Leases=require('game.coop_leases')
            local now=service.clock()
            assert(Leases.acquire(service.activityState,'station','companion',1,data.coop.sceneEpoch,now,{}))
            local old=assert(service:prepareRequest('host','travel.depart',{}))
            run('scene.leaveTrain'); assert(service.activityState.resources.station.actorId=='companion')
            old.requestId=old.requestId+1
            assert(service:execute('host',0,old).reason=='travel_unavailable' and not data.coop.journey)
        ''')

    def test_paid_departure_is_replay_safe_and_reload_resumes_without_payment(self):
        self.lua.execute('''
            local req=assert(service:prepareRequest('host','travel.depart',{}))
            local coal=data.resources.coal; local reply=service:execute('host',0,req)
            assert(reply.ok and reply.durable and data.coop.journey.phase=='departed')
            local paid=data.resources.coal; assert(paid<coal and data.location==2)
            assert(service:execute('host',0,req).durable and data.resources.coal==paid)
            data=assert(Save.read(1)); create()
            local runtime={saveData=data}; require('game.coop_scene_runtime').restoreJourney(runtime)
            assert(runtime.travelTransition and not runtime.travelTransition.changed and runtime.travelTransition.t==0)
            assert(service:execute('host',0,req).reason=='wrong_session' and data.resources.coal==paid)
            assert(service:submitLocal('travel.depart',{}).reason=='travel_unavailable')
        ''')

    def test_arrival_requires_host_clock_and_rewards_once_across_reload(self):
        self.lua.execute('''
            data.passengers={{npc='cook-mouse.png',origin=1,destination=3,job='cook',x=200,y=430}}
            assert(require('game.coop_entities').ensure(data))
            run('travel.depart')
            assert(service:submitLocal('travel.arrive',{}).reason=='not_arrived')
            travelTime=100; run('travel.arrive')
            assert(data.location==3 and data.coop.journey.phase=='arrived' and #data.passengers==0)
            assert(data.goodwill==1 and data.arrivalNotice)
            local coal,scrap=data.resources.coal,data.scrap
            data=assert(Save.read(1)); create()
            local runtime={saveData=data}; require('game.coop_scene_runtime').restoreJourney(runtime)
            assert(runtime.travelTransition.changed and runtime.travelTransition.t>0)
            assert(service:submitLocal('travel.arrive',{}).reason=='journey_unavailable')
            run('travel.finish'); assert(not data.coop.journey and data.location==3 and data.resources.coal==coal and data.scrap==scrap)
        ''')

    def test_failed_departure_checkpoint_waits_and_retry_never_pays_twice(self):
        self.lua.execute('''
            canSave=false
            local reply=run('travel.depart'); local paid=data.resources.coal
            assert(reply.savePending and not reply.durable and Save.read(1).coop.journey==nil)
            travelTime=100
            assert(service:submitLocal('travel.arrive',{}).reason=='save_pending')
            canSave=true; assert(service:retryCheckpoint() and data.resources.coal==paid)
            run('travel.arrive'); run('travel.finish'); assert(data.location==3)
        ''')

    def test_invalid_journey_metadata_cannot_migrate_or_load(self):
        self.lua.execute('''
            run('travel.depart')
            for _,mutate in ipairs({
                function(d) d.coop.journey.to=50 end,
                function(d) d.coop.journey.phase='finished' end,
                function(d) d.location=4 end,
                function(d) d.coop.journey.maintenanceCondition=math.huge end,
                function(d) d.coop.journey.cost=0 end,
                function(d) d.scene='house' end,
            }) do local copy=assert(Schema.copy(data)); mutate(copy); assert(not Schema.validate(copy) and not Schema.migrate(copy)) end
        ''')

    def test_presentation_accepts_committed_epoch_without_increment_or_old_position_sync(self):
        self.lua.execute('''
            local Session=require('game.game_session'); local session=Session.new()
            session:setSaveData(data); session:setScreen('game'); session:setPlayer({x=300,y=450})
            local reply=run('scene.leaveTrain'); local epoch=data.coop.sceneEpoch
            session:acceptPartyState(reply.result)
            session:sync('game',1,data,session.player,session.scene)
            assert(data.coop.sceneEpoch==epoch and session.player.x==data.players.host.playerX and session.scene=='stop')
        ''')

    def test_final_stop_only_opens_ending_after_arrival_and_finish(self):
        self.lua.execute('''
            data.location=49; data.resources={food=100,water=100,coal=100,oil=100}
            run('travel.depart'); assert(data.location==49)
            travelTime=100; run('travel.arrive'); assert(data.location==50 and data.coop.journey)
            data=assert(Save.read(1)); create()
            local session=require('game.game_session').new()
            assert(session:activate(data,{})=='game','unfinished final arrival must resume before ending')
            local reply=run('travel.finish'); assert(reply.result.screen=='ending' and not data.coop.journey)
            assert(session:activate(data,{})=='ending')
            assert(service:submitLocal('travel.depart',{}).reason=='travel_unavailable')
        ''')

    def test_caravan_entry_and_return_checkpoint_own_visit_and_preserve_stock(self):
        self.lua.execute('''
            local gate=caravanStop(); local epoch=data.coop.sceneEpoch
            love.math.random=function() error('global RNG touched') end
            local reply=run('scene.caravan',{action='enter',stop=9})
            assert(reply.durable and reply.result.firstCaravanVisit and data.scene=='caravan' and distinct())
            assert(data.coop.sceneEpoch==epoch and data.crowCaravans.meetings==1)
            assert(Caravan.isWalkable(data.playerX,data.playerY))
            assert(Players.forActor(data,'companion').scene=='stop' and data.players.companion.playerX==180)
            local camp=assert(Caravans.lookup(data,9)); local merchant=camp.merchants[1]
            merchant.listings[1].quantity=0
            local random=data.coop.randomState; local item=merchant.listings[1].item
            local session=assert(Caravan.restore(data))
            for _,point in ipairs(Caravan.interactions(session)) do
                if point.action=='returnStop' then data.playerX,data.playerY=point.x,point.y end
            end
            reply=run('scene.caravan',{action='return'})
            assert(reply.durable and data.scene=='stop' and distinct() and not data.crowCaravans.activeCampId)
            local returnX,returnY=Settlements.clamp(gate.x,gate.y,9)
            assert(data.playerX==returnX and data.playerY==returnY)
            random=data.coop.randomState
            data.playerX,data.playerY=gate.x,gate.y
            reply=run('scene.caravan',{action='enter',stop=9})
            assert(not reply.result.firstCaravanVisit and data.crowCaravans.meetings==1 and data.coop.randomState==random)
            assert(Caravans.lookup(data,9).merchants[1].listings[1].item==item)
            assert(Caravans.lookup(data,9).merchants[1].listings[1].quantity==0)
            local saved=assert(Save.read(1)); assert(saved.scene=='caravan' and saved.players.companion.playerX==data.players.companion.playerX)
        ''')

    def test_caravan_rejects_wrong_gate_unscheduled_departed_and_forged_args_without_mutation(self):
        self.lua.execute('''
            local gate=caravanStop(); local random=data.coop.randomState; local revision=data.coop.revision
            data.playerX=180
            assert(service:submitLocal('scene.caravan',{action='enter',stop=9}).reason=='gate_unavailable')
            data.playerX=gate.x
            assert(service:submitLocal('scene.caravan',{action='enter',stop=10}).reason=='wrong_scene')
            assert(service:submitLocal('scene.caravan',{action='enter',stop=9,x=480}).reason=='invalid_arguments')
            data.location=10; gate=Caravan.stopEntrance(10); data.playerX,data.playerY=gate.x,gate.y
            assert(not service:submitLocal('scene.caravan',{action='enter',stop=10}).ok)
            assert(next(data.crowCaravans.camps)==nil and data.coop.randomState==random and data.coop.revision==revision)
            data.location=9; gate=Caravan.stopEntrance(9); data.playerX,data.playerY=gate.x,gate.y
            run('scene.caravan',{action='enter',stop=9}); run('scene.returnTrain')
            data.scene='stop'; data.playerX,data.playerY=gate.x,gate.y
            assert(Caravans.markDeparted(data,9)); local meetings=data.crowCaravans.meetings
            assert(service:submitLocal('scene.caravan',{action='enter',stop=9}).reason=='camp_unavailable')
            assert(data.scene=='stop' and data.crowCaravans.meetings==meetings)
        ''')

    def test_caravan_rolls_back_generation_and_rng_when_party_spawn_fails(self):
        self.lua.execute('''
            caravanStop(); local random=data.coop.randomState; local epoch=data.coop.sceneEpoch
            local place=Party.place; Party.place=function() return nil,'injected_spawn_failure' end
            local reply=service:submitLocal('scene.caravan',{action='enter',stop=9}); Party.place=place
            assert(not reply.ok and reply.reason=='injected_spawn_failure')
            assert(data.scene=='stop' and data.coop.sceneEpoch==epoch and data.coop.randomState==random)
            assert(next(data.crowCaravans.camps)==nil and not data.crowCaravans.activeCampId)
            run('scene.caravan',{action='enter',stop=9})
        ''')

    def test_host_can_use_caravan_return_hud_from_a_trading_stall(self):
        self.lua.execute('''
            caravanStop(); run('scene.caravan',{action='enter',stop=9})
            local session=assert(Caravan.restore(data)); local merchant=Caravan.merchant(session,'packmaster')
            data.playerX,data.playerY=merchant.x,merchant.y
            assert(Caravan.interaction(session,{x=data.playerX,y=data.playerY}).action=='trade')
            local reply=run('scene.caravan',{action='return'})
            assert(reply.durable and data.scene=='stop' and distinct())
        ''')

    def test_caravan_failed_save_retry_and_exact_replay_keep_one_scene_and_stock_roll(self):
        self.lua.execute('''
            caravanStop(); assert(Save.write(1,data)); local epoch=data.coop.sceneEpoch
            local request=assert(service:prepareRequest('host','scene.caravan',{action='enter',stop=9}))
            canSave=false; local reply=service:execute('host',0,request)
            assert(reply.ok and reply.savePending and not reply.durable and Save.read(1).scene=='stop')
            local random=data.coop.randomState; local x=data.players.companion.playerX
            assert(service:submitLocal('scene.returnTrain',{}).reason=='save_pending')
            canSave=true; assert(service:retryCheckpoint()); reply=service:execute('host',0,request)
            assert(reply.durable and data.coop.sceneEpoch==epoch and data.coop.randomState==random)
            assert(data.crowCaravans.meetings==1 and data.players.companion.playerX==x)
            data=assert(Save.read(1)); create(); assert(data.scene=='caravan' and Caravan.restore(data))
        ''')

    def test_expedition_stop_dungeon_and_return_move_only_own_actor_to_authored_spawns(self):
        self.lua.execute('''
            local reply=enterExpedition(6)
            assert(reply.durable and reply.result.expeditionTutorial and distinct() and data.activeExpeditionArea==Areas.SURFACE_ID)
            local state=Areas.state(data,Areas.SURFACE_ID); assert(state.discovered and state.tutorialSeen)
            local gate=approachExpedition('dungeon-entrance')
            reply=run('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn})
            assert(reply.durable and not reply.result.expeditionTutorial and data.activeExpeditionArea==Areas.DUNGEON_ID and distinct())
            assert(Areas.isWalkable(data,Areas.DUNGEON_ID,data.playerX,data.playerY))
            assert(Players.forActor(data,'companion').scene=='stop' and data.players.companion.playerX==180)
            gate=approachExpedition('return-surface')
            reply=run('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn})
            assert(not reply.result.expeditionTutorial and data.activeExpeditionArea==Areas.SURFACE_ID and distinct())
            approachExpedition('return-town'); run('scene.expedition',{action='returnStop'})
            assert(data.scene=='stop' and not data.activeExpeditionArea and distinct())
            local saved=assert(Save.read(1)); assert(saved.players.companion.playerY==data.players.companion.playerY)
        ''')

    def test_badlands_entry_resets_environment_once_and_surface_tutorial_never_repeats(self):
        self.lua.execute('''
            enterExpedition(5); local gate=approachExpedition('basin-entrance')
            local request=assert(service:prepareRequest('host','scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn}))
            local reply=service:execute('host',0,request); assert(reply.ok and reply.durable and distinct())
            local basin=Areas.state(data,Areas.BADLANDS_BASIN_ID); assert(basin.environmentClock==0)
            basin.environmentClock=12
            assert(service:execute('host',0,request).durable and basin.environmentClock==12)
            gate=approachExpedition('return-approach')
            reply=run('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn})
            assert(not reply.result.expeditionTutorial)
        ''')

    def test_expedition_rejects_remote_gate_forged_area_spawn_and_unknown_args(self):
        self.lua.execute('''
            local gate=expeditionStop(6); local epoch=data.coop.sceneEpoch; local random=data.coop.randomState
            data.playerX=180
            assert(service:submitLocal('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn}).reason=='gate_unavailable')
            data.playerX=gate.x
            for _,args in ipairs({
                {action='enterArea',areaId=Areas.DUNGEON_ID,spawn='surface'},
                {action='enterArea',areaId=gate.target,spawn='dungeonReturn'},
                {action='enterArea',areaId=gate.target,spawn=gate.spawn,x=100},
                {action='returnStop'},
            }) do assert(not service:submitLocal('scene.expedition',args).ok) end
            assert(data.scene=='stop' and not data.activeExpeditionArea and data.coop.sceneEpoch==epoch and data.coop.randomState==random)
            assert(not data.expeditions or not data.expeditions[Areas.SURFACE_ID] or not data.expeditions[Areas.SURFACE_ID].discovered)
            enterExpedition(6); approachExpedition('return-town')
            assert(service:submitLocal('scene.expedition',{action='returnStop',areaId=gate.target}).reason=='invalid_arguments')
        ''')

    def test_expedition_spawn_failure_rolls_back_discovery_tutorial_and_environment(self):
        self.lua.execute('''
            local gate=expeditionStop(5); local epoch=data.coop.sceneEpoch
            local place=Party.place; Party.place=function() return nil,'injected_spawn_failure' end
            local reply=service:submitLocal('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn}); Party.place=place
            assert(not reply.ok and reply.reason=='injected_spawn_failure' and data.coop.sceneEpoch==epoch)
            assert(data.scene=='stop' and not data.activeExpeditionArea)
            assert(not data.expeditions or not data.expeditions[gate.target] or not data.expeditions[gate.target].discovered)
            reply=run('scene.expedition',{action='enterArea',areaId=gate.target,spawn=gate.spawn}); assert(reply.result.expeditionTutorial)
        ''')

    def test_medical_car_heals_admitted_characters_and_greenhouse_produces_once(self):
        self.lua.execute('''
            data.trainCars={'living-car','medical','greenhouse'}; data.health=2
            data.players.companion.health=data.players.companion.maxHealth-1; data.passengers={}
            run('travel.depart'); local food=data.resources.food; travelTime=100
            local request=assert(service:prepareRequest('host','travel.arrive',{})); canSave=false
            local reply=service:execute('host',0,request); assert(reply.ok and reply.savePending)
            assert(data.health==5 and data.players.companion.health==data.players.companion.maxHealth and data.resources.food==food+2)
            canSave=true; assert(service:retryCheckpoint()); assert(service:execute('host',0,request).durable)
            assert(data.health==5 and data.resources.food==food+2)
            local saved=assert(Save.read(1)); assert(saved.health==5 and saved.players.companion.health==saved.players.companion.maxHealth)
        ''')

    def test_medical_car_leaves_disconnected_companion_and_offline_api_unchanged(self):
        self.lua.execute('''
            data.trainCars={'living-car','medical'}; data.health=2; data.players.companion.health=4
            service:disconnect('companion',1); run('travel.depart'); travelTime=100; run('travel.arrive')
            assert(data.health==5 and data.players.companion.health==4)
            local Train=require('game.train_upgrade_balance')
            local legacy={trainCars={'medical'},health=1,maxHealth=20,resources={}}
            assert(Train.applyArrival(legacy).health==3 and legacy.health==4)
            local before=data.health
            local result=Train.applyArrival(data,{'host','host'})
            assert(data.health==before+3 and result.actorHealth.host==3)
        ''')

    def test_invalid_host_runtime_positions_cannot_enter_routes(self):
        self.lua.execute('''
            local actorState=context.actorState
            for _,setup in ipairs({caravanStop,expeditionStop}) do
                setup()
                for _,position in ipairs({{}, {x=0/0,y=400}, {x=math.huge,y=400}, {x=400,y=-math.huge}}) do
                    context.actorState=function(id) local state=actorState(id); state.x=position.x; state.y=position.y; return state end
                    local name=data.location==9 and 'scene.caravan' or 'scene.expedition'
                    local gate=Areas.entrance(data.location)
                    local args=name=='scene.caravan' and {action='enter',stop=9} or {action='enterArea',areaId=gate.target,spawn=gate.spawn}
                    assert(service:submitLocal(name,args).reason=='gate_unavailable')
                end
            end
            context.actorState=actorState
        ''')


if __name__ == '__main__':
    unittest.main()
