-- Portable character data. A visit keeps the local world intact and reserves
-- its traveler until the host returns a final, frozen character checkpoint.
local Players=require('game.coop_players')
local Items=require('game.item_instances')
local P=require('game.net.protocol')
local Crypto=require('game.net.crypto')
local Codec=require('game.net.codec')
local Records=require('game.net.state_records')
local Traveler={VERSION=1}
local excluded={playerX=true,playerY=true,playerFacing=true,activeCar=true,weapons=true}
local fields={}
for field in pairs(Players.personalFields) do if not excluded[field] then fields[field]=true end end
local limits={maxBytes=65536,maxDepth=12,maxEntries=4096,maxStringBytes=256}
local function copy(value)
    if type(value)~='table' then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function digest(value) return Crypto.isHex(value,32) end
function Traveler.validIdentity(value)
    return P.fields(value,{version=true,profileId=true,tripId=true,serial=true,status=true}) and value.version==1
        and digest(value.profileId) and digest(value.tripId) and P.integer(value.serial,1,2147483647)
        and (value.status=='active' or value.status=='returned' or value.status=='closed')
end
function Traveler.sameVisit(value,profile)
    return value and profile and value.profileId==profile.profileId and value.tripId==profile.tripId and value.serial==profile.serial
end
function Traveler.exportActor(data,id)
    local source=Players.get(Players.campaignOf(data),id); if not source then return nil,'missing_traveler' end
    local result={}; for field in pairs(fields) do result[field]=copy(source[field]) end
    return result
end
function Traveler.validateActor(actor,allowed)
    if not P.fields(actor,fields) or not P.text(actor.character,128)
        or allowed and allowed[actor.character]~=true or not P.integer(actor.inventoryCapacity,1,256)
        or not P.clock(actor.health) or not P.clock(actor.maxHealth) or actor.maxHealth>1000000000 then return false end
    local recordWire=Records.encode(actor)
    if not recordWire or not Codec.encode(recordWire,limits) then return false end
    local record=copy(actor); record.id='host'; record.playerX=0; record.playerY=0; record.playerFacing=1; record.activeCar=1
    local probe={players={host=record},itemIdentity={version=1,nextId=2147483647}}
    if not Players.validate(probe) or not Items.validate(probe) then return false end
    for _,kind in ipairs({'inventory','equipment'}) do
        for key,name in pairs(record[kind]) do
            if not P.integer(key,1,kind=='inventory' and record.inventoryCapacity or 2) or not P.text(name,128) then return false end
        end
    end
    for _,kind in ipairs({'stats','ammo','weaponDurability','weaponProficiency'}) do
        for key,value in pairs(record[kind]) do
            if not P.text(key,128) or type(value)~='number' or not P.clock(value) or value>1000000000 then return false end
        end
    end
    for key,value in pairs(record.nextBattlePotions) do
        if not P.text(key,128) or value~=true then return false end
    end
    return true
end
function Traveler.validEnvelope(profile,allowed)
    return P.fields(profile,{version=true,profileId=true,tripId=true,serial=true,actor=true})
        and profile.version==Traveler.VERSION and digest(profile.profileId) and digest(profile.tripId)
        and P.integer(profile.serial,1,2147483647) and Traveler.validateActor(profile.actor,allowed)
end
function Traveler.pack(profile)
    if not Traveler.validEnvelope(profile) then return nil,'invalid_traveler' end
    local result=copy(profile); result.actor=assert(Records.encode(profile.actor))
    if not Codec.encode(result,limits) then return nil,'traveler_too_large' end
    return result
end
function Traveler.unpack(wire,allowed)
    if not P.fields(wire,{version=true,profileId=true,tripId=true,serial=true,actor=true}) then return nil,'invalid_traveler' end
    if not Codec.encode(wire,limits) then return nil,'traveler_too_large' end
    local result=copy(wire); result.actor=Records.decode(wire.actor)
    if not Traveler.validEnvelope(result,allowed) then return nil,'invalid_traveler' end
    return result
end
function Traveler.validate(data)
    for _,actor in pairs(data.players or {}) do
        if actor.travelIdentity and not Traveler.validIdentity(actor.travelIdentity) then return false,'invalid visiting traveler' end
        local returned=actor.travelReturn
        if returned then
            local profile=type(returned)=='table' and Traveler.unpack(returned.profile)
            if not P.fields(returned,{profile=true,revision=true}) or not profile
                or not Traveler.sameVisit(actor.travelIdentity,profile) or actor.travelIdentity.status=='active'
                or not P.integer(returned.revision,1,2147483647) then return false,'invalid returned traveler' end
        elseif actor.travelIdentity and actor.travelIdentity.status~='active' then return false,'missing returned traveler' end
    end
    local count=0
    if data.travelerHistory~=nil and type(data.travelerHistory)~='table' then return false,'invalid traveler history' end
    for id,entry in pairs(data.travelerHistory or {}) do
        count=count+1
        if count>256 or not digest(id) or not P.fields(entry,{tripId=true,serial=true})
            or not digest(entry.tripId) or not P.integer(entry.serial,1,2147483647) then return false,'invalid traveler history' end
    end
    local localState=data.localTraveler
    if localState==nil then return true end
    if not P.fields(localState,{version=true,id=true,serial=true,trip=true,lastReturn=true}) or localState.version~=1
        or not digest(localState.id) or not P.integer(localState.serial,0,2147483647) then return false,'invalid local traveler' end
    local trip=localState.trip
    if trip and (not P.fields(trip,{id=true,campaignId=true,address=true,serial=true,appliedRevision=true})
        or not digest(trip.id) or not digest(trip.campaignId) or not P.text(trip.address,160)
        or trip.serial~=localState.serial or not P.integer(trip.appliedRevision,0,2147483647)) then return false,'invalid traveler visit' end
    local returned=localState.lastReturn
    if returned and (not P.fields(returned,{id=true,campaignId=true,revision=true,serial=true,pending=true})
        or not digest(returned.id) or not digest(returned.campaignId) or not P.integer(returned.revision,1,2147483647)
        or returned.pending~=nil and type(returned.pending)~='boolean'
        or not P.integer(returned.serial,1,localState.serial)) then return false,'invalid traveler return' end
    return true
end
function Traveler.isAway(data) return data and data.localTraveler and data.localTraveler.trip~=nil or false end
function Traveler.checkout(data,campaignId,address,profileId,tripId)
    if not digest(campaignId) or not digest(profileId) or not digest(tripId) or not P.text(address,160) then return nil,'invalid_visit' end
    local draft=assert(require('game.save_schema').copy(data))
    draft.localTraveler=draft.localTraveler or {version=1,id=profileId,serial=0}
    local state=draft.localTraveler
    if state.trip then
        if state.trip.campaignId~=campaignId then return nil,'traveler_away' end
    elseif state.lastReturn and state.lastReturn.pending then
        local last=state.lastReturn
        if last.campaignId~=campaignId then return nil,'traveler_ack_pending' end
        return draft,{version=1,profileId=state.id,tripId=last.id,serial=last.serial,actor=Traveler.exportActor(draft,'host')}
    else
        if state.serial>=2147483647 then return nil,'traveler_serial_exhausted' end
        state.serial=state.serial+1
        state.trip={id=tripId,campaignId=campaignId,address=address,serial=state.serial,appliedRevision=0}
    end
    local profile={version=1,profileId=state.id,tripId=state.trip.id,serial=state.serial,actor=Traveler.exportActor(draft,'host')}
    if not Traveler.validEnvelope(profile) then return nil,'invalid_traveler' end
    return draft,profile
end
function Traveler.replaceActor(data,id,portable,allowed)
    if not Traveler.validateActor(portable,allowed) then return nil,'invalid_traveler' end
    local destination=Players.get(data,id); if not destination then return nil,'missing_traveler' end
    local replacement=copy(portable)
    local count=0; for _,slots in pairs(replacement.itemSlots or {}) do for _ in pairs(slots) do count=count+1 end end
    if not data.itemIdentity or data.itemIdentity.nextId+count>2147483647 then return nil,'item_ids_exhausted' end
    -- Item IDs are scoped to each world. Allocate new local IDs so visiting
    -- gear cannot collide with a chest or merchant's identically numbered gear.
    for _,slots in pairs(replacement.itemSlots or {}) do
        for _,instance in pairs(slots) do
            local fresh=Items.create(data,instance.name,instance.durability)
            if not fresh then return nil,'invalid_traveler_item' end
            instance.id=fresh.id
        end
    end
    for field in pairs(fields) do destination[field]=replacement[field] end
    return destination
end
function Traveler.applyCheckpoint(data,profile,receipt,allowed)
    if not Traveler.validEnvelope(profile,allowed) or not P.fields(receipt,{campaignId=true,revision=true,returned=true})
        or not digest(receipt.campaignId) or not P.integer(receipt.revision,1,2147483647)
        or type(receipt.returned)~='boolean' then return nil,'invalid_traveler_checkpoint' end
    local state=data.localTraveler; local trip=state and state.trip
    if not state or state.id~=profile.profileId then return nil,'traveler_identity_mismatch' end
    if not trip then
        local last=state.lastReturn
        if receipt.returned and last and last.id==profile.tripId and last.campaignId==receipt.campaignId
            and last.revision==receipt.revision and last.serial==profile.serial then return assert(require('game.save_schema').copy(data)),'already_returned' end
        return nil,'traveler_not_away'
    end
    if trip.id~=profile.tripId or trip.serial~=profile.serial or trip.campaignId~=receipt.campaignId then return nil,'traveler_visit_mismatch' end
    if receipt.revision<trip.appliedRevision then return nil,'stale_traveler_checkpoint' end
    local draft=assert(require('game.save_schema').copy(data)); local nextState=draft.localTraveler
    -- Ordered replicas can include passive progression at the same command
    -- revision. The client coalesces unchanged profiles before writing them.
    if receipt.revision>trip.appliedRevision or not receipt.returned then
        local actor,reason=Traveler.replaceActor(draft,'host',profile.actor,allowed); if not actor then return nil,reason end
        nextState.trip.appliedRevision=receipt.revision
    end
    if receipt.returned then
        nextState.lastReturn={id=trip.id,campaignId=trip.campaignId,revision=receipt.revision,serial=trip.serial}
        nextState.trip=nil
    end
    if not require('game.save_schema').validate(draft) then return nil,'invalid_return_save' end
    return draft
end
return Traveler
