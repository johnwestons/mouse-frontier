-- Checkpointed outcomes are distinct from the transient request cache. A new
-- authority session never executes a previous session's request again.
local Codec=require("game.net.codec")
local Capabilities=require("game.coop_capabilities")
local Receipts={MAX_COUNT=64,MAX_BYTES=262144,MAX_SEQUENCE=2147483647}
local LIMITS={maxBytes=16384,maxDepth=16,maxEntries=1024,maxStringBytes=1200}
local fields={actorId=true,sessionId=true,sessionSerial=true,requestId=true,fingerprint=true,response=true}
local critical={}
for name in ("inventory.swap inventory.consume inventory.give ammo.give storage.transfer loot.pickup loot.drop mailbox.collect train.fuel train.upgrade train.engineUpgrade "
    .."merchant.buy merchant.sell npc.gift passenger.equip firstAid.complete maintenance.complete weaponRepair.complete "
    .."quest.deliver quest.help decoration.collect expedition.cache npc.chatter passenger.chatter"):gmatch("%S+") do critical[name]=true end

local function integer(value,minimum)
    return type(value)=="number" and value==math.floor(value) and value>=minimum and value<=Receipts.MAX_SEQUENCE
end

function Receipts.required(command,args,operation)
    local policy=Capabilities.commands[command] and Capabilities.commands[command].policy
    local effects=operation.effects or {}
    return critical[command]==true or policy=="host_progression" or policy=="host_admin"
        or effects.story==true or effects.scene==true or effects.localScene==true or effects.ending==true
        or command=="outfit.craft" and (args.action=="start" or args.action=="collect")
        or command=='radio.station' or command=='decoration.place' and next(args.values or {})~=nil
        or operation.checkpoint==true
end

local function encoded(entry,state)
    if type(entry)~="table" then return nil end
    for key in pairs(entry) do if not fields[key] then return nil end end
    if entry.actorId~="host" and entry.actorId~="companion" then return nil end
    if type(entry.sessionId)~="string" or #entry.sessionId<1 or #entry.sessionId>64
        or not integer(entry.sessionSerial,1) or entry.sessionSerial>state.sessionSerial
        or not integer(entry.requestId,1) or type(entry.fingerprint)~="string" or #entry.fingerprint>1200 then return nil end
    local request=Codec.decode(entry.fingerprint,{maxBytes=1200,maxDepth=8,maxEntries=80,maxStringBytes=128})
    if not request or request.sessionId~=entry.sessionId or request.requestId~=entry.requestId
        or not integer(request.sceneEpoch,1) or type(request.args)~="table" or type(request.expected)~="table"
        or not Capabilities.authorize(request.command,entry.actorId=="host" and "host" or "guest") then return nil end
    for key in pairs(request) do
        if key~="sessionId" and key~="requestId" and key~="command" and key~="sceneEpoch" and key~="args" and key~="expected" then return nil end
    end
    local response=entry.response
    if type(response)~="table" or response.ok~=true or response.durable~=true
        or response.requestId~=entry.requestId or not integer(response.revision,1)
        or type(response.revisions)~="table" or type(response.result)~="table" then return nil end
    for key in pairs(response) do
        if key~="ok" and key~="durable" and key~="requestId" and key~="revision" and key~="revisions" and key~="result" then return nil end
    end
    for scope,revision in pairs(response.revisions) do
        if type(scope)~="string" or #scope>80 or not integer(revision,1) or revision>response.revision then return nil end
        if request.expected[scope]~=revision-1 then return nil end
    end
    for scope in pairs(request.expected) do if response.revisions[scope]==nil then return nil end end
    return Codec.encode(entry,LIMITS)
end

function Receipts.validate(data)
    local state=data.coop and data.coop.checkpoints
    if state==nil then return true end
    if type(state)~="table" or state.version~=1 or not integer(state.sessionSerial,1)
        or type(state.receipts)~="table" then return false,"invalid checkpoint metadata" end
    for key in pairs(state) do
        if key~="version" and key~="sessionSerial" and key~="receipts" then return false,"invalid checkpoint metadata" end
    end
    local count,bytes,seen=0,0,{}
    for key,entry in pairs(state.receipts) do
        if not integer(key,1) or key>Receipts.MAX_COUNT then return false,"invalid receipt index" end
        local text=encoded(entry,state)
        if not text or entry.response.revision>data.coop.revision then return false,"invalid checkpoint receipt" end
        local identity=entry.actorId.."|"..entry.sessionId.."|"..entry.requestId
        if seen[identity] then return false,"duplicate checkpoint receipt" end
        seen[identity]=true; count=count+1; bytes=bytes+#text
    end
    if count~=#state.receipts or bytes>Receipts.MAX_BYTES then return false,"checkpoint receipt limit" end
    for index=1,count do if state.receipts[index]==nil then return false,"sparse checkpoint receipts" end end
    return true
end

function Receipts.beginSession(data)
    local state=data.coop.checkpoints
    local previous=state and state.sessionSerial or 0
    if previous>=Receipts.MAX_SEQUENCE then return nil,"session_sequence_exhausted" end
    if not state then state={version=1,sessionSerial=0,receipts={}}; data.coop.checkpoints=state end
    state.sessionSerial=previous+1
    return state.sessionSerial
end

function Receipts.add(data,actorId,sessionId,request,fingerprint,response)
    local state=data.coop.checkpoints
    local entry={actorId=actorId,sessionId=sessionId,sessionSerial=state.sessionSerial,
        requestId=request.requestId,fingerprint=fingerprint,response=response}
    local text=encoded(entry,state)
    if not text then return false,"invalid_receipt" end
    -- Decode our bounded data encoding to detach the receipt from UI results.
    state.receipts[#state.receipts+1]=assert(Codec.decode(text,LIMITS))
    local bytes=0
    for _,value in ipairs(state.receipts) do bytes=bytes+#assert(encoded(value,state)) end
    while #state.receipts>Receipts.MAX_COUNT or bytes>Receipts.MAX_BYTES do
        bytes=bytes-#assert(encoded(table.remove(state.receipts,1),state))
    end
    return true
end

function Receipts.find(data,actorId,sessionId,requestId)
    local state=data.coop.checkpoints
    for _,entry in ipairs(state and state.receipts or {}) do
        if entry.actorId==actorId and entry.sessionId==sessionId and entry.requestId==requestId then return entry end
    end
end

return Receipts
