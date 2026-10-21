-- Trusted peer bindings are passed separately from wire requests. Handlers
-- stage changes on a detached campaign; only validated successes commit.
local Schema=require("game.save_schema")
local Players=require("game.coop_players")
local Entities=require("game.coop_entities")
local Capabilities=require("game.coop_capabilities")
local Codec=require("game.net.codec")
local Items=require("game.item_instances")
local Leases=require("game.coop_leases")
local Random=require("game.coop_random")
local Receipts=require("game.coop_receipts")
local Authority={}
Authority.__index=Authority
local MAX_REVISION=2147483647
local ENVELOPE={sessionId=true,requestId=true,sceneEpoch=true,command=true,args=true,expected=true}
local LIMITS={maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128}

local function integer(value,minimum)
    return type(value)=="number" and value==math.floor(value) and value>=minimum and value<=MAX_REVISION
end

local function copy(value) return assert(Schema.copy(value)) end
local function failure(reason) return {ok=false,reason=reason,durable=false} end
local function same(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for key,value in pairs(a)do if not same(value,b[key])then return false end end
    for key in pairs(b)do if a[key]==nil then return false end end
    return true
end

-- Keep UI/domain references live, including a container that changes its array
-- offset when another item is removed. Removed entities never impersonate the
-- next entity at their former offset.
local function commit(target,source)
    local objects={}
    local sourceObjects={}
    for _,record in ipairs(Entities.records(target)) do
        if record.value.entityId then objects[record.value.entityId]=record.value end
    end
    for _,record in ipairs(Entities.records(source)) do sourceObjects[record.value]=true end
    local function merge(dst,src)
        local values={}
        for key,value in pairs(src) do
            if type(value)=="table" then
                local old=rawget(dst,key)
                -- Receipts and activity payloads can mention an entity ID.
                -- Only actual source entities may reuse the live object.
                if sourceObjects[value] then old=objects[value.entityId]
                elseif type(old)=="table" and old.entityId and objects[old.entityId]==old then old=nil end
                -- Changing a selected gun must not overwrite the cached record
                -- for its previous exact item through a shared table alias.
                if key=='weaponSession' and type(old)=='table' and (old.actorId~=value.actorId
                    or old.itemId~=value.itemId or old.weapon~=value.weapon or old.borrowed~=value.borrowed) then old=nil end
                values[key]=merge(type(old)=="table" and old or {},value)
            else values[key]=value end
        end
        for key in pairs(dst) do if values[key]==nil then rawset(dst,key,nil) end end
        for key,value in pairs(values) do rawset(dst,key,value) end
        return dst
    end
    merge(target,source)
    Players.attachHost(target)
end

function Authority.new(context)
    assert(type(context)=="table" and type(context.campaign)=="table","authority requires campaign")
    assert(type(context.sessionId)=="string" and #context.sessionId>0 and #context.sessionId<=64,"authority requires session ID")
    assert(Random.valid(context.randomSeed or 1),"authority requires a valid host random seed")
    assert(Entities.ensure(context.campaign))
    if Items.enabled(context.campaign) then assert(Items.ensure(context.campaign)) end
    assert(Schema.validate(context.campaign))
    assert(context.checkpoint==nil or type(context.checkpoint)=="function","invalid checkpoint callback")
    assert(not context.checkpoint or #context.sessionId<=53,"checkpoint session prefix exceeds limit")
    local self=setmetatable({campaign=context.campaign,sessionId=context.sessionId,handlers={},
        bindings={host=0},requests={},busy=false,cacheLimit=64,
        checkpoint=context.checkpoint,
        activityState=Leases.new(),randomSeed=context.randomSeed or 1,
        clock=context.clock or function() return love and love.timer and love.timer.getTime() or os.clock() end},Authority)
    if self.checkpoint then
        local serial=assert(Receipts.beginSession(self.campaign))
        self.sessionSerial=serial
        self.sessionId=context.sessionId..":"..serial
        assert(#self.sessionId<=64,"checkpoint session ID exceeds limit")
        self.pendingSave={session=true}
        self:retryCheckpoint()
    end
    return self
end

function Authority:retryCheckpoint()
    if not self.pendingSave then return true end
    if self.saving then return false end
    if self.campaign.coop.checkpoints.sessionSerial~=self.sessionSerial then return false end
    self.saving=true
    local ok,saved=pcall(self.checkpoint,self.campaign)
    self.saving=false
    if not ok or saved~=true then return false end
    local pending=self.pendingSave
    if pending.actorId then
        local history=self.requests[pending.actorId]
        local cached=history and history.cache[pending.requestId]
        if cached then cached.response.durable=true; cached.response.savePending=nil end
    end
    self.pendingSave=nil
    return true
end

function Authority:checkpointStatus()
    local pending=self.pendingSave
    return {pending=pending~=nil,requestId=pending and pending.requestId,
        actorId=pending and pending.actorId,revision=pending and pending.revision}
end

-- Hosting must checkpoint current ordinary edits as well as critical receipts
-- before opening a socket. Reuse the visible retry barrier on I/O failure.
function Authority:checkpointNow()
    if not self.checkpoint then return false,'checkpoint_required' end
    if self.sessionSerial~=self.campaign.coop.checkpoints.sessionSerial then return false,'stale_authority' end
    if not self.pendingSave then self.pendingSave={session=true} end
    local saved=self:retryCheckpoint()
    if saved then return true end
    return false,'save_not_ready'
end

function Authority:suspendActivities()
    for actorId in pairs(self.bindings) do Leases.releaseActor(self.activityState,actorId) end
end

-- Receipt lookup is read-only and requires a currently admitted actor. Old
-- envelopes still fail execute's session check, even when their receipt exists.
function Authority:receipt(actorId,generation,sessionId,requestId,fingerprint)
    if self.sessionSerial and self.campaign.coop.checkpoints.sessionSerial~=self.sessionSerial then return failure("stale_authority") end
    if self.bindings[actorId]==nil or self.bindings[actorId]~=generation then return failure("unbound_peer") end
    local entry=Receipts.find(self.campaign,actorId,sessionId,requestId)
    if not entry then return failure("receipt_unavailable") end
    if entry.fingerprint~=fingerprint then return failure("request_conflict") end
    local response=copy(entry.response)
    local pending=self.pendingSave
    -- A fresh authority can receive an in-memory campaign whose previous
    -- checkpoint failed. Its preflight must verify that journal before any
    -- carried receipt may promise persistence.
    if pending and (pending.session or pending.actorId==actorId and pending.requestId==requestId and self.sessionId==sessionId) then
        response.durable=false; response.savePending=true
    end
    return response
end

function Authority:register(name,handler)
    assert(Capabilities.commands[name] and not self.handlers[name],"invalid or repeated command handler")
    assert(type(handler)=="function","handler must prepare a transaction")
    self.handlers[name]=handler
end

-- Called only by the admission layer, never by a command or a claimed role.
-- Keep dedup history across rejoin; a lost response can be queried safely.
function Authority:admit(actorId,generation)
    assert(actorId==Players.COMPANION and Players.get(self.campaign,actorId),"unknown companion")
    assert(integer(generation,1) and generation>(self.lastGeneration or 0),"stale peer generation")
    self.lastGeneration=generation
    self.bindings[actorId]=generation
    Leases.releaseActor(self.activityState,actorId)
end

function Authority:disconnect(actorId,generation)
    if actorId~=Players.HOST and self.bindings[actorId]==generation then
        self.bindings[actorId]=nil
        Leases.releaseActor(self.activityState,actorId)
    end
end

function Authority:sweepActivities()
    local now=self.clock()
    assert(type(now)=="number" and now==now and now>=0 and now<math.huge,"invalid authority clock")
    self.lastNow=math.max(self.lastNow or 0,now)
    Leases.sweep(self.activityState,self.lastNow,self.campaign.coop.sceneEpoch,self.bindings,
        require('game.coop_last_stand_lifecycle').key(self.campaign))
    if self.activityState.positionOccupancy then
        local positions=require('game.coop_last_stand_positions')
        require('game.coop_last_stand_occupancy').sweep(self.activityState.positionOccupancy,
            positions.domain and positions.domain(self.campaign),self.bindings,self.lastNow)
    end
    return self.lastNow
end

function Authority:_prepare(actorId,name,args,draft,activities)
    local allowed,reason=Capabilities.authorize(name,Players.role(draft,actorId))
    if not allowed then return nil,reason end
    local identity=Players.get(draft,actorId).travelIdentity
    if identity and identity.status~='active' and name~='traveler.return' and name~='traveler.ack' then return nil,'traveler_returned' end
    if require('game.coop_last_stand_lifecycle').active(draft) and not name:match('^lastStand%.')
        and not name:match('^session%.')
        and not name:match('^traveler%.')
        and not (name:match('^gun%.') and args.mode=='lastStand')
        and not ({['inventory.swap']=true,['inventory.equip']=true,['inventory.consume']=true,['weapon.select']=true})[name] then
        return nil,'modal_scene'
    end
    if draft.roamingEncounter and name~='battle.begin' and name~='scene.returnTrain' and name~='session.kick'
        and name~='traveler.ack' then return nil,'encounter_pending' end
    local handler=self.handlers[name]
    if not handler then return nil,"not_implemented" end
    -- Guest handlers resolve scene-dependent objects through that actor's
    -- fixed view. Shared writes still target this detached host-owned draft.
    local actorData=actorId=='companion' and Players.forActor(draft,actorId) or draft
    local operation,prepareError=handler(actorData,actorId,args,activities)
    if not operation then return nil,prepareError or "invalid_action" end
    if type(operation)~="table" or type(operation.apply)~="function" or type(operation.scopes)~="table" then
        return nil,"invalid_handler"
    end
    if operation.checkpoint~=nil and type(operation.checkpoint)~="boolean" then return nil,"invalid_handler" end
    -- This one notification can commit session state, never campaign state.
    if name=='progression.request' and operation.transientOnly~=true then return nil,'invalid_handler'end
    if operation.transientOnly~=nil and (operation.transientOnly~=true or name~='progression.request'
        or operation.checkpoint~=false or next(operation.effects or {})~=nil) then return nil,'invalid_handler'end
    allowed,reason=Capabilities.authorize(name,Players.role(draft,actorId),operation.effects)
    if not allowed then return nil,reason end
    local seen={}
    for _,scope in ipairs(operation.scopes) do
        if type(scope)~="string" or #scope>80 or seen[scope] then return nil,"invalid_handler" end
        seen[scope]=true
    end
    if not next(seen) then return nil,"invalid_handler" end
    return operation
end

function Authority:_execute(actorId,request,fingerprint)
    if request.sceneEpoch~=self.campaign.coop.sceneEpoch then return failure("stale_scene") end
    local draft,copyError=Schema.copy(self.campaign)
    if not draft then return failure(copyError) end
    if not Entities.ensure(draft) then return failure("invalid_campaign") end
    local transientBaseline=request.command=='progression.request' and copy(draft) or nil
    local now=self:sweepActivities()
    local activities={state=copy(self.activityState),now=now,generation=self.bindings[actorId],randomSeed=self.randomSeed,bindings=self.bindings}
    local transientActivities=transientBaseline and copy(activities.state) or nil
    local operation,reason=self:_prepare(actorId,request.command,request.args,draft,activities)
    if not operation then return failure(reason) end
    local expectedCount=0
    for scope,revision in pairs(request.expected) do
        if type(scope)~="string" or not integer(revision,0) then return failure("invalid_revisions") end
        expectedCount=expectedCount+1
    end
    if expectedCount~=#operation.scopes then return failure("invalid_revisions") end
    for _,scope in ipairs(operation.scopes) do
        local revision=self.campaign.coop.revisions[scope] or 0
        if request.expected[scope]~=revision then return failure("stale_revision") end
        if not operation.transientOnly and revision>=MAX_REVISION then return failure("revision_exhausted") end
    end
    if not operation.transientOnly and draft.coop.revision>=MAX_REVISION then return failure("revision_exhausted") end
    local result,applyError=operation.apply()
    if not result then return failure(applyError or "invalid_action") end
    if operation.transientOnly then
        if not same(draft,transientBaseline)then return failure('invalid_transient_mutation')end
        for key,value in pairs(transientActivities)do
            if key~='travelRequests' and not same(value,activities.state[key])then return failure('invalid_transient_mutation')end
        end
        for key in pairs(activities.state)do
            if key~='travelRequests' and transientActivities[key]==nil then return failure('invalid_transient_mutation')end
        end
        if not require('game.net.travel_request_results').valid(result)then return failure('invalid_public_result')end
        local response=copy({ok=true,result=result,revision=self.campaign.coop.revision,revisions={},
            durable=false,requestId=request.requestId})
        self.activityState=copy(activities.state)
        return response
    end
    local changed={}
    for _,scope in ipairs(operation.scopes) do
        local revision=(self.campaign.coop.revisions[scope] or 0)+1
        draft.coop.revisions[scope]=revision
        changed[scope]=revision
    end
    draft.coop.revision=self.campaign.coop.revision+1
    local response={ok=true,result=result,revision=draft.coop.revision,revisions=changed,durable=false,requestId=request.requestId}
    -- Validate result ownership/serializability before touching the live state.
    response=copy(response)
    local nextActivities=copy(activities.state)
    local critical=self.checkpoint and Receipts.required(request.command,request.args,operation)
    if critical then
        local savedResponse=copy(response); savedResponse.durable=true
        local added,message=Receipts.add(draft,actorId,self.sessionId,request,fingerprint,savedResponse)
        if not added then return failure(message) end
    end
    if not Entities.ensure(draft) or not Schema.validate(draft) then return failure("invalid_result") end
    commit(self.campaign,draft)
    self.activityState=nextActivities
    if critical then
        self.pendingSave={actorId=actorId,requestId=request.requestId,revision=response.revision}
        if self:retryCheckpoint() then response.durable=true else response.savePending=true end
    end
    return response
end

function Authority:execute(actorId,generation,request)
    if self.busy or self.saving then return failure("busy") end
    if self.sessionSerial and self.campaign.coop.checkpoints.sessionSerial~=self.sessionSerial then return failure("stale_authority") end
    if not Players.get(self.campaign,actorId) or self.bindings[actorId]==nil
        or self.bindings[actorId]~=generation then return failure("unbound_peer") end
    if type(request)~="table" or request.sessionId~=self.sessionId then return failure("wrong_session") end
    if not integer(request.requestId,1) or not integer(request.sceneEpoch,1)
        or type(request.command)~="string" or type(request.args)~="table" or type(request.expected)~="table" then
        return failure("invalid_request")
    end
    for key in pairs(request) do if not ENVELOPE[key] then return failure("invalid_request") end end
    local fingerprint=Codec.encode(request,LIMITS)
    if not fingerprint then return failure("invalid_request") end
    local history=self.requests[actorId]
    if not history then history={high=0,cache={},order={}}; self.requests[actorId]=history end
    local cached=history.cache[request.requestId]
    if cached then
        if cached.fingerprint~=fingerprint then return failure("request_conflict") end
        return copy(cached.response)
    end
    if self.pendingSave then return failure("save_pending") end
    if request.requestId<=history.high then return failure("expired_request") end
    self.busy=true
    local ok,response=pcall(self._execute,self,actorId,request,fingerprint)
    self.busy=false
    if not ok then response=failure("handler_error") end
    response.requestId=request.requestId
    history.high=request.requestId
    history.cache[request.requestId]={fingerprint=fingerprint,response=copy(response)}
    history.order[#history.order+1]=request.requestId
    if #history.order>self.cacheLimit then history.cache[table.remove(history.order,1)]=nil end
    return copy(response)
end

-- Local/offline host input uses the same envelope and dispatcher. Network
-- clients must keep the exact prepared envelope until its result is resolved.
function Authority:prepareRequest(actorId,name,args)
    if self.sessionSerial and self.campaign.coop.checkpoints.sessionSerial~=self.sessionSerial then return nil,"stale_authority" end
    if self.pendingSave then return nil,"save_pending" end
    local draft=assert(Schema.copy(self.campaign))
    assert(Entities.ensure(draft))
    local now=self:sweepActivities()
    local activities={state=copy(self.activityState),now=now,generation=self.bindings[actorId],randomSeed=self.randomSeed,bindings=self.bindings}
    local ok,operation,reason=pcall(self._prepare,self,actorId,name,args,draft,activities)
    if not ok then return nil,"handler_error" end
    if not operation then return nil,reason end
    local expected={}
    for _,scope in ipairs(operation.scopes) do expected[scope]=self.campaign.coop.revisions[scope] or 0 end
    return {sessionId=self.sessionId,requestId=(self.requests[actorId] and self.requests[actorId].high or 0)+1,
        sceneEpoch=self.campaign.coop.sceneEpoch,command=name,args=copy(args),expected=expected}
end

function Authority:submitLocal(name,args)
    local request,reason=self:prepareRequest(Players.HOST,name,args)
    if not request then return failure(reason) end
    return self:execute(Players.HOST,0,request)
end

return Authority
