local LootProgression = require("game.loot_progression")
local Inventory = {}

function Inventory.inventorySlotRect(index)
    local column,row=(index-1)%4,math.floor((index-1)/4)
    return {x=584+column*76,y=230+row*56,w=62,h=52}
end

function Inventory.mobileInventorySlotRect(index)
    local column,row=(index-1)%4,math.floor((index-1)/4)
    return {x=575+column*82,y=230+row*78,w=76,h=68}
end

function Inventory.equipmentSlotRect(index)
    return {x=600+(index-1)*160,y=496,w=128,h=58}
end

function Inventory.mobileEquipmentSlotRect(index)
    return {x=580+(index-1)*170,y=490,w=150,h=70}
end

function Inventory.wearableSlotRect(index)
    return {x=560+(index-1)*120,y=92,w=110,h=68}
end

function Inventory.chestSlotRect(index)
    local column,row=(index-1)%5,math.floor((index-1)/5)
    return {x=55+column*92,y=235+row*92,w=76,h=72}
end

function Inventory.scrapPrice(name,catalog)
    return LootProgression.itemPrice(catalog,name)
end

function Inventory.resalePrice(name,catalog,data)
    local durability=data and data.weaponDurability and data.weaponDurability[name]
    return LootProgression.resalePrice(catalog,name,durability)
end

function Inventory.firstEmptySlot(data)
    for index=1,(data.inventoryCapacity or 6) do
        if data.inventory[index]==nil then return index end
    end
end

function Inventory.isWeapon(name,weaponStats)
    return name and weaponStats[name]~=nil and name~="scratch"
end

local function backpackCapacity(name,wearableItems,fallback)
    local profile=name and wearableItems and wearableItems[name]
    if profile and profile.slot=="backpack" then return math.max(1,math.floor(tonumber(profile.capacity) or 6)) end
    if not name then return 6 end
    return math.max(1,math.floor(tonumber(fallback) or 6))
end

function Inventory.canChangeBackpack(data,name,wearableItems,source,target,moving,displaced)
    local capacity=backpackCapacity(name,wearableItems,data.inventoryCapacity)
    for index,item in pairs(data.inventory or {}) do
        if type(index)=="number" and index>capacity then
            if source and source.kind=="inventory" and source.index==index then item=displaced end
            if target and target.kind=="inventory" and target.index==index then item=moving end
            if item~=nil then return false,capacity end
        end
    end
    local function checkSlot(ref)
        if ref and ref.kind=="inventory" and type(ref.index)=="number" and ref.index>capacity then
            local item=data.inventory[ref.index]
            if source and source.kind=="inventory" and source.index==ref.index then item=displaced end
            if target and target.kind=="inventory" and target.index==ref.index then item=moving end
            if item~=nil then return false,capacity end
        end
        return true
    end
    local sourceOk=checkSlot(source); if not sourceOk then return false,capacity end
    local targetOk=checkSlot(target); if not targetOk then return false,capacity end
    return true,capacity
end

local function syncBackpack(data,wearableItems)
    local name=data.wearables and data.wearables.backpack
    data.backpack=name
    data.inventoryCapacity=backpackCapacity(name,wearableItems,data.inventoryCapacity)
end

local function accepts(ref,item,weaponStats,wearableItems)
    if not item then return true end
    if ref.kind=="equipment" then return Inventory.isWeapon(item,weaponStats) end
    if ref.kind=="wearable" then
        local profile=wearableItems and wearableItems[item]
        return profile~=nil and profile.slot==ref.slot
    end
    return true
end

function Inventory.value(data,activeChest,ref)
    if not ref then return nil end
    if ref.kind=="equipment" then return data.equipment[ref.index] end
    if ref.kind=="wearable" then return data.wearables and data.wearables[ref.slot] end
    if ref.kind=="chest" then return activeChest and activeChest.storage[ref.index] end
    return data.inventory[ref.index]
end

function Inventory.setValue(data,activeChest,ref,value,wearableItems)
    if ref.kind=="equipment" then data.equipment[ref.index]=value
    elseif ref.kind=="wearable" then
        data.wearables=data.wearables or {}
        data.wearables[ref.slot]=value
        if ref.slot=="backpack" then syncBackpack(data,wearableItems) end
    elseif ref.kind=="chest" and activeChest then activeChest.storage[ref.index]=value
    else data.inventory[ref.index]=value end
end

function Inventory.move(data,activeChest,source,target,weaponStats,ammoPickupAmounts,wearableItems)
    if not source or not target then return false end
    -- Reward mailboxes are a one-way delivery channel: the player may take
    -- rewards out, but cannot put backpack items into them.
    if activeChest and activeChest.mailbox and target.kind=="chest" then return false end
    local moving=Inventory.value(data,activeChest,source)
    local displaced=Inventory.value(data,activeChest,target)
    if not moving then return false end
    if source.kind=="chest" and target.kind=="inventory" and ammoPickupAmounts[moving] and not displaced then
        data.ammo[moving]=(data.ammo[moving] or 0)+ammoPickupAmounts[moving]
        Inventory.setValue(data,activeChest,source,nil)
        return true
    end
    if not accepts(target,moving,weaponStats,wearableItems) or not accepts(source,displaced,weaponStats,wearableItems) then return false end
    local nextBackpack=data.wearables and data.wearables.backpack
    if source.kind=="wearable" and source.slot=="backpack" then nextBackpack=displaced end
    if target.kind=="wearable" and target.slot=="backpack" then nextBackpack=moving end
    local capacity=backpackCapacity(nextBackpack,wearableItems,data.inventoryCapacity)
    local relocationIndex
    if source.kind=="inventory" and target.kind=="wearable" and target.slot=="backpack"
        and source.index>capacity and displaced then
        for index=1,capacity do
            if data.inventory[index]==nil then relocationIndex=index; break end
        end
        if not relocationIndex then return false,"Free a backpack slot within the new capacity before changing wearables." end
    end
    local capacityDisplaced=displaced
    if relocationIndex then capacityDisplaced=nil end
    local capacityOk=Inventory.canChangeBackpack(data,nextBackpack,wearableItems,source,target,moving,capacityDisplaced)
    if not capacityOk then return false,"Free a backpack slot within the new capacity before changing wearables." end
    Inventory.setValue(data,activeChest,target,moving,wearableItems)
    if relocationIndex then
        Inventory.setValue(data,activeChest,source,nil,wearableItems)
        Inventory.setValue(data,activeChest,{kind="inventory",index=relocationIndex},displaced,wearableItems)
    else Inventory.setValue(data,activeChest,source,displaced,wearableItems) end
    if source.kind=="wearable" or target.kind=="wearable" then syncBackpack(data,wearableItems) end
    return true
end

function Inventory.quickTransfer(data,activeChest,ref,weaponStats,ammoPickupAmounts,storageCapacities,wearableItems)
    if not ref or not Inventory.value(data,activeChest,ref) or not activeChest then return false end
    if activeChest.mailbox and ref.kind=="inventory" then return false end
    local moving=Inventory.value(data,activeChest,ref)
    if ref.kind=="chest" and ammoPickupAmounts[moving] then
        data.ammo[moving]=(data.ammo[moving] or 0)+ammoPickupAmounts[moving]
        Inventory.setValue(data,activeChest,ref,nil)
        return true
    end
    if ref.kind=="inventory" then
        for index=1,(storageCapacities[activeChest.name] or 10) do
            local target={kind="chest",index=index}
            if not Inventory.value(data,activeChest,target) then
                return Inventory.move(data,activeChest,ref,target,weaponStats,ammoPickupAmounts,wearableItems)
            end
        end
    elseif ref.kind=="chest" then
        for index=1,(data.inventoryCapacity or 6) do
            local target={kind="inventory",index=index}
            if not Inventory.value(data,activeChest,target) then
                return Inventory.move(data,activeChest,ref,target,weaponStats,ammoPickupAmounts,wearableItems)
            end
        end
    elseif ref.kind=="wearable" then
        for index=1,(storageCapacities[activeChest.name] or 10) do
            local target={kind="chest",index=index}
            if not Inventory.value(data,activeChest,target) then
                return Inventory.move(data,activeChest,ref,target,weaponStats,ammoPickupAmounts,wearableItems)
            end
        end
    end
    return false
end

return Inventory
