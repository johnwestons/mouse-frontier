local Players=require("game.coop_players")
local Entities=require("game.coop_entities")
local Inventory=require("game.inventory")
local Areas=require("game.expedition_areas")
local Consumables=require("game.consumables")
local TrainBalance=require("game.train_upgrade_balance")
local Engines=require("game.engine_upgrades")
local Config=require("game.config")
local Items=require("game.item_instances")
local Contract=require('game.coop_item_contract')
local Commands={}

local function keysOnly(value,allowed)
    if type(value)~="table" then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end

local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

local function near(state,x,y,radius)
    return finite(state.x) and finite(state.y) and finite(x) and finite(y)
        and (state.x-x)^2+(state.y-y)^2<=radius^2
end

local function access(data,actor,state,item,record)
    if not state or state.screen~="game" or state.scene~=data.scene then return false end
    if record.kind=="expeditionChest" then
        if state.scene~="expedition" or data.activeExpeditionArea~=record.areaId then return false end
        local definition=Areas.definition(record.areaId)
        for _,spot in ipairs(definition and definition.interactions or {}) do
            if spot.chestId==record.key then
                local area=data.expeditions[record.areaId]
                return (not spot.requires or (area.gates and area.gates[spot.requires]))
                    and near(state,spot.x,spot.y,spot.radius)
                    and Areas.canReach(data,record.areaId,state.x,state.y,spot.x,spot.y,true)
            end
        end
        return false
    end
    if record.kind~="drop" or item.scene~=state.scene then return false end
    if state.scene=="train" then
        if (item.carIndex or 1)~=(actor.activeCar or 1) then return false end
    elseif state.scene=="house" then
        if item.location~=data.location or (item.houseDoor or 1)~=(data.activeHouseDoor or 1) then return false end
    elseif state.scene=="expedition" then
        if item.expeditionAreaId~=data.activeExpeditionArea then return false end
    elseif state.scene=="caravan" then
        if item.caravanCampId~=(data.crowCaravans and data.crowCaravans.activeCampId) then return false end
    elseif item.location~=data.location then return false end
    return near(state,item.x,item.y,75)
end

local function isContainer(item,catalog)
    return item and type(item.storage)=='table' and (catalog.storageCapacities[item.name]~=nil or item.mailbox==true or item.expeditionChest==true)
end
local function usedContainer(chest)
    if not chest then return end
    if chest.mailbox then chest.mailUnread=false end
    if chest.expeditionChest then chest.opened=true end
end

local function validRef(ref,actor,chest,catalog)
    if not keysOnly(ref,{kind=true,index=true,slot=true}) then return false end
    if ref.kind=="wearable" then
        if ref.index~=nil then return false end
        for _,slot in ipairs(catalog.wearableSlots or {}) do if slot.id==ref.slot then return true end end
        return false
    end
    if ref.slot~=nil or not finite(ref.index) or ref.index~=math.floor(ref.index) or ref.index<1 then return false end
    if ref.kind=="inventory" then return ref.index<=actor.inventoryCapacity end
    if ref.kind=="equipment" then return ref.index<=2 end
    if ref.kind=="chest" then return chest and ref.index<=(catalog.storageCapacities[chest.name] or 10) end
    return false
end

function Commands.install(authority,context)
    local catalog=assert(context.catalog)
    local actorState=assert(context.actorState)
    local function available(data,id,state)
        return id~='companion' or state and state.screen=='game' and state.scene==data.scene
            and not state.traveling and not state.changingCar and not state.encounterActive and not state.activityBlocked
            and data.players[id].health>0
    end

    local function prepare(data,actorId,args,name)
        local actor=Players.forActor(data,actorId)
        local state=actorState(actorId)
        if not available(data,actorId,state) then return nil,'unavailable' end
        if not state or (state.screen~="game" and state.screen~="battle") or state.scene~=data.scene then return nil,"unavailable" end
        local scopes={"player:"..actorId}
        local chest
        if args.containerId~=nil then
            local record
            chest,record=Entities.find(data,args.containerId)
            if not chest or type(chest.storage)~="table" or not access(data,actor,state,chest,record) then return nil,"container_unavailable" end
            if not isContainer(chest,catalog) then return nil,"invalid_container" end
            scopes[#scopes+1]="entity:"..chest.entityId
        end
        if name~="inventory.swap" and not chest then return nil,"container_required" end
        if not validRef(args.source,actor,chest,catalog) then return nil,"invalid_slot" end
        if not Contract.matches(args.sourceItem,actor,chest,args.source) then return nil,'stale_item' end
        if name=="inventory.swap" then
            if not validRef(args.target,actor,chest,catalog) then return nil,"invalid_slot" end
            if not Contract.matches(args.targetItem,actor,chest,args.target) then return nil,'stale_item' end
            if args.source.kind==args.target.kind and args.source.index==args.target.index and args.source.slot==args.target.slot then return nil,"same_slot" end
            local usesChest=args.source.kind=="chest" or args.target.kind=="chest"
            if usesChest~=(chest~=nil) then return nil,"invalid_container" end
        end
        if name=="mailbox.collect" and args.source.kind~="chest" then return nil,"invalid_slot" end
        return {scopes=scopes,apply=function()
            local moved,reason
            if name=="inventory.swap" then
                moved,reason=Inventory.move(actor,chest,args.source,args.target,catalog.weaponStats,catalog.ammoPickupAmounts,catalog.wearableItems)
            elseif name=="storage.transfer" then
                moved,reason=Inventory.quickTransfer(actor,chest,args.source,catalog.weaponStats,catalog.ammoPickupAmounts,catalog.storageCapacities,catalog.wearableItems)
            else
                local item=Inventory.value(actor,chest,args.source)
                local amount=catalog.ammoPickupAmounts[item]
                if not amount then return nil,"not_ammunition" end
                actor.ammo[item]=(actor.ammo[item] or 0)+amount
                Inventory.setValue(actor,chest,args.source,nil,catalog.wearableItems)
                usedContainer(chest)
                return {item=item,amount=amount}
            end
            if not moved then return nil,reason or "cannot_transfer" end
            usedContainer(chest)
            return {moved=true}
        end}
    end

    for _,name in ipairs({"inventory.swap","storage.transfer","mailbox.collect"}) do
        local command=name
        authority:register(command,function(data,actorId,args)
            local allowed={source=true,containerId=true,sourceItem=true}
            if command=="inventory.swap" then allowed.target=true; allowed.targetItem=true end
            if not keysOnly(args,allowed) then return nil,"invalid_arguments" end
            return prepare(data,actorId,args,command)
        end)
    end

    authority:register("inventory.consume",function(data,actorId,args)
        if not keysOnly(args,{source=true,containerId=true,sourceItem=true}) then return nil,"invalid_arguments" end
        local actor=Players.forActor(data,actorId)
        local state=actorState(actorId)
        if not available(data,actorId,state) then return nil,'unavailable' end
        if not state or state.screen~="game" or state.scene~=data.scene then return nil,"unavailable" end
        local scopes={"player:"..actorId}
        local chest,record
        if args.containerId~=nil then
            chest,record=Entities.find(data,args.containerId)
            if not chest or type(chest.storage)~="table" or not access(data,actor,state,chest,record) then return nil,"container_unavailable" end
            if not isContainer(chest,catalog) then return nil,'invalid_container' end
            scopes[#scopes+1]="entity:"..chest.entityId
        end
        if not validRef(args.source,actor,chest,catalog) then return nil,"invalid_slot" end
        if not Contract.matches(args.sourceItem,actor,chest,args.source) then return nil,'stale_item' end
        if (args.source.kind=="chest")~=(chest~=nil) then return nil,"invalid_container" end
        local item=Inventory.value(actor,chest,args.source)
        if not item then return nil,"empty_slot" end
        local effect=catalog.itemEffects[item]
        if effect and (effect.food or effect.water or effect.oil) and not effect.potion then
            scopes[#scopes+1]="resources"; scopes[#scopes+1]="train"
        end
        return {scopes=scopes,apply=function()
            local result=Consumables.use(actor,catalog,TrainBalance,item)
            if not result.ok then return nil,result.reason end
            Inventory.setValue(actor,chest,args.source,nil,catalog.wearableItems)
            usedContainer(chest)
            return result
        end}
    end)

    authority:register("train.fuel",function(data,actorId,args)
        if not keysOnly(args,{source=true,sourceItem=true}) then return nil,"invalid_arguments" end
        local actor=Players.forActor(data,actorId)
        local state=actorState(actorId)
        if not available(data,actorId,state) then return nil,'unavailable' end
        if args.source~=nil then
            if not validRef(args.source,actor,nil,catalog) or args.source.kind~='inventory' then return nil,'invalid_slot' end
            if not Contract.matches(args.sourceItem,actor,nil,args.source) then return nil,'stale_item' end
        elseif args.sourceItem~=nil then return nil,'invalid_arguments' end
        local car=context.car or Config.trainCar
        if not state or state.screen~="game" or state.scene~="train" or data.scene~="train"
            or actor.activeCar~=1 or not near(state,car.x+165,car.y+240,95) then return nil,"out_of_reach" end
        return {scopes={"player:"..actorId,"resources","train"},apply=function()
            local result=Consumables.fuel(actor,TrainBalance,args.source)
            if not result.ok then return nil,result.reason end
            return result
        end}
    end)

    for _,name in ipairs({"train.upgrade","train.engineUpgrade"}) do
        local command=name
        authority:register(command,function(data,actorId,args)
            if not keysOnly(args,command=="train.upgrade" and {carId=true,quotedPrice=true} or {quotedPrice=true,quotedLevel=true}) then return nil,"invalid_arguments" end
            local state=actorState(actorId)
            if not state or state.screen~="game" or state.scene~="train" or data.scene~="train"
                or not available(data,actorId,state) then return nil,"unavailable" end
            local entry
            if command=="train.upgrade" then
                for _,candidate in ipairs(TrainBalance.carCatalog) do if candidate.id==args.carId then entry=candidate; break end end
                if not entry then return nil,"invalid_car" end
            end
            local price=entry and entry.cost or (Engines.next(data.engineLevel) or {}).cost
            local level
            if not entry then level=data.engineLevel+1 end
            if args.quotedPrice~=nil or args.quotedLevel~=nil then
                if not finite(args.quotedPrice) or args.quotedPrice<0 or args.quotedPrice>1e9
                    or args.quotedLevel~=nil and (not finite(args.quotedLevel) or args.quotedLevel~=math.floor(args.quotedLevel)) then return nil,'invalid_arguments' end
                if args.quotedPrice~=price or args.quotedLevel~=nil and args.quotedLevel~=level then return nil,'quote_changed' end
            end
            return {scopes={"resources","train"},apply=function()
                local result=entry and TrainBalance.purchaseCar(data,entry) or TrainBalance.purchaseEngine(data,Engines)
                if not result.ok then return nil,result.reason end
                result.price=price
                if entry then result.carId=entry.id else result.level=data.engineLevel end
                return result
            end}
        end)
    end

    authority:register("loot.pickup",function(data,actorId,args,transaction)
        if not keysOnly(args,{entityId=true}) or type(args.entityId)~="string" then return nil,"invalid_arguments" end
        local item,record=Entities.find(data,args.entityId)
        if not item or record.kind~="drop" then return nil,"missing_item" end
        if transaction.state.resources["decoration:"..item.entityId] then return nil,"activity_busy" end
        local actor=Players.forActor(data,actorId)
        local state=actorState(actorId)
        if not available(data,actorId,state) then return nil,'unavailable' end
        if not access(data,actor,state,item,record) then return nil,"out_of_reach" end
        if item.permanent then return nil,"permanent" end
        if item.storage and next(item.storage) then return nil,"container_not_empty" end
        return {scopes={"player:"..actorId,"entity:"..item.entityId},apply=function()
            local result={item=item.name}
            if item.name=="rose-heart-arrow" or item.name=="blade-hearts" then
                actor.maxHealth=actor.maxHealth+5
                actor.health=math.min(actor.maxHealth,actor.health+5)
                result.heart=true
            elseif catalog.ammoPickupAmounts[item.name] then
                local amount=catalog.ammoPickupAmounts[item.name]
                actor.ammo[item.name]=(actor.ammo[item.name] or 0)+amount
                result.amount=amount
            else
                local slot=Inventory.firstEmptySlot(actor)
                if not slot then return nil,"inventory_full" end
                Inventory.setValue(actor,nil,{kind="inventory",index=slot},item.name,catalog.wearableItems,item.itemInstance)
            end
            table.remove(record.parent,record.key)
            return result
        end}
    end)

    authority:register("loot.drop",function(data,actorId,args)
        if not keysOnly(args,{source=true,containerId=true,sourceItem=true}) then return nil,"invalid_arguments" end
        local actor=Players.forActor(data,actorId)
        local state=actorState(actorId)
        if not available(data,actorId,state) then return nil,'unavailable' end
        if not state or state.screen~="game" or state.scene~=data.scene or not finite(state.x) or not finite(state.y) then return nil,"unavailable" end
        local chest,record
        local scopes={"player:"..actorId}
        if args.containerId then
            chest,record=Entities.find(data,args.containerId)
            if not chest or type(chest.storage)~="table" or not access(data,actor,state,chest,record) then return nil,"container_unavailable" end
            if not isContainer(chest,catalog) then return nil,'invalid_container' end
            scopes[#scopes+1]="entity:"..chest.entityId
        end
        if not validRef(args.source,actor,chest,catalog) then return nil,"invalid_slot" end
        if not Contract.matches(args.sourceItem,actor,chest,args.source) then return nil,'stale_item' end
        if (args.source.kind=="chest")~=(chest~=nil) then return nil,"invalid_container" end
        local item=Inventory.value(actor,chest,args.source)
        if not item then return nil,"empty_slot" end
        if args.source.kind=="wearable" and args.source.slot=="backpack" and not Inventory.canChangeBackpack(actor,nil,catalog.wearableItems) then
            return nil,"backpack_full"
        end
        return {scopes=scopes,apply=function()
            local dropped={name=item,x=state.x+35,y=state.y,scene=data.scene,scale=1,rotation=0,droppedByPlayer=true}
            dropped.itemInstance=Items.get(actor,chest,args.source)
            if data.scene=="train" then dropped.carIndex=actor.activeCar or 1 else dropped.location=data.location end
            if data.scene=="house" then dropped.houseDoor=data.activeHouseDoor or data.lastStopDoor or 1 end
            if data.scene=="expedition" then dropped.expeditionAreaId=data.activeExpeditionArea end
            if data.scene=="caravan" then dropped.caravanCampId=data.crowCaravans and data.crowCaravans.activeCampId end
            if catalog.storageCapacities[item] then dropped.storage={} end
            data.droppedItems[#data.droppedItems+1]=dropped
            Inventory.setValue(actor,chest,args.source,nil,catalog.wearableItems)
            usedContainer(chest)
            assert(Entities.ensure(data))
            return {entityId=dropped.entityId,item=item}
        end}
    end)
end

-- Shared by item-consuming assistance commands; never accept a client claim
-- that a slot or container is currently accessible.
Commands.validRef=validRef
Commands.canAccess=access
Commands.isContainer=isContainer
return Commands
