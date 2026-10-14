-- Shared offline/authoritative rules. The caller supplies an actor-scoped data
-- view; train supplies remain shared while health and potions stay personal.
local Consumables={}
local Items=require("game.item_instances")

function Consumables.use(data,catalog,balance,name)
    if name=="rose-heart-arrow" or name=="blade-hearts" then
        data.maxHealth=data.maxHealth+5
        data.health=math.min(data.maxHealth,data.health+5)
        return {ok=true,item=name,heart=true}
    end
    local effect=catalog.itemEffects[name]
    if not effect then return {ok=false,reason="not_consumable"} end
    if effect.potion then
        data.nextBattlePotions[name]=true
        return {ok=true,item=name,potion=true}
    end
    local full,hasSupply,hasSpace={},false,false
    for _,resource in ipairs({"food","water","oil"}) do
        if effect[resource] then
            hasSupply=true
            full[resource]=data.resources[resource]>=balance.resourceCapacity(data,resource)
            if not full[resource] then hasSpace=true end
        end
    end
    if hasSupply and not hasSpace then return {ok=false,reason="storage_full",full=full} end
    local gained={}
    for _,resource in ipairs({"food","water","oil"}) do
        if effect[resource] then gained[resource]=balance.addResource(data,resource,effect[resource]) end
    end
    if effect.health then
        local previous=data.health
        data.health=math.min(data.maxHealth,data.health+effect.health)
        gained.health=data.health-previous
    end
    return {ok=true,item=name,gained=gained}
end

function Consumables.fuel(data,balance,source)
    if data.resources.coal>=balance.resourceCapacity(data,"coal") then return {ok=false,reason="storage_full"} end
    for index=source and source.index or 1,source and source.index or (data.inventoryCapacity or 6) do
        local item=data.inventory[index]
        if item=="coal-bucket" or item=="coal-chunk" then
            Items.write(data,nil,{kind="inventory",index=index},nil)
            return {ok=true,item=item,gained=balance.addResource(data,"coal",item=="coal-bucket" and 3 or 1)}
        end
    end
    return {ok=false,reason="missing_coal"}
end

return Consumables
