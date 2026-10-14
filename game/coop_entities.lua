-- Campaign-local identities survive array compaction and save/reload. Names,
-- coordinates and array offsets are never network identities.
local Entities={}
local Random=require("game.coop_random")
local Receipts=require("game.coop_receipts")
local Party=require("game.party_scene")
local Identity=require("game.net.identity")
local MAX_ID=2147483647

local function integer(value,minimum)
    return type(value)=="number" and value==math.floor(value) and value>=minimum and value<=MAX_ID
end

local function sortedKeys(values)
    local keys={}
    if type(values)~="table" then return keys end
    for key in pairs(values) do keys[#keys+1]=key end
    table.sort(keys,function(a,b)
        if type(a)==type(b) then
            if type(a)=="number" or type(a)=="string" then return a<b end
            return tostring(a)<tostring(b)
        end
        return type(a)<type(b)
    end)
    return keys
end

-- Explicit domains only: arbitrary tables (inventory slots, dialogue answers,
-- authored definitions) must not accidentally become mutable world entities.
function Entities.records(data)
    local result={}
    local function add(value,kind,parent,key,areaId)
        if type(value)=="table" then
            result[#result+1]={value=value,kind=kind,parent=parent,key=key,areaId=areaId}
        end
    end
    local function collection(values,kind,areaId)
        for _,key in ipairs(sortedKeys(values)) do add(values[key],kind,values,key,areaId) end
    end
    collection(data.droppedItems,"drop")
    collection(data.passengers,"passenger")
    collection(data.stopLayouts,"stop")
    for _,key in ipairs(sortedKeys(data.stopLayouts)) do
        local layout=data.stopLayouts[key]
        if type(layout)=='table' then add(layout.shootingRange,'rangeSpot',layout,'shootingRange') end
    end
    if type(data.rangeSessions)=='table' then
        for _,id in ipairs({'host','companion'}) do
            local session=data.rangeSessions[id]
            if type(session)=='table' then
                add(session,'rangeSession',data.rangeSessions,id)
                collection(session.targets,'rangeTarget')
            end
        end
    end
    collection(data.supplyQuests,"supplyQuest")
    collection(data.mailQuests,"mailQuest")
    collection(data.encounters,"encounter")
    if type(data.trainAmbush)=='table' and data.trainAmbush.defendersVersion~=nil then
        add(data.trainAmbush,'trainAmbush',data,'trainAmbush')
    end
    if type(data.lastStand)=='table' and type(data.lastStand.combat)=='table' and data.lastStand.combat.version~=nil then
        add(data.lastStand.combat,'lastStandCombat',data.lastStand,'combat')
    end
    if type(data.lastStand)=='table' and type(data.lastStand.lifecycle)=='table' and data.lastStand.lifecycle.version~=nil then
        add(data.lastStand.lifecycle,'lastStandLifecycle',data.lastStand,'lifecycle')
    end
    local areas=data.expeditions
    for _,areaId in ipairs(sortedKeys(areas)) do
        local area=areas[areaId]
        if type(area)=="table" then
            add(area,"area",areas,areaId,areaId)
            collection(area.chests,"expeditionChest",areaId)
            collection(area.mobs,"expeditionMob",areaId)
        end
    end
    collection(type(data.crowCaravans)=="table" and data.crowCaravans.camps,"caravan")
    return result
end

function Entities.validate(data,allowMissing)
    local state=data.coop
    if state~=nil then
        if type(state)~="table" or state.version~=1 or not integer(state.nextEntityId,1)
            or not integer(state.revision,0) or not integer(state.sceneEpoch,1)
            or type(state.revisions)~="table" then return false,"invalid co-op metadata" end
        if state.randomState~=nil and not Random.valid(state.randomState) then return false,"invalid co-op random state" end
        if state.preferencesDetached~=nil and type(state.preferencesDetached)~="boolean" then return false,"invalid preference ownership" end
        local receiptsValid,receiptsError=Receipts.validate(data)
        if not receiptsValid then return false,receiptsError end
        local partyValid,partyError=Party.validate(data)
        if not partyValid then return false,partyError end
        local identityValid,identityError=Identity.validate(data)
        if not identityValid then return false,identityError end
        for key,value in pairs(state.revisions) do
            if type(key)~="string" or #key>80 or not integer(value,0) then return false,"invalid co-op revision" end
        end
    elseif not allowMissing then return false,"missing co-op metadata" end
    local seen,objects={},{}
    for _,record in ipairs(Entities.records(data)) do
        if objects[record.value] then return false,"duplicate entity reference" end
        objects[record.value]=true
        local id=record.value.entityId
        if id~=nil then
            local number=type(id)=="string" and tonumber(id:match("^e([1-9]%d*)$"))
            if not number or not integer(number,1) or id~="e"..string.format("%.0f",number) then return false,"invalid entity ID" end
            if seen[id] then return false,"duplicate entity ID: "..id end
            if state and number>=state.nextEntityId then return false,"entity sequence regressed" end
            seen[id]=true
        elseif not allowMissing then return false,"missing entity ID" end
    end
    return true
end

function Entities.ensure(data)
    local valid,reason=Entities.validate(data,true)
    if not valid then return nil,reason end
    local records=Entities.records(data)
    local nextId=data.coop and data.coop.nextEntityId or 1
    local missing=0
    for _,record in ipairs(records) do
        if record.value.entityId then nextId=math.max(nextId,tonumber(record.value.entityId:sub(2))+1)
        else missing=missing+1 end
    end
    if nextId+missing>MAX_ID then return nil,"entity IDs exhausted" end
    data.coop=data.coop or {version=1,revision=0,sceneEpoch=1,revisions={}}
    for _,record in ipairs(records) do
        if not record.value.entityId then
            record.value.entityId="e"..string.format("%.0f",nextId)
            nextId=nextId+1
        end
    end
    data.coop.nextEntityId=nextId
    return data
end

function Entities.find(data,id)
    if type(id)~="string" then return nil end
    for _,record in ipairs(Entities.records(data)) do
        if record.value.entityId==id then return record.value,record end
    end
end

return Entities
