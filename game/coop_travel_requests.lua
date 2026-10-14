-- A departure request is a bounded session notification, not permission to
-- travel. Inspection uses the same host trait/load/engine/maintenance rules as
-- travel.depart on detached scratch state. No campaign field is changed.
local P=require('game.net.protocol')
local Players=require('game.coop_players')
local Schema=require('game.save_schema')
local Progression=require('game.progression_balance')
local Engines=require('game.engine_upgrades')
local Maintenance=require('game.maintenance')
local Train=require('game.train_upgrade_balance')
local Life=require('game.coop_last_stand_lifecycle')
local Results=require('game.net.travel_request_results')
local Requests={LIFETIME=15,COOLDOWN=5,MAX=2147483647}
local quoteFields={from=true,to=true,food=true,water=true,coal=true,sourceRevision=true}
function Requests.scopes()return {'world:scene','resources','train','player:host','player:companion'}end
local function ordinary(data,id,context,motionId)
    local state=context.actorState(id);local host=context.actorState('host')
    return id=='companion' and state and host and state.screen=='game' and state.scene=='train'
        and host.screen=='game' and host.scene=='train' and not host.traveling and not host.encounterActive
        and data.scene=='train' and data.stopped==true and data.location<50
        and not data.coop.journey and not data.tacticalBattle and not data.roamingEncounter
        and not (data.events and data.events.current) and not Life.active(data)
        and not (data.trainAmbush and data.trainAmbush.active) and not state.traveling
        and not state.encounterActive and not state.changingCar and not state.activityBlocked
        and state.movementReady==true and P.integer(state.motionId,1,Requests.MAX) and state.motionId==motionId
end
function Requests.inspect(data,catalog)
    -- Maintenance.coalPenalty normalizes its input. It must only see scratch.
    local host=Players.get(data,'host')
    local scratch=assert(Schema.copy({location=data.location,engineLevel=data.engineLevel,
        trait=host and host.trait,maintenance=data.maintenance,trainCars=data.trainCars,passengers=data.passengers,resources=data.resources}))
    local cost=Progression.travelCost(scratch,Engines,Maintenance,catalog.characterTraitProfiles[1],Train)
    local status=Progression.travelStatus(scratch,cost)
    local result={from=data.location,to=data.location+1,sourceRevision=data.coop.revision,
        food=cost.food,water=cost.water,coal=cost.coal,terrain=cost.terrain,
        passengers=cost.passengers,passengerLoad=cost.passengerLoad,maintenanceCoal=cost.maintenanceCoal,
        navigatorSaved=cost.navigatorSaved,available={},missing={},affordable=status.affordable,
        serial=0,requested=false,already=false}
    for _,name in ipairs({'food','water','coal'})do result.available[name]=data.resources[name];result.missing[name]=status.missing[name]end
    assert(Results.valid(result),'invalid host travel inspection');return result
end
function Requests.install(service,context)
    service:register('progression.request',function(data,id,args,t)
        if not P.fields(args,{action=true,motionId=true,quote=true}) or (args.action~='inspect' and args.action~='depart')
            or not P.integer(args.motionId,1,Requests.MAX)
            or args.action=='inspect' and args.quote~=nil
            or args.action=='depart' and not P.fields(args.quote,quoteFields) then return nil,'invalid_args'end
        if not ordinary(data,id,context,args.motionId)then return nil,'travel_unavailable'end
        local result=Requests.inspect(data,context.catalog)
        if args.action=='depart'then
            for key in pairs(quoteFields)do if args.quote[key]~=result[key]then return nil,'travel_quote_changed'end end
        end
        return {scopes=Requests.scopes(),checkpoint=false,transientOnly=true,effects={},apply=function()
            if args.action=='inspect'then return result end
            local store=t.state.travelRequests or {nextSerial=1};t.state.travelRequests=store
            local previous=store.pending
            if previous and previous.generation==t.generation and previous.epoch==data.coop.sceneEpoch
                and previous.motionId==args.motionId and t.now<previous.expiresAt then
                result.serial=previous.serial;result.requested=true;result.already=true;return result
            end
            if store.lastAt and t.now-store.lastAt<Requests.COOLDOWN then return nil,'request_cooldown'end
            if store.nextSerial>Requests.MAX then return nil,'request_serial_exhausted'end
            result.serial=store.nextSerial;result.requested=true
            store.nextSerial=store.nextSerial+1;store.lastAt=t.now
            store.pending={generation=t.generation,epoch=data.coop.sceneEpoch,motionId=args.motionId,
                serial=result.serial,expiresAt=t.now+Requests.LIFETIME,inspection=result}
            return result
        end}
    end)
end
function Requests.notice(service,context)
    local store=service.activityState.travelRequests;local pending=store and store.pending
    if not pending then return nil end
    if service.pendingSave or service.bindings.companion~=pending.generation
        or service.campaign.coop.sceneEpoch~=pending.epoch or service.clock()>=pending.expiresAt
        or not ordinary(service.campaign,'companion',context,pending.motionId) then store.pending=nil;return nil end
    -- Keep the host's displayed costs current if assistance changes supplies,
    -- maintenance or upgrades after the request. This is still only a notice.
    local inspection=Requests.inspect(service.campaign,context.catalog)
    inspection.serial=pending.serial;inspection.requested=true
    return Results.project(inspection)
end
function Requests.dismiss(service,serial)
    local store=service.activityState.travelRequests;local pending=store and store.pending
    if not pending or pending.serial~=serial then return false end
    store.pending=nil;return true
end
return Requests
