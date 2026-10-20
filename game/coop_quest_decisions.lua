-- Persistent host offers and decisions. Guest assistance consumes accepted
-- work through coop_quests; it cannot create or accept an offer here.
local Access=require('game.coop_recipient_access')
local Leases=require('game.coop_leases')
local Progression=require('game.quest_progression')
local Passengers=require('game.passengers')
local Help=require('game.stop_help_progression')
local Sessions=require('game.help_quest_session')
local Relationships=require('game.npc_relationships')
local Entities=require('game.coop_entities')
local Items=require('game.item_instances')
local Random=require('game.coop_random')
local P=require('game.net.protocol')
local Catalog=require('game.catalog')
local Identity=require('game.npc_identity')
local Targets=require('game.npc_targets')
local Decisions={}
local kinds={mail=true,ride=true,supplies=true,trade=true,item=true,aid=true}
local function key(data,npc) return tostring(data.location)..':'..npc end
local function helpRequest(data,layout,npc,kind)
    local request=layout.helpRequests and layout.helpRequests[npc]
    local quest=request and data.helpQuestSessions and data.helpQuestSessions[request.sessionId]
    if not request or request.kind~=kind or request.accepted or request.complete or not quest
        or quest.npc~=npc or quest.location~=data.location or quest.state~='offered'
        or quest.source~=(kind=='aid' and 'first-aid' or 'item-request') then return nil end
    return request,quest
end

function Decisions.text(layout,npc,offer,catalog)
    if offer.kind=='mail' then return catalog.mailRequestLines[offer.lineIndex]
    elseif offer.kind=='ride' then return catalog.rideRequestLines[offer.lineIndex]
    elseif offer.kind=='supplies' then return Progression.deliveryProfile(offer.deliveryKind).request
    elseif offer.kind=='item' or offer.kind=='aid' then
        local request=layout.helpRequests and layout.helpRequests[npc]; return request and request.text
    else return 'Trade available.' end
end

function Decisions.validateOffers(data)
    for stop,layout in pairs(data.stopLayouts or {}) do
        local offers=type(layout)=='table' and layout.coopOffers
        if offers~=nil then
            if type(offers)~='table' then return false end
            for npc,offer in pairs(offers) do
                if not P.text(npc,128) or not P.fields(offer,{kind=true,status=true,location=true,lineIndex=true,
                    deliveryKind=true,requestSessionId=true}) or not kinds[offer.kind]
                    or not P.integer(offer.location,1,49) or tostring(offer.location)~=tostring(stop)
                    or (offer.status~='offered' and offer.status~='accepted' and offer.status~='declined') then return false end
                local asked=(data.questAsked or {})[tostring(offer.location)..':'..npc]
                if (offer.status=='offered' and asked) or (offer.status~='offered' and asked~=true) then return false end
                if offer.kind=='mail' or offer.kind=='ride' then
                    local lines=offer.kind=='mail' and Catalog.mailRequestLines or Catalog.rideRequestLines
                    if not P.integer(offer.lineIndex,1,#lines) or offer.deliveryKind~=nil or offer.requestSessionId~=nil then return false end
                elseif offer.kind=='supplies' then
                    if not Progression.deliveryIndex[offer.deliveryKind] or offer.lineIndex~=nil or offer.requestSessionId~=nil
                        or type(layout.deliveryOffers)~='table' or layout.deliveryOffers[npc]~=offer.deliveryKind then return false end
                elseif offer.kind=='item' or offer.kind=='aid' then
                    if type(layout.helpRequests)~='table' then return false end
                    local request=layout.helpRequests[npc]
                    if type(request)~='table' then return false end
                    local quest=data.helpQuestSessions and data.helpQuestSessions[request.sessionId]
                    if not P.text(offer.requestSessionId,62) or offer.lineIndex~=nil or offer.deliveryKind~=nil
                        or request.kind~=offer.kind or request.sessionId~=offer.requestSessionId or type(quest)~='table'
                        or quest.npc~=npc or quest.location~=offer.location
                        or quest.source~=(offer.kind=='aid' and 'first-aid' or 'item-request')
                        or (offer.status=='accepted' and (request.accepted~=true or quest.state=='offered'
                            or (request.complete==true)~=(quest.state=='resolved')))
                        or (offer.status~='accepted' and (request.accepted or request.complete)) then return false end
                elseif offer.lineIndex~=nil or offer.deliveryKind~=nil or offer.requestSessionId~=nil then return false end
            end
        end
    end
    return true
end

function Decisions.install(authority,context)
    local catalog=context.catalog
    local function target(data,args,transaction)
        local found=Access.find(data,args.targetId,args.npc,context.actorState('host'))
        if not found or found.kind~='resident' then return nil,'recipient_unavailable' end
        if Leases.npcBusy(transaction.state,args.targetId,args.npc) then return nil,'activity_busy' end
        local kind=found.target.npcOffers and found.target.npcOffers[args.npc]
        if not kinds[kind] or data.location>=50 or (data.questAsked or {})[key(data,args.npc)] then return nil,'offer_unavailable' end
        return found.target,kind
    end
    authority:register('quest.offer',function(data,actorId,args,transaction)
        if not P.fields(args,{targetId=true,npc=true}) then return nil,'invalid_args' end
        local layout,kind=target(data,args,transaction); if not layout then return nil,kind end
        local request,quest
        if kind=='item' or kind=='aid' then
            request,quest=helpRequest(data,layout,args.npc,kind); if not request then return nil,'quest_unavailable' end
        end
        local existing=layout.coopOffers and layout.coopOffers[args.npc]
        if existing and (existing.kind~=kind or existing.status~='offered') then return nil,'offer_changed' end
        return {scopes={'entity:'..args.targetId,'story:questOffers','world:quests','rng'},apply=function()
            layout.coopOffers=layout.coopOffers or {}
            local offer=existing
            if not offer then
                offer={kind=kind,status='offered',location=data.location,requestSessionId=quest and quest.id}
                local raw=Random.generator(data,transaction.randomSeed); local rng=Random.range(raw)
                if kind=='mail' or kind=='ride' then
                    local lines=kind=='mail' and catalog.mailRequestLines or catalog.rideRequestLines
                    if not lines or #lines==0 then return nil,'offer_unavailable' end
                    offer.lineIndex=rng(1,#lines)
                elseif kind=='supplies' then
                    layout.deliveryOffers=layout.deliveryOffers or {}
                    offer.deliveryKind=layout.deliveryOffers[args.npc]
                    if not offer.deliveryKind then
                        data.supplyDeliveryCycle=data.supplyDeliveryCycle or {seen={}}
                        offer.deliveryKind=Progression.rollDelivery(data.location,raw,data.supplyDeliveryCycle)
                        layout.deliveryOffers[args.npc]=offer.deliveryKind
                    end
                    if not Progression.deliveryIndex[offer.deliveryKind] then return nil,'offer_unavailable' end
                end
                layout.coopOffers[args.npc]=offer
            end
            return {ok=true,offer=offer}
        end}
    end)
    local function decision(data,actorId,args,transaction,decline,recruit)
        if not P.fields(args,{targetId=true,npc=true,kind=true}) or not kinds[args.kind] then return nil,'invalid_args' end
        local layout,kind=target(data,args,transaction); if not layout then return nil,kind end
        local offer=layout.coopOffers and layout.coopOffers[args.npc]
        if kind~=args.kind or not offer or offer.kind~=kind or offer.status~='offered'
            or recruit and kind~='ride' then return nil,'offer_changed' end
        if not decline and kind=='ride' and Targets.pending(data,args.npc) then return nil,'recipient_has_delivery' end
        local request,quest
        if kind=='item' or kind=='aid' then
            request,quest=helpRequest(data,layout,args.npc,kind)
            if not request or offer.requestSessionId~=quest.id then return nil,'quest_unavailable' end
        end
        local scopes={'entity:'..args.targetId,'story:questOffers','world:quests'}
        if quest then scopes[#scopes+1]='quest:'..quest.id end
        if not decline and (kind=='mail' or kind=='ride' or kind=='supplies') then scopes[#scopes+1]='rng' end
        if not decline and (kind=='mail' or kind=='supplies' or kind=='ride') then scopes[#scopes+1]='people:identities' end
        if not decline and (kind=='mail' or kind=='supplies') then scopes[#scopes+1]='world:stops' end
        if not decline and kind=='ride' then scopes[#scopes+1]='relationships'; scopes[#scopes+1]='resources' end
        return {scopes=scopes,apply=function()
            data.questAsked=data.questAsked or {}; data.questAsked[key(data,args.npc)]=true
            offer.status=decline and 'declined' or 'accepted'
            local result={ok=true,kind=kind,declined=decline==true,accepted=not decline}
            if decline then return result end
            if quest then
                request.accepted=true; Sessions.accept(data,quest.id); result.questId=quest.id
                if kind=='aid' and not Help.medicalItem(data,catalog) then
                    Sessions.investigate(data,quest.id,'Find a medical supply and return to the wounded critter.')
                end
            elseif kind=='trade' then return result
            else
                local raw=Random.generator(data,transaction.randomSeed); local rng=Random.range(raw)
                local distance=kind=='ride' and Passengers.rideLength(Passengers.jobFor(args.npc),50-data.location,
                    data.resources.food,data.resources.water,rng(-1,1)) or Progression.questDistance(kind,data.location,raw)
                local destination=data.location+distance
                if destination<=data.location or destination>50 then return nil,'destination_unavailable' end
                local record
                if kind=='mail' then
                    record={sender=args.npc,origin=data.location,destination=destination,complete=false}
                    Targets.bind(data,record,rng)
                    data.mailQuests[#data.mailQuests+1]=record; result.recipient=record.recipient
                elseif kind=='supplies' then
                    if not Progression.deliveryIndex[offer.deliveryKind] then return nil,'offer_changed' end
                    record={sender=args.npc,origin=data.location,destination=destination,amount=Progression.deliveryProfile(offer.deliveryKind).amount,
                        cargoKind=offer.deliveryKind,complete=false}
                    Targets.bind(data,record,rng)
                    data.supplyQuests[#data.supplyQuests+1]=record; result.deliveryKind=offer.deliveryKind
                else
                    local car=context.car
                    if not car or not P.clock(car.x) or not P.clock(car.y) then return nil,'passenger_spawn_unavailable' end
                    local x,y=car.x+225+#data.passengers*85,car.y+285
                    if x>=100000 or y>=100000 then return nil,'passenger_spawn_unavailable' end
                    if Items.enabled(data) then assert(Items.ensure(data)) end
                    local person=Identity.get(data,args.npc) or Identity.ensure(data,args.npc,data.location,1)
                    record={npc=args.npc,characterId=person.id,origin=data.location,destination=destination,x=x,y=y,homeX=x,homeY=y,wait=1,
                        job=Passengers.jobFor(args.npc),pose='idle',weapon=layout.npcWeapon}
                    if Items.enabled(data) then
                        record.weaponInstance=layout.npcWeaponInstance; layout.npcWeapon=nil; layout.npcWeaponInstance=nil
                    end
                    data.passengers[#data.passengers+1]=record
                    Identity.board(data,record)
                    Relationships.recordRide(data,person.id); result.job=record.job
                end
                assert(Entities.ensure(data)); result.entityId=record.entityId; result.destination=destination
                result.reward=Progression.rewardProfile(kind=='supplies' and offer.deliveryKind or kind,distance,data.trait,destination)
            end
            return result
        end}
    end
    authority:register('quest.accept',function(data,id,args,t) return decision(data,id,args,t,false,false) end)
    authority:register('quest.decline',function(data,id,args,t) return decision(data,id,args,t,true,false) end)
    authority:register('passenger.recruit',function(data,id,args,t) return decision(data,id,args,t,false,true) end)
end
return Decisions
