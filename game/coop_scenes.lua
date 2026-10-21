local Party=require("game.party_scene")
local Players=require("game.coop_players")
local Random=require("game.coop_random")
local Stops=require("game.stops")
local House=require("game.house")
local NPCs=require("game.scene_npcs")
local Settlements=require("game.settlements")
local Doors=require("game.interior_doors")
local Util=require("game.util")
local Progression=require("game.progression_balance")
local Engines=require("game.engine_upgrades")
local Maintenance=require("game.maintenance")
local Train=require("game.train_upgrade_balance")
local Arrivals=require("game.journey_arrivals")
local Items=require("game.item_instances")
local Routes=require('game.journey_scene_routes')
local Caravans=require('game.crow_caravans')
local Caravan=require('game.crow_caravan_area')
local Areas=require('game.expedition_areas')
local Home=require('game.home_stop')
local Presence=require('game.coop_presence')
local Commands={}
function Commands.localScopes(id) return {'presence:'..id,'player:'..id,'rng','people:identities','world:rooms'} end
local function positionAvailable(state)
    return type(state.x)=='number' and state.x==state.x and math.abs(state.x)<100000
        and type(state.y)=='number' and state.y==state.y and math.abs(state.y)<100000
end
local function fields(args,allowed)
    for key in pairs(args) do if not allowed[key] then return false end end
    return true
end
local function trainPositions(data,context,returning)
    return Party.place(data,function(id,actor)
        local own=Players.forActor(Players.campaignOf(data),id)
        if not returning and own.scene=='train' and type(actor.playerX)=="number" and type(actor.playerY)=="number" then return actor.playerX,actor.playerY end
        return context.trainSpawn(data,id)
    end,function(x,y,id) return context.trainClamp(data,id,x,y) end)
end
function Commands.install(authority,context)
    local catalog=context.catalog
    local function register(name,prepare)
        authority:register(name,function(data,actorId,args,transaction)
            local localScene=name:match('^scene%.') and name~='scene.rangeEnter' and name~='scene.rangeExit'
                or name=='home.advance' and (args.action=='enterOffice' or args.action=='exitOffice')
            if data.roamingEncounter and name=='scene.returnTrain' then
                if actorId~='host' then return nil,'host_only' end
                localScene=false
            end
            if localScene then
                local campaign=Players.campaignOf(data); Presence.ensure(campaign)
                data=Players.forActor(campaign,actorId)
            end
            local state=context.actorState(actorId)
            if not state or state.screen~="game" or state.scene~=data.scene or state.changingCar or state.activityBlocked
                or state.encounterActive then return nil,"scene_unavailable" end
            if data.roamingEncounter and name~='scene.returnTrain' then return nil,'encounter_pending' end
            if Home.isHome(data) and (name=='scene.enterHouse' or name=='scene.caravan' or name=='scene.expedition') then return nil,'home_preparation_incomplete' end
            if data.coop.sceneEpoch>=Party.MAX then return nil,"scene_epoch_exhausted" end
            local apply,reason=prepare(data,state,args,transaction)
            if not apply then return nil,reason end
            local scopes={"party","resources","rng","world:scene","relationships","player:host","people:identities"}
            if name=='home.advance' then scopes[#scopes+1]='story:homeStop'; scopes[#scopes+1]='world:maintenance' end
            if name=='travel.depart' and Home.isHome(data) then scopes[#scopes+1]='story:homeStop' end
            if data.roamingEncounter then scopes[#scopes+1]='combat:roaming' end
            if data.players.companion then scopes[#scopes+1]="player:companion" end
            local homeRoom=name=='home.advance' and (args.action=='enterOffice' or args.action=='exitOffice')
            if localScene then scopes=Commands.localScopes(actorId) end
            return {scopes=scopes,effects=localScene and {localScene=true} or name=='home.advance' and not homeRoom and {story=true} or {scene=true},apply=function()
                local result,message=apply()
                if not result then return nil,message end
                if Items.enabled(data) and not Items.ensure(data) then return nil,"invalid_items" end
                return result
            end}
        end)
    end
    local function advanceHome(data,state,args,transaction)
        if not fields(args,{action=true}) or type(args.action)~='string' then return nil,'invalid_arguments' end
        if state.traveling or state.activityBlocked or data.coop.journey then return nil,'home_step_unavailable' end
        local allowed,reason=Home.canAdvance(data,args.action,state)
        if not allowed then return nil,reason end
        return function()
            local result,message=Home.advance(data,args.action)
            if not result then return nil,message end
            if result.homeOfficeTransition then
                local x,y
                if Home.isOffice(data) then x,y=Home.officeSpawn.x,Home.officeSpawn.y else x,y=Home.points.officeDoor.x,Home.points.officeDoor.y+28 end
                local actors,reason=Party.place(data,function() return x,y end,function(px,py) return Home.clamp(px,py,data) end)
                if not actors then return nil,reason end
                NPCs.prepare(data,catalog)
                local party=Party.commit(data,transaction,actors)
                party.homeOfficeTransition=true
                return party
            end
            return result
        end
    end
    register('home.advance',advanceHome)
    register('scene.office',function(data,state,args,transaction)
        if args.action~='enterOffice' and args.action~='exitOffice' then return nil,'invalid_arguments' end
        return advanceHome(data,state,args,transaction)
    end)
    for _,command in ipairs({"scene.leaveTrain","scene.returnTrain","scene.enterHouse","scene.exitHouse"}) do
        local name=command
        register(name,function(data,state,args,transaction)
            if not fields(args,name=="scene.enterHouse" and {door=true} or {}) then return nil,"invalid_arguments" end
            if data.coop.journey or state.traveling then return nil,"travel_in_progress" end
            if name=="scene.leaveTrain" then
                if data.scene~="train" then return nil,"wrong_scene" end
                local encounter=data.encounters[tostring(data.location)]
                if not Home.isHome(data) then
                    if encounter and encounter.hasMob and not encounter.resolved then return nil,"stop_not_open" end
                    if not data.events[tostring(data.location)] and not (encounter and encounter.hasMob and encounter.resolved) then return nil,"stop_not_open" end
                end
            elseif name=="scene.enterHouse" then
                if data.scene~="stop" or type(args.door)~="number" or args.door~=math.floor(args.door)
                    or Settlements.nearDoor(state.x,state.y,data.location)~=args.door then return nil,"door_unavailable" end
            elseif name=="scene.exitHouse" and data.scene~="house" then return nil,"wrong_scene"
            elseif name=="scene.returnTrain" and data.scene=="train" and not data.roamingEncounter then return nil,"wrong_scene" end
            if name=='scene.returnTrain' and Home.isHome(data) then
                if data.homeStop.stage~='ready' then return nil,'home_preparation_incomplete' end
                local target=Home.interaction(data,state)
                if not target or target.action~='board' then return nil,'home_target_unavailable' end
            end
            return function()
                local rng=Random.generator(data,transaction.randomSeed)
                local actors,message
                if name=="scene.returnTrain" then
                    data.roamingEncounter=nil
                    data.scene="train"; data.activeHouseDoor=nil; data.activeExpeditionArea=nil
                    if data.crowCaravans then data.crowCaravans.activeCampId=nil end
                    actors,message=trainPositions(data,context,true)
                elseif name=="scene.enterHouse" then
                    data.lastStopDoor=args.door; data.activeHouseDoor=args.door; data.scene="house"
                    local layout=Stops.ensureDoor(data,catalog,args.door,rng)
                    House.ensure(data,catalog,context.isFurniture,rng)
                    local files=type(context.interiorFiles)=="function" and context.interiorFiles() or context.interiorFiles
                    actors,message=Party.place(data,function() return Doors.spawnPoint(layout.interior,files) end,Util.clampHouseFloor)
                    NPCs.prepare(data,catalog,rng)
                else
                    local returning=name=="scene.exitHouse"
                    data.scene="stop"; data.activeHouseDoor=nil
                    local x,y
                    if Home.isHome(data) then x,y=Home.points.train.x,Home.points.train.y
                    elseif returning then x,y=Settlements.doorPoint(data.location,data.lastStopDoor)
                    else x,y=Settlements.trainPoint(data.location) end
                    actors,message=Party.place(data,function() return x,y end,function(px,py)
                        if Home.isHome(data) then return Home.clamp(px,py,data) end
                        return Settlements.clamp(px,py,data.location)
                    end)
                    NPCs.prepare(data,catalog,rng)
                end
                if not actors then return nil,message end
                return Party.commit(data,transaction,actors)
            end
        end)
    end
    register('scene.caravan',function(data,state,args,transaction)
        if not fields(args,{action=true,stop=true}) or (args.action~='enter' and args.action~='return') then return nil,'invalid_arguments' end
        if data.coop.journey or state.traveling then return nil,'travel_in_progress' end
        if not positionAvailable(state) then return nil,'gate_unavailable' end
        local session,gate
        if args.action=='enter' then
            if data.scene~='stop' or args.stop~=data.location then return nil,'wrong_scene' end
            gate=Caravan.stopEntrance(data.location)
            if not gate or (state.x-gate.x)^2+(state.y-gate.y)^2>gate.radius^2 then return nil,'gate_unavailable' end
        else
            if args.stop~=nil then return nil,'invalid_arguments' end
            if data.scene~=Caravan.SCENE then return nil,'wrong_scene' end
            session=Caravan.restore(data)
            -- The host's persistent Return to Stop HUD control is available
            -- throughout the camp, including while trading.
            if not session then return nil,'return_unavailable' end
        end
        return function()
            local actors,message
            local firstVisit=false
            local rng=Random.generator(data,transaction.randomSeed)
            if args.action=='enter' then
                local camp,reason=Caravans.ensureCamp(data,catalog,data.location,Routes.caravanSchedule(data,rng))
                if not camp or not Caravans.isActive(camp) then return nil,reason or 'camp_unavailable' end
                firstVisit=camp.visited~=true
                local entered,x,y=Caravan.enter(data,data.location,{x=state.x,y=state.y,facing=data.playerFacing},{camp=camp})
                if not entered then return nil,x or 'camp_unavailable' end
                data.scene=Caravan.SCENE; data.activeHouseDoor=nil; data.activeExpeditionArea=nil
                if firstVisit then data.crowCaravans.meetings=(data.crowCaravans.meetings or 0)+1 end
                actors,message=Party.place(data,function() return x,y end,Caravan.clamp)
            else
                local x,y,facing=Caravan.leave(data,session)
                if type(x)~='number' or type(y)~='number' then return nil,'return_unavailable' end
                data.scene='stop'; data.activeHouseDoor=nil
                if facing~=nil then data.playerFacing=facing end
                actors,message=Party.place(data,function() return x,y end,function(px,py) return Settlements.clamp(px,py,data.location) end)
                NPCs.prepare(data,catalog,rng)
            end
            if not actors then return nil,message end
            local result=Party.commit(data,transaction,actors)
            result.caravanEntry=args.action=='enter'; result.firstCaravanVisit=firstVisit
            return result
        end
    end)
    register('scene.expedition',function(data,state,args,transaction)
        if not fields(args,{action=true,areaId=true,spawn=true})
            or (args.action~='enterArea' and args.action~='returnStop') then return nil,'invalid_arguments' end
        if data.coop.journey or state.traveling then return nil,'travel_in_progress' end
        if not positionAvailable(state) then return nil,'gate_unavailable' end
        local selected=Areas.interaction(data,data.scene,{x=state.x,y=state.y})
        if not selected or selected.action~=args.action then return nil,'gate_unavailable' end
        local area,x,y
        if args.action=='enterArea' then
            if args.areaId~=selected.targetArea or args.spawn~=selected.spawn then return nil,'destination_unavailable' end
            area=Areas.definition(selected.targetArea)
            if not area or area.stop~=data.location then return nil,'destination_unavailable' end
            local source=Areas.current(data)
            local definition
            for _,candidate in ipairs(source and source.interactions or {}) do if candidate.id==selected.id then definition=candidate end end
            if definition and definition.requires and not Areas.updateGates(data,source.id)[definition.requires] then return nil,'gate_locked' end
            x,y=Areas.spawn(area.id,selected.spawn)
            if type(x)~='number' or type(y)~='number' then return nil,'spawn_unavailable' end
        elseif args.areaId~=nil or args.spawn~=nil then return nil,'invalid_arguments' end
        return function()
            local actors,message
            local tutorial=false
            if args.action=='enterArea' then
                Areas.ensure(data); data.activeExpeditionArea=area.id; data.activeHouseDoor=nil; data.scene=Areas.SCENE
                local saved=Areas.state(data,area.id); saved.discovered=true
                tutorial=area.kind=='surface' and not saved.tutorialSeen
                if tutorial then saved.tutorialSeen=true end
                local occupied=false
                for id in pairs(data.players) do
                    if id~=Players.actorId(data) then
                        local other=Players.forActor(data,id)
                        if other.scene=='expedition' and other.activeExpeditionArea==area.id then occupied=true end
                    end
                end
                if not occupied then Areas.resetEnvironment(data,area.id) end
                actors,message=Party.place(data,function() return x,y end,function(px,py) return Areas.clamp(data,area.id,px,py) end)
            else
                data.scene='stop'; data.activeExpeditionArea=nil; data.activeHouseDoor=nil
                actors,message=Party.place(data,function() return 875,420 end,function(px,py) return Settlements.clamp(px,py,data.location) end)
                NPCs.prepare(data,catalog,Random.generator(data,transaction.randomSeed))
            end
            if not actors then return nil,message end
            local result=Party.commit(data,transaction,actors)
            result.expeditionEntry=args.action=='enterArea'; result.expeditionTutorial=tutorial
            return result
        end
    end)
    register("travel.depart",function(data,state,args,transaction)
        if not fields(args,{}) then return nil,"invalid_arguments" end
        if data.scene~="train" or data.location>=50 or data.coop.journey or state.traveling then return nil,"travel_unavailable" end
        if not Home.canDepart(data) then return nil,'home_preparation_incomplete' end
        local cost=Progression.travelCost(data,Engines,Maintenance,catalog.characterTraitProfiles[1],Train)
        if not Progression.travelStatus(data,cost).affordable then return nil,"insufficient_supplies" end
        return function()
            local departed,reason=Home.depart(data); if not departed then return nil,reason end
            for _,resource in ipairs({"food","water","coal"}) do data.resources[resource]=data.resources[resource]-cost[resource] end
            data.arrivalNotice=nil
            data.coop.journey={from=data.location,to=data.location+1,phase="departed",epoch=data.coop.sceneEpoch+1,maintenanceCondition=Maintenance.condition(data)}
            local actors,message=trainPositions(data,context,false); if not actors then return nil,message end
            return Party.commit(data,transaction,actors)
        end
    end)
    register("travel.arrive",function(data,state,args,transaction)
        if not fields(args,{}) then return nil,"invalid_arguments" end
        local leg=data.coop.journey
        if not leg or leg.phase~="departed" then return nil,"journey_unavailable" end
        local timing=Engines.timings(data.engineLevel,leg.maintenanceCondition)
        if not state.travelTime or state.travelTime<timing.change then return nil,"not_arrived" end
        return function()
            leg.phase="arrived"; data.location=leg.to; data.stopped=true; data.visitedStops[data.location]=true
            local participants={}
            for _,id in ipairs({"host","companion"}) do if authority.bindings[id]~=nil and Players.get(data,id) then participants[#participants+1]=id end end
            Maintenance.onTravel(data); Train.applyArrival(data,participants)
            local rng=Random.generator(data,transaction.randomSeed)
            Stops.ensure(data,catalog,"train",rng)
            Arrivals.apply(data,catalog,rng,participants)
            local actors,message=trainPositions(data,context,false); if not actors then return nil,message end
            return Party.commit(data,transaction,actors)
        end
    end)
    register("travel.finish",function(data,state,args,transaction)
        if not fields(args,{}) then return nil,"invalid_arguments" end
        local leg=data.coop.journey
        if not leg or leg.phase~="arrived" then return nil,"journey_unavailable" end
        local timing=Engines.timings(data.engineLevel,leg.maintenanceCondition)
        if not state.travelTime or state.travelTime<timing.total then return nil,"not_arrived" end
        return function()
            data.coop.journey=nil
            local actors,message=trainPositions(data,context,false); if not actors then return nil,message end
            local result=Party.commit(data,transaction,actors,data.location>=50 and "ending" or "game")
            result.arrivalNotice=data.arrivalNotice~=nil
            return result
        end
    end)
end
return Commands
