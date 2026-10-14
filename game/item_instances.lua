-- Names remain catalog/UI keys. A movable piece of gear has one separate
-- persistent record, carried with it rather than recreated on its new owner.
-- Every loaded/new campaign uses the ledger. Plain pre-migration domain data
-- retains legacy behavior until SaveSchema establishes canonical ownership.
local Items={}
local Catalog=require("game.catalog")
local Entities=require("game.coop_entities")
local MAX_ID=2147483647

local function integer(n,minimum)
    return type(n)=="number" and n==math.floor(n) and n>=minimum and n<=MAX_ID
end

local function keys(t)
    local result={}
    for key in pairs(t or {}) do result[#result+1]=key end
    table.sort(result,function(a,b)
        if type(a)==type(b) then return a<b end
        return type(a)<type(b)
    end)
    return result
end

function Items.isGear(name)
    return type(name)=="string" and ((Catalog.weaponStats[name]~=nil and name~="scratch"
        and not name:find("mob%-")) or Catalog.wearableItems[name]~=nil)
end

local function weapon(name) return Catalog.weaponStats[name]~=nil end

local function slot(data,chest,ref,create)
    local owner=ref.kind=="chest" and chest or data
    if not owner then return nil end
    local field=ref.kind=="chest" and "storageInstances" or "itemSlots"
    if create then owner[field]=owner[field] or {} end
    local map=owner[field]
    if ref.kind~="chest" and map then
        if create then map[ref.kind]=map[ref.kind] or {} end
        map=map[ref.kind]
    end
    local names=ref.kind=="chest" and owner.storage or ref.kind=="wearable" and owner.wearables
        or ref.kind=="equipment" and owner.equipment or owner.inventory
    return map,ref.slot or ref.index,names
end

function Items.enabled(data) return data and data.itemIdentity~=nil end
-- Replicas carry owned instances but deliberately omit the host's allocation
-- counter. Read-only selectors must still distinguish duplicate guest gear.
function Items.identified(data) return Items.enabled(data) or data and type(data.itemSlots)=='table' end

function Items.create(data,name,durability)
    if not Items.enabled(data) or not Items.isGear(name) then return nil end
    local ledger=data.itemIdentity
    assert(ledger.version==1 and integer(ledger.nextId,1) and ledger.nextId<MAX_ID,"item IDs exhausted or invalid")
    local record={id="i"..string.format("%.0f",ledger.nextId),name=name}
    if weapon(name) then
        record.durability=durability==nil and 100 or durability
        assert(integer(record.durability,0) and record.durability<=100,"invalid weapon condition")
    end
    ledger.nextId=ledger.nextId+1
    return record
end

function Items.get(data,chest,ref)
    local map,key,names=slot(data,chest,ref,false)
    local record=map and map[key]
    return record and names and names[key]==record.name and record or nil
end

-- Called alongside a slot write. An absent record means a newly created item,
-- never a request to recover an old item by its catalog name.
function Items.assign(data,chest,ref,name,record)
    if not Items.enabled(data) then return end
    local map,key=slot(data,chest,ref,true)
    assert(map and key,"invalid item slot")
    if record then assert(Items.isGear(name) and record.name==name,"item does not match slot") end
    map[key]=record or Items.create(data,name)
end

function Items.take(data,chest,ref)
    local map,key=slot(data,chest,ref,false)
    local record=Items.get(data,chest,ref)
    if map then map[key]=nil end
    return record
end

-- Creation/destruction writers use this alongside transfer-aware Inventory.
-- An omitted instance creates fresh gear even when replacing the same name.
function Items.write(data,chest,ref,name,instance)
    Items.assign(data,chest,ref,name,instance)
    local owner=ref.kind=="chest" and chest or data
    local field=ref.kind=="chest" and "storage" or ref.kind=="wearable" and "wearables" or ref.kind
    owner[field]=owner[field] or {}
    owner[field][ref.slot or ref.index]=name
end

-- Ordered selection preserves old callers which select a weapon by name.
-- New actor commands and UI selectors should pass an exact ref or item ID.
function Items.owned(data,nameOrId,ref)
    if ref then
        local record=Items.get(data,nil,ref)
        return record and (record.name==nameOrId or record.id==nameOrId) and record or nil
    end
    for _,kind in ipairs({"equipment","inventory"}) do
        local values=data[kind] or {}
        for _,index in ipairs(keys(values)) do
            local record=Items.get(data,nil,{kind=kind,index=index})
            if record and (record.name==nameOrId or record.id==nameOrId) then return record end
        end
    end
end

function Items.condition(data,nameOrId,ref)
    if not data then return 100 end
    if nameOrId=="scratch" then return 100 end
    local record=Items.owned(data,nameOrId,ref)
    if record then return record.durability or 100 end
    if Items.enabled(data) then return 0 end
    return data.weaponDurability and data.weaponDurability[nameOrId] or 100
end

-- Stable selectors distinguish duplicate weapons. The catalog name is only
-- presentation/rules data; sessions retain key so a replacement cannot take
-- over an in-progress repair or a loaded weapon session.
function Items.weapons(data,catalog)
    local result,seen={},{}
    for _,kind in ipairs({"equipment","inventory"}) do
        for _,index in ipairs(keys(data[kind])) do
            local name=data[kind][index]
            if Items.isGear(name) and catalog.weaponStats[name] then
                local ref={kind=kind,index=index}
                local record=Items.get(data,nil,ref)
                if (Items.identified(data) and record) or (not Items.identified(data) and not seen[name]) then
                    seen[name]=true
                    result[#result+1]={name=name,key=record and record.id or name,id=record and record.id,
                        ref=ref,durability=Items.condition(data,name,ref)}
                end
            end
        end
    end
    return result
end

function Items.selection(data,selector,catalog)
    for _,entry in ipairs(Items.weapons(data,catalog)) do
        if entry.key==selector then return entry end
    end
end

function Items.setCondition(data,nameOrId,value,ref)
    assert(integer(value,0) and value<=100,"invalid weapon condition")
    local record=Items.owned(data,nameOrId,ref)
    if record and record.durability~=nil then record.durability=value; return true end
    if Items.enabled(data) then return false end
    data.weaponDurability=data.weaponDurability or {}
    data.weaponDurability[nameOrId]=value
    return true
end

-- A single traversal defines ownership and validates uniqueness. Records live
-- at their owner; there is no second registry copy that can drift out of sync.
function Items.slots(data)
    local result={}
    local function add(owner,field,key,name,legacy)
        result[#result+1]={owner=owner,field=field,key=key,name=name,legacy=legacy}
    end
    local function collection(owner,field,names,legacy)
        local all={}
        for k in pairs(names or {}) do all[k]=true end
        for k in pairs(owner[field] or {}) do all[k]=true end
        for _,k in ipairs(keys(all)) do add(owner,field,k,names and names[k],legacy) end
    end
    for _,id in ipairs(keys(data.players)) do
        local actor=data.players[id]
        for kind in pairs(actor.itemSlots or {}) do
            assert(kind=="inventory" or kind=="equipment" or kind=="wearable","invalid item slot kind")
        end
        -- Descriptors can represent missing maps without modifying the input.
        for _,kind in ipairs({"equipment","inventory","wearable"}) do
            local names=kind=="wearable" and actor.wearables or actor[kind]
            local maps=actor.itemSlots or {}
            collection(maps,kind,names,actor.weaponDurability)
            for index=#result,1,-1 do
                local entry=result[index]
                if entry.owner~=maps then break end
                entry.actor=actor
            end
        end
    end
    for _,entry in ipairs(Entities.records(data)) do
        local object=entry.value
        if entry.kind=="drop" then
            add(object,"itemInstance",nil,object.name)
            collection(object,"storageInstances",object.storage)
        elseif entry.kind=="expeditionChest" then collection(object,"storageInstances",object.storage)
        elseif entry.kind=="passenger" then add(object,"weaponInstance",nil,object.weapon)
        elseif entry.kind=="stop" then add(object,"npcWeaponInstance",nil,object.npcWeapon)
        elseif entry.kind=="caravan" then
            local function listings(list)
                for _,listing in ipairs(list or {}) do
                    for _,index in ipairs(keys(listing.instances)) do
                        add(listing,"instances",index,listing.item)
                        result[#result].listing=listing
                    end
                end
            end
            for _,merchant in ipairs(object.merchants or {}) do listings(merchant.listings) end
            listings(object.resaleStock)
        end
    end
    return result
end

local function value(entry)
    if entry.key~=nil then return entry.owner[entry.field] and entry.owner[entry.field][entry.key] end
    return entry.owner[entry.field]
end

local function validate(data,allowMissing)
    local ledger=data.itemIdentity
    if ledger==nil then
        if not allowMissing then return false,"missing item ledger" end
        for _,entry in ipairs(Items.slots(data)) do
            if value(entry)~=nil then return false,"item identity without ledger" end
        end
        return true
    end
    if type(ledger)~="table" or ledger.version~=1 or not integer(ledger.nextId,1) then return false,"invalid item ledger" end
    local seen={}
    for _,entry in ipairs(Items.slots(data)) do
        local record=value(entry)
        if record~=nil then
            if type(record)~="table" or not Items.isGear(entry.name) or record.name~=entry.name then return false,"item does not match owner" end
            for key in pairs(record) do
                if key~="id" and key~="name" and key~="durability" then return false,"invalid item record field" end
            end
            if entry.key~=nil then
                if entry.field=="wearable" then
                    local profile=Catalog.wearableItems[entry.name]
                    if not profile or profile.slot~=entry.key then return false,"invalid wearable owner slot" end
                elseif not integer(entry.key,1) then return false,"invalid item owner slot" end
            end
            local id=type(record.id)=="string" and tonumber(record.id:match("^i([1-9]%d*)$"))
            if not integer(id,1) or record.id~="i"..string.format("%.0f",id) or id>=ledger.nextId then return false,"invalid item identity" end
            if seen[record.id] then return false,"duplicate item identity: "..record.id end
            seen[record.id]=true
            if weapon(record.name) then
                if not integer(record.durability,0) or record.durability>100 then return false,"invalid weapon condition" end
            elseif record.durability~=nil then return false,"condition on non-weapon item" end
            if entry.listing and (not integer(entry.key,1) or not integer(entry.listing.quantity,0)
                or entry.key>entry.listing.quantity) then return false,"invalid resale item quantity" end
            if entry.listing then
                for index=1,entry.key do
                    if entry.listing.instances[index]==nil then return false,"sparse resale item queue" end
                end
            end
        elseif Items.isGear(entry.name) and not allowMissing then return false,"missing item identity" end
    end
    return true
end

function Items.validate(data,allowMissing)
    local ok,valid,reason=pcall(validate,data,allowMissing)
    if not ok then return false,"invalid item ownership tables" end
    return valid,reason
end

-- One-time migration is explicit. Already-enabled saves may gain newly spawned
-- gear, but an existing damaged/mismatched/duplicated record is never repaired
-- or discarded silently. Counter exhaustion is checked before any writes.
function Items.ensure(data)
    local legacy=data.itemIdentity==nil
    local valid,reason=Items.validate(data,true)
    if not valid then return nil,reason end
    local entries=Items.slots(data)
    local count=0
    for _,entry in ipairs(entries) do if Items.isGear(entry.name) and not value(entry) then count=count+1 end end
    local nextId=legacy and 1 or data.itemIdentity.nextId
    if nextId+count>MAX_ID then return nil,"item IDs exhausted" end
    data.itemIdentity=data.itemIdentity or {version=1,nextId=1}
    for _,entry in ipairs(entries) do
        if Items.isGear(entry.name) and not value(entry) then
            local condition=legacy and entry.legacy and entry.legacy[entry.name] or nil
            if condition~=nil then condition=math.max(0,math.min(100,math.floor(tonumber(condition) or 100))) end
            local record=Items.create(data,entry.name,condition)
            if entry.actor then
                entry.actor.itemSlots=entry.actor.itemSlots or {}
                entry.owner=entry.actor.itemSlots
            end
            if entry.key~=nil then
                entry.owner[entry.field]=entry.owner[entry.field] or {}
                entry.owner[entry.field][entry.key]=record
            else entry.owner[entry.field]=record end
        end
    end
    return data
end

return Items
