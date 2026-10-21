-- Production persistent-state projection. Runtime enemies, input prediction,
-- cameras and UI widgets have their own later simulation/presentation lanes.
local Codec=require('game.net.codec')
local P=require('game.net.protocol')
local Records=require('game.net.state_records')
local M=require('game.net.state_manifest')
local Schema=require('game.save_schema')
local Players=require('game.coop_players')
local Ownership=require('game.replica_ownership')
local State={}; local Producer={}; Producer.__index=Producer; local Replica={}; Replica.__index=Replica
local LIMITS={maxBytes=P.BASELINE_BYTES,maxDepth=16,maxEntries=200000,maxStringBytes=Records.MAX_STRING}
local MAX=2147483647
local function fail(reason) return nil,reason end
local function pick(source,fields)
    local result={}
    for _,field in ipairs(fields) do result[field]=rawget(source,field) end
    return result
end
local function validNumber(value,minimum,maximum)
    return type(value)=='number' and value==value and value>=minimum and value<=maximum
end
local function validateSlots(values,maximum)
    if type(values)~='table' then return false end
    for key,value in pairs(values) do
        if not P.integer(key,1,maximum) or not P.text(value,128) then return false end
    end
    return true
end
local function assemble(values,epoch)
    local data={players={}}
    for name,fields in pairs(M.groups) do
        local group=values[name]
        if not P.fields(group,M.allowed[name]) then return fail('invalid_'..name..'_fields') end
        for _,field in ipairs(fields) do data[field]=group[field] end
    end
    for _,id in ipairs({'host','companion'}) do
        local actor=values['actor:'..id]
        if not P.fields(actor,M.actorAllowed) or actor.id~=id or not P.text(actor.character,128)
            or not P.integer(actor.inventoryCapacity,1,256) or not validateSlots(actor.inventory,actor.inventoryCapacity)
            or not validateSlots(actor.equipment,16) then return fail('invalid_actor') end
        data.players[id]=actor
    end
    if not P.fields(values.radio,M.allowed.radio) or not P.text(values.radio.station,64)
        or type(values.radio.rainEnabled)~='boolean' then return fail('invalid_radio') end
    local authority=values.authority
    if not P.fields(authority,M.allowed.authority) or not P.integer(authority.sourceRevision,0,MAX)
        or type(authority.scopes)~='table' then return fail('invalid_authority_state') end
    local carCount=Records.dense(data.trainCars,32)
    if not carCount or carCount<1 then return fail('invalid_train_cars') end
    for _,name in ipairs(data.trainCars) do if not P.text(name,128) then return fail('invalid_train_car') end end
    for _,actor in pairs(data.players) do
        if not P.integer(actor.activeCar,1,carCount) or not validNumber(actor.maxHealth,1,1e9)
            or not validNumber(actor.health,0,actor.maxHealth) then return fail('invalid_actor_bounds') end
    end
    if not P.integer(data.location,1,50) or not ({train=true,stop=true,house=true,expedition=true,caravan=true})[data.scene]
        or type(data.stopped)~='boolean' or not validNumber(data.scrap,0,1e9) or not validNumber(data.goodwill,0,1e9)
        or not P.integer(data.engineLevel,0,10000) then return fail('invalid_campaign_state') end
    if not P.fields(data.resources,{food=true,water=true,coal=true,oil=true}) then return fail('invalid_resources') end
    for _,name in ipairs({'food','water','coal','oil'}) do
        if not validNumber(data.resources[name],0,1e9) then return fail('invalid_resource_value') end
    end
    data.audio=values.radio
    data.coop={revision=authority.sourceRevision,sceneEpoch=epoch,revisions=authority.scopes,journey=authority.journey}
    -- Reuse the canonical actor/entity/item consistency checks without exposing
    -- allocation counters or importing any save defaults into the guest view.
    local validation={}; for key,value in pairs(data) do validation[key]=value end
    validation.version=M.SCHEMA; validation.itemIdentity={version=1,nextId=MAX}
    validation.coop={version=1,nextEntityId=MAX,revision=authority.sourceRevision,sceneEpoch=epoch,
        revisions=authority.scopes,journey=authority.journey,preferencesDetached=true}
    local valid,reason=Schema.validate(validation)
    if not valid then return fail(reason) end
    return Ownership.mark(data)
end
function State.audit(campaign)
    if M.SCHEMA~=Schema.CURRENT_VERSION or Ownership.isReplica(campaign) then return fail('invalid_projection_source') end
    local valid,reason=Schema.validate(campaign)
    if not valid then return fail(reason) end
    for key in pairs(campaign) do if not M.known[key] then return fail('unclassified_campaign_field:'..tostring(key)) end end
    for _,actor in pairs(campaign.players) do
        for key in pairs(actor) do if not M.actorAllowed[key] then return fail('unclassified_actor_field:'..tostring(key)) end end
    end
    return true
end
function State.project(campaign)
    local valid,reason=State.audit(campaign)
    if not valid then return fail(reason) end
    if not campaign.players.companion then return fail('companion_missing') end
    local source={}
    for name,fields in pairs(M.groups) do source[name]=pick(campaign,fields) end
    for _,id in ipairs({'host','companion'}) do
        source['actor:'..id]=pick(campaign.players[id],M.actorFields)
    end
    source.radio={station=campaign.audio.station,rainEnabled=campaign.audio.rainEnabled}
    source.authority={sourceRevision=campaign.coop.revision,scopes=campaign.coop.revisions,journey=campaign.coop.journey}
    local records,encoded,values={},{},{}; local budget=Records.budget()
    for _,name in ipairs(M.order) do
        local record,errorMessage=Records.encode(source[name],budget)
        if not record then return fail(errorMessage) end
        local bytes,encodeError=Codec.encode(record,LIMITS)
        if not bytes then return fail(encodeError) end
        records[name]=record; encoded[name]=bytes
        values[name]=assert(Records.decode(record))
    end
    local view,viewError=assemble(values,campaign.coop.sceneEpoch)
    if not view then return fail(viewError) end
    return {records=records,encoded=encoded,sceneEpoch=campaign.coop.sceneEpoch,view=view}
end
local function packet(projection,revision,old)
    local changed=Codec.array({})
    for _,id in ipairs(M.order) do
        if not old or projection.encoded[id]~=old.encoded[id] then
            changed[#changed+1]={id=id,record=projection.records[id]}
        end
    end
    if old and #changed==0 then return nil end
    local message={kind='mouse-frontier-state',version=M.VERSION,schema=M.SCHEMA,revision=revision,
        sceneEpoch=projection.sceneEpoch,mode=old and 'delta' or 'baseline',domains=changed}
    if old then message.baseRevision=revision-1 end
    local bytes,reason=Codec.encode(message,LIMITS)
    if not bytes then return fail(reason) end
    return message
end
function State.producer() return setmetatable({revision=0},Producer) end
function Producer:capture(campaign,full)
    local projection,reason=State.project(campaign)
    if not projection then return fail(reason) end
    local old=not full and self.current and self.current.sceneEpoch==projection.sceneEpoch and self.current or nil
    if self.revision>=MAX then return fail('replica_revision_exhausted') end
    local message,errorMessage=packet(projection,self.revision+1,old)
    if not message then return nil,errorMessage end
    self.current=projection; self.revision=message.revision
    return message
end
function Producer:baseline()
    if not self.current then return fail('replica_uninitialized') end
    return packet(self.current,self.revision,nil)
end
function State.replica() return setmetatable({revision=0,records={}},Replica) end
function Replica:prepare(message)
    if not P.fields(message,{kind=true,version=true,schema=true,revision=true,sceneEpoch=true,mode=true,baseRevision=true,domains=true})
        or message.kind~='mouse-frontier-state' or message.version~=M.VERSION or message.schema~=M.SCHEMA
        or not P.integer(message.revision,1,MAX) or not P.integer(message.sceneEpoch,1,MAX)
        or (message.mode~='baseline' and message.mode~='delta') then return fail('invalid_replica_envelope') end
    if message.revision<=self.revision or (self.sceneEpoch and message.sceneEpoch<self.sceneEpoch) then return fail('stale_replica') end
    if message.mode=='delta' then
        if message.baseRevision~=self.revision or message.revision~=self.revision+1 or message.sceneEpoch~=self.sceneEpoch
            or not self.data then return fail('replica_gap') end
    elseif message.baseRevision~=nil then return fail('invalid_replica_base') end
    local count=Records.dense(message.domains,#M.order)
    if not count or count==0 or (message.mode=='baseline' and count~=#M.order) then return fail('invalid_replica_domains') end
    local records={}; if message.mode=='delta' then for name,bytes in pairs(self.records) do records[name]=bytes end end
    local seen={}
    for _,domain in ipairs(message.domains) do
        if not P.fields(domain,{id=true,record=true}) or not M.allowed[domain.id] or seen[domain.id] then return fail('invalid_replica_domain') end
        seen[domain.id]=true
        local bytes,reason=Codec.encode(domain.record,LIMITS)
        if not bytes then return fail(reason) end
        records[domain.id]=bytes
    end
    local values={}; local budget=Records.budget(); local total=0
    for _,name in ipairs(M.order) do
        local bytes=records[name]; if not bytes then return fail('missing_replica_domain') end
        total=total+#bytes; if total>P.BASELINE_BYTES then return fail('replica_size_limit') end
        local record,decodeError=Codec.decode(bytes,LIMITS)
        if not record then return fail(decodeError) end
        local value,reason=Records.decode(record,budget)
        if not value then return fail(reason) end
        values[name]=value
    end
    local data,reason=assemble(values,message.sceneEpoch)
    if not data then return fail(reason) end
    if self.data then
        if data.coop.revision<self.authorityRevision then return fail('authority_regressed') end
        for scope,revision in pairs(self.scopes) do
            if (data.coop.revisions[scope] or 0)<revision then return fail('scope_regressed') end
        end
    end
    local scopes={}; for name,revision in pairs(data.coop.revisions) do scopes[name]=revision end
    return {data=data,records=records,revision=message.revision,sceneEpoch=message.sceneEpoch,
        authorityRevision=data.coop.revision,scopes=scopes}
end
function Replica:validate(message) local prepared,reason=self:prepare(message); return prepared~=nil,reason end
local function commit(self,prepared)
    self.data=prepared.data; self.records=prepared.records; self.revision=prepared.revision; self.sceneEpoch=prepared.sceneEpoch
    self.authorityRevision=prepared.authorityRevision; self.scopes=prepared.scopes
    return true
end
-- Stage the fully decoded, validated result while the network acknowledges
-- receipt. The one-use closure owns that detached result; callers cannot
-- substitute unvalidated fields or commit it over a newer replica.
function Replica:stage(message)
    local prepared,reason=self:prepare(message)
    if not prepared then return nil,reason end
    local revision,data=self.revision,self.data
    local used=false
    return function()
        if used or self.revision~=revision or self.data~=data then return nil,'stale_staged_replica' end
        used=true
        return commit(self,prepared)
    end
end
function Replica:apply(message)
    local prepared,reason=self:prepare(message)
    if not prepared then return nil,reason end
    return commit(self,prepared)
end
function Replica:actor(id) return self.data and Players.forActor(self.data,id or 'companion') end
State.manifest=M
return State
