local Inventory = {}

function Inventory.inventorySlotRect(index)
    local column,row=(index-1)%4,math.floor((index-1)/4)
    return {x=584+column*76,y=245+row*66,w=62,h=58}
end

function Inventory.equipmentSlotRect(index)
    return {x=620+(index-1)*130,y=545,w=96,h=70}
end

function Inventory.chestSlotRect(index)
    local column,row=(index-1)%5,math.floor((index-1)/5)
    return {x=55+column*92,y=235+row*92,w=76,h=72}
end

function Inventory.scrapPrice(name,catalog)
    local stats=catalog.weaponStats[name]
    if stats then return 3+(stats.tier or 1)*2 end
    if catalog.backpackUpgrades[name] then return math.floor(catalog.backpackUpgrades[name].capacity*1.5) end
    if catalog.itemEffects[name] then return 3 end
    return 2
end

function Inventory.firstEmptySlot(data)
    for index=1,(data.inventoryCapacity or 6) do
        if data.inventory[index]==nil then return index end
    end
end

function Inventory.isWeapon(name,weaponStats)
    return name and weaponStats[name]~=nil and name~="scratch"
end

function Inventory.value(data,activeChest,ref)
    if not ref then return nil end
    if ref.kind=="equipment" then return data.equipment[ref.index] end
    if ref.kind=="chest" then return activeChest and activeChest.storage[ref.index] end
    return data.inventory[ref.index]
end

function Inventory.setValue(data,activeChest,ref,value)
    if ref.kind=="equipment" then data.equipment[ref.index]=value
    elseif ref.kind=="chest" and activeChest then activeChest.storage[ref.index]=value
    else data.inventory[ref.index]=value end
end

function Inventory.move(data,activeChest,source,target,weaponStats,ammoPickupAmounts)
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
    if (target.kind=="equipment" and not Inventory.isWeapon(moving,weaponStats))
        or (source.kind=="equipment" and displaced and not Inventory.isWeapon(displaced,weaponStats)) then
        return false
    end
    Inventory.setValue(data,activeChest,target,moving)
    Inventory.setValue(data,activeChest,source,displaced)
    return true
end

function Inventory.quickTransfer(data,activeChest,ref,weaponStats,ammoPickupAmounts,storageCapacities)
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
                return Inventory.move(data,activeChest,ref,target,weaponStats,ammoPickupAmounts)
            end
        end
    elseif ref.kind=="chest" then
        for index=1,(data.inventoryCapacity or 6) do
            local target={kind="inventory",index=index}
            if not Inventory.value(data,activeChest,target) then
                return Inventory.move(data,activeChest,ref,target,weaponStats,ammoPickupAmounts)
            end
        end
    end
    return false
end

return Inventory
