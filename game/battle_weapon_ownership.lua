local Items=require("game.item_instances")
local Entities=require("game.coop_entities")
local Actors=require('game.battle_actors')
local Weapons={}

function Weapons.resolve(data,unit,selector,catalog)
    data=Actors.data(data,unit)
    if selector=="scratch" then return {name="scratch",key="scratch",durability=100} end
    if not Items.identified(data) then
        if not catalog.weaponStats[selector] then return nil end
        return {name=selector,key=selector,durability=unit.team=="ally" and Items.condition(data,selector) or 100}
    end
    if unit.team=="enemy" then
        if selector~=unit.weapon or not catalog.weaponStats[selector] then return nil end
        return {name=selector,key=selector,durability=100}
    end
    if Actors.id(unit) then
        local entry=Items.selection(data,selector,catalog)
        if not entry or entry.ref.kind~="equipment" or entry.ref.index>2 then return nil end
        entry.instance=Items.get(data,nil,entry.ref)
        return entry
    end
    if unit.weaponOwnerId then
        local owner,descriptor=Entities.find(data,unit.weaponOwnerId)
        local instance=owner and owner.weaponInstance
        if not descriptor or descriptor.kind~="passenger" or not instance or instance.id~=unit.weaponItemId
            or (selector~=instance.id and selector~=instance.name) or owner.weapon~=instance.name then return nil end
        return {name=instance.name,key=instance.id,durability=instance.durability,instance=instance}
    end
    if unit.temporaryWeapon and selector==unit.weapon then
        return {name=unit.weapon,key=unit.weapon,durability=unit.weaponDurability or 100,temporary=unit}
    end
end

function Weapons.options(data,unit,catalog)
    data=Actors.data(data,unit)
    local result={"scratch"}
    if Actors.id(unit) then
        if Items.identified(data) then
            for index=1,2 do
                local record=Items.get(data,nil,{kind="equipment",index=index})
                if record then result[#result+1]=record.id end
            end
        else
            for index=1,2 do if data.equipment[index] then result[#result+1]=data.equipment[index] end end
        end
    elseif unit.weapon then result[#result+1]=unit.weaponItemId or unit.weapon end
    return result
end

function Weapons.wear(data,info,amount)
    if info.name=="scratch" then return end
    local after=math.max(0,info.durability-amount)
    if info.instance then info.instance.durability=after
    elseif info.temporary then info.temporary.weaponDurability=after
    else Items.setCondition(data,info.name,after) end
end

-- Old checkpoints identified passenger units by roster position. Rebind only
-- when the saved character and weapon identify one present passenger. Never
-- guess an item for an already-started player attack from its catalog name.
function Weapons.restore(data,battle,catalog)
    if not Items.enabled(data) then return false end
    local changed=false
    for _,unit in ipairs(battle.units or {}) do
        if unit.team=="ally" and not Actors.id(unit) and not unit.weaponOwnerId and not unit.temporaryWeapon then
            local owner,count=nil,0
            for _,passenger in ipairs(data.passengers or {}) do
                if passenger.npc==unit.file and passenger.weapon==unit.weapon and passenger.weaponInstance then
                    owner=passenger; count=count+1
                end
            end
            if count==1 then
                unit.weaponOwnerId=owner.entityId; unit.weaponItemId=owner.weaponInstance.id; changed=true
            else
                local index=tonumber(type(unit.id)=="string" and unit.id:match("^defender(%d+)$"))
                local allies=battle.encounter and battle.encounter.temporaryAllies
                if index and allies and allies[index]==unit.file then unit.temporaryWeapon=true; changed=true end
            end
        end
    end
    if battle.phase=="target" then
        local unit=battle.units[battle.active]
        local selector=battle.chosenItemId
        local info=selector and unit and Weapons.resolve(data,unit,selector,catalog)
        if not info or info.name~=battle.chosenWeapon then
            battle.chosenWeapon=nil; battle.chosenItemId=nil
            battle.phase=battle.moveUsed and "action" or "select"
            changed=true
        end
    end
    return changed
end

return Weapons
