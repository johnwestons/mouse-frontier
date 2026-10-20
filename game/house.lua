local House = {}
local Random = require("game.coop_random")
local Storage = require("game.house_storage")
local Furniture = require("game.furniture_catalog")
local LootProgression = require("game.loot_progression")
local HouseholdItems = require("game.household_items")
local CoopEntities = require("game.coop_entities")
local Items = require("game.item_instances")

local function ensureStorage(data,catalog,location,createLayout)
    data.stopLayouts=data.stopLayouts or {}; data.droppedItems=data.droppedItems or {}
    local key=tostring(location); local door=data.activeHouseDoor or 1
    local layout=data.stopLayouts[key] or {}
    -- Starting supplies and reward overflow can target an unvisited stop.
    -- Do not preempt Stops.ensure with a partial generated stop layout.
    if createLayout then data.stopLayouts[key]=layout end
    layout.interior=Storage.interior(layout.interior,location)
    local home=layout.houseDoors and layout.houseDoors[tostring(door)]
    if home then home.interior=Storage.interior(home.interior or layout.interior,location); layout.interior=home.interior end
    local containers={}
    for index=#data.droppedItems,1,-1 do
        local item=data.droppedItems[index]
        if item.scene=="house" and item.location==location and (item.houseDoor or 1)==door and not item.droppedByPlayer then
            if item.houseStorageHotspot or catalog.storageCapacities[item.name] then
                table.insert(containers,1,item)
            elseif item.generatedFurniture or Furniture.isFurniture(item.name) or item.name=="bedroll" then
                table.remove(data.droppedItems,index)
            end
        end
    end
    if #containers==0 then
        local item={scene="house",location=location,houseDoor=door,storage={}}
        data.droppedItems[#data.droppedItems+1]=item; containers[1]=item
    end
    for number,item in ipairs(containers) do Storage.place(item,layout.interior,location,number) end
    -- Existing containers keep their entity IDs, contents and gear identities.
    -- Multiple old fixtures become compartments of the same painted storage.
    return containers,layout
end

function House.lootDestination(data,catalog,location)
    location=math.max(1,location or 1)
    local houseDoor=data.activeHouseDoor or 1
    -- Co-op reward authorization uses this query before opening a transaction.
    -- Creation and legacy migration must happen in storeLoot/ensure instead.
    local containers={}
    for _,item in ipairs(data.droppedItems or {}) do
        if item.scene=="house" and item.location==location and (item.houseDoor or 1)==houseDoor
            and not item.droppedByPlayer and catalog.storageCapacities[item.name] then
            containers[#containers+1]=item
        end
    end
    local key=tostring(location); local start=(((data.lootContainerCursor or {})[key] or 0)%math.max(1,#containers))+1
    for step=0,#containers-1 do
        local index=((start+step-1)%#containers)+1; local item=containers[index]
        -- Predict the same slots that storeLoot will use after legacy fixtures
        -- are converted, without changing them during authorization.
        local capacity=catalog.storageCapacities["house-storage"]
        for slot=1,capacity do if not (item.storage or {})[slot] then return item,slot,index,#containers end end
    end
    return nil,1,nil,#containers
end

function House.storeLoot(data,catalog,name,location,instance)
    location=math.max(1,location or 1)
    local houseDoor=data.activeHouseDoor or 1
    local _,layout=ensureStorage(data,catalog,location)
    local container,slotIndex,cursor,count=House.lootDestination(data,catalog,location)
    data.lootContainerCursor=data.lootContainerCursor or {}
    if cursor then data.lootContainerCursor[tostring(location)]=cursor end
    if not container then
        container={scene="house",location=location,houseDoor=houseDoor,storage={}}
        Storage.place(container,layout.interior,location,count+1)
        data.droppedItems[#data.droppedItems+1]=container; slotIndex=1
    end
    container.storage=container.storage or {}
    Items.write(data,container,{kind="chest",index=slotIndex},name,instance)
    -- Generated/overflow containers need their live identity before any caller
    -- retains a reference, opens them, or copies the campaign for a save.
    assert(CoopEntities.ensure(data))
end

function House.rollLoot(data,catalog,location,rng)
    local random=Random.range(rng)
    data.lootRolls=data.lootRolls or {}; local key=tostring(location)..":"..tostring(data.activeHouseDoor or 1)
    local houseDoor=data.activeHouseDoor or 1
    local newHouse=not data.lootRolls[key]
    if not data.lootRolls[key] then
        House.storeLoot(data,catalog,LootProgression.rollSupply(catalog,"food",location,rng),location)
        House.storeLoot(data,catalog,LootProgression.rollSupply(catalog,"water",location,rng),location)
        local item=LootProgression.rollItem(catalog,location,{allowWeapon=false,rng=rng})
        if item then House.storeLoot(data,catalog,item,location) end
        -- A weapon marks a new route tier, rather than appearing in ordinary
        -- container rolls throughout every stop.
        if location>1 and (location-1)%6==0 and houseDoor==1 then
            local milestone=LootProgression.rollWeapon(catalog,location,"uncommon",rng)
            if milestone then House.storeLoot(data,catalog,milestone,location) end
        end
        data.lootRolls[key]=true
    end
    -- One household find adds variety without filling every container with
    -- several low-value curiosities.
    local householdKey="household:2:"..key
    if not data.lootRolls[householdKey] then
        local rarity=LootProgression.itemRarityAt(location,LootProgression.rollRarity(location,nil,rng))
        local item=HouseholdItems.roll(rarity,catalog.householdItemPools,rng)
        if item then House.storeLoot(data,catalog,item,location) end
        data.lootRolls[householdKey]=true
    end
    -- Only the first home at a stop can hold a repair part, and only when the
    -- player owns a critically damaged weapon that is missing its exact part.
    local repairKey="repair-parts:1:"..key
    if not data.lootRolls[repairKey] then
        if houseDoor==1 and random()<.30 then
            local part=LootProgression.rollRepairPart(data,catalog,location,rng,{targetedOnly=true})
            if part then House.storeLoot(data,catalog,part,location) end
        end
        data.lootRolls[repairKey]=true
    end
    -- New homes add one route-tier crafting material at the first house of a
    -- stop. Older visited homes keep the original one-time cache migration.
    local outfitKey="outfit-materials:1:"..key
    if not data.lootRolls[outfitKey] then
        if newHouse then
            if houseDoor==1 then
                local material=LootProgression.rollCraftMaterial(catalog,location,rng)
                if material then House.storeLoot(data,catalog,material,location) end
            end
        else
            for _,name in ipairs({"thread-spool","fabric-scraps"}) do
                if catalog.craftMaterials and catalog.craftMaterials[name] then House.storeLoot(data,catalog,name,location) end
            end
            local material=LootProgression.rollCraftMaterial(catalog,location,rng)
            if material then House.storeLoot(data,catalog,material,location) end
        end
        data.lootRolls[outfitKey]=true
    end
end

function House.ensure(data,catalog,isFurniture,rng)
    local location=data.location; local key=tostring(location)
    local houseDoor=data.activeHouseDoor or 1
    local doorKey=key..":"..tostring(houseDoor)
    ensureStorage(data,catalog,location,true)
    if not data.houseInitialized then data.houseInitialized={} end
    if not data.houseLayoutsArranged then data.houseLayoutsArranged={} end
    data.houseInitialized[doorKey]=true
    data.houseLayoutsArranged[doorKey]=true
    House.rollLoot(data,catalog,location,rng)
    assert(CoopEntities.ensure(data))
end

return House
