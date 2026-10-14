local House = {}
local Random = require("game.coop_random")
local Compositions = require("game.furniture_compositions")
local LootProgression = require("game.loot_progression")
local HouseholdItems = require("game.household_items")
local CoopEntities = require("game.coop_entities")
local Items = require("game.item_instances")

local arrangements={
    {{300,350,1.35},{470,350,1.35},{735,365,1.35},{330,535,1.45},{700,530,1.5}},
    {{285,360,1.4},{500,350,1.3},{735,370,1.4},{355,530,1.5},{680,525,1.45}},
    {{300,355,1.35},{485,365,1.35},{720,355,1.35},{325,525,1.45},{705,525,1.5}},
    {{290,360,1.4},{470,350,1.35},{730,365,1.35},{350,525,1.45},{685,530,1.5}},
    {{300,355,1.35},{490,350,1.35},{725,360,1.4},{335,530,1.5},{700,525,1.45}}
}

local furnitureGroups={
    {"bookcase","medicine-cabinet","train-locker","pantry-cupboard","barrel-cabinet","railway-folding-screen","standing-dressing-mirror","wall-mounted-coat-hooks"},
    {"floor-lamp","potbelly-stove","side-table","rolltop-writing-desk","brass-washstand","round-pedestal-table","copper-plant-stand"},
    {"travel-chest","supply-crate","storage-bench","blue-steamer-trunk","quilting-frame"},
    {"armchair-green","rocking-chair","round-stool","patchwork-train-bench","patchwork-footstool","train-car-writing-chair"},
    {"single-bed","blue-sofa","patchwork-train-bench","wooden-cradle"}
}

local function furnitureBounds(item)
    local half=math.max(28,38*(item.scale or 1))
    return 145+half,815-half,350+half*.35,605-half*.20
end

local function arrange(items,isFurniture,location)
    local placed={}
    for _,item in ipairs(items or {}) do
        if item.scene=="house" and item.location==location and isFurniture(item.name) and not item.droppedByPlayer then
            local left,right,top,bottom=furnitureBounds(item)
            item.x=math.max(left,math.min(right,item.x or (left+right)/2)); item.y=math.max(top,math.min(bottom,item.y or (top+bottom)/2))
            local radius=math.max(30,42*(item.scale or 1))
            for _=1,12 do
                local overlap=false
                for _,other in ipairs(placed) do if math.abs(item.x-other.x)<radius+other.radius and math.abs(item.y-other.y)<radius+other.radius then overlap=true; break end end
                if not overlap then break end
                item.x=item.x+radius*1.25
                if item.x>right then item.x=left; item.y=math.min(bottom,item.y+radius*1.1) end
            end
            placed[#placed+1]={x=item.x,y=item.y,radius=radius}
        end
    end
end

function House.lootDestination(data,catalog,location)
    location=math.max(1,location or 1)
    local houseDoor=data.activeHouseDoor or 1
    local containers={}
    for _,item in ipairs(data.droppedItems or {}) do
        if item.scene=="house" and item.location==location and (item.houseDoor or 1)==houseDoor and catalog.storageCapacities[item.name] then containers[#containers+1]=item end
    end
    local key=tostring(location); local start=(((data.lootContainerCursor or {})[key] or 0)%math.max(1,#containers))+1
    for step=0,#containers-1 do
        local index=((start+step-1)%#containers)+1; local item=containers[index]; local capacity=catalog.storageCapacities[item.name]
        for slot=1,capacity do if not (item.storage or {})[slot] then return item,slot,index,#containers end end
    end
    return nil,1,nil,#containers
end

function House.storeLoot(data,catalog,name,location,instance)
    location=math.max(1,location or 1)
    local houseDoor=data.activeHouseDoor or 1
    local container,slotIndex,cursor,count=House.lootDestination(data,catalog,location)
    data.lootContainerCursor=data.lootContainerCursor or {}
    if cursor then data.lootContainerCursor[tostring(location)]=cursor end
    if not container then
        container={name="supply-crate",x=315+count*105,y=525,scene="house",location=location,houseDoor=houseDoor,scale=1.25,storage={},layer=50+count}
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
    local random=Random.range(rng)
    local location=data.location; local key=tostring(location); local layout=data.stopLayouts[key] or {}
    local houseDoor=data.activeHouseDoor or 1
    local doorKey=key..":"..tostring(houseDoor)
    layout.interior=layout.interior or random(1,5); data.stopLayouts[key]=layout
    local composition=Compositions.build(layout.interior)
    if not data.houseInitialized then data.houseInitialized={} end
    if not data.houseLayoutsArranged then data.houseLayoutsArranged={} end
    if not data.houseInitialized[doorKey] then
        for _,spot in ipairs(composition) do
            local name=spot.name
            local item={name=name,x=spot.x,y=spot.y,scene="house",location=location,houseDoor=houseDoor,scale=spot.scale,rotation=spot.rotation,generatedFurniture=true,layer=spot.layer}
            if catalog.storageCapacities[name] then item.storage={} end
            data.droppedItems[#data.droppedItems+1]=item
        end
        data.houseInitialized[doorKey]=true
    end
    if not data.houseLayoutsArranged[doorKey] then
        local index=1
        for _,item in ipairs(data.droppedItems) do
            if item.scene=="house" and item.location==location and (item.houseDoor or 1)==houseDoor and isFurniture(item.name) and not item.droppedByPlayer then
                local spot=composition[index]; if spot then item.x,item.y,item.scale,item.rotation,item.layer=spot.x,spot.y,spot.scale,spot.rotation,spot.layer; item.generatedFurniture=true; index=index+1 end
            end
        end
        data.houseLayoutsArranged[doorKey]=true
    end
    arrange(data.droppedItems,isFurniture,location)
    House.rollLoot(data,catalog,location,rng)
end

return House
