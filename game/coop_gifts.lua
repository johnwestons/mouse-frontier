local Players=require("game.coop_players")
local Entities=require("game.coop_entities")
local Inventory=require("game.inventory")
local InventoryCommands=require("game.coop_inventory")
local Items=require("game.item_instances")
local Relationships=require("game.npc_relationships")
local Util=require("game.util")
local Access=require('game.coop_recipient_access')
local Contract=require('game.coop_item_contract')
local Random=require('game.coop_random')
local Availability=require('game.coop_object_access')
local SceneNPCs=require('game.scene_npcs')
local Gifts={}

function Gifts.install(authority,context)
    local catalog=assert(context.catalog)
    local actorState=assert(context.actorState)
    for _,name in ipairs({"npc.gift","passenger.equip"}) do
        local command=name
        authority:register(command,function(data,actorId,args)
            for key in pairs(args) do
                if key~="targetId" and key~="npc" and key~="source" and key~="containerId" and key~='sourceItem' then return nil,"invalid_arguments" end
            end
            local actor=Players.forActor(data,actorId)
            local state=actorState(actorId)
            if not state or state.screen~="game" or state.scene~=data.scene then return nil,"unavailable" end
            if not Availability.available(data,actor,state) then return nil,'unavailable' end
            local target,entry=Entities.find(data,args.targetId)
            if not target or type(args.npc)~="string" then return nil,"missing_recipient" end
            local passenger=entry.kind=="passenger"
            if not passenger and command=='passenger.equip' then return nil,'invalid_recipient' end
            if not Access.find(actor,args.targetId,args.npc,state) then return nil,'recipient_unavailable' end
            local scopes={"player:"..actorId,"entity:"..target.entityId,"relationships"}
            local chest,record
            if args.containerId then
                chest,record=Entities.find(data,args.containerId)
                if not chest or type(chest.storage)~="table"
                    or not InventoryCommands.canAccess(data,actor,state,chest,record) then return nil,"container_unavailable" end
                scopes[#scopes+1]="entity:"..chest.entityId
            end
            if not InventoryCommands.validRef(args.source,actor,chest,catalog)
                or (args.source.kind=="chest")~=(chest~=nil) then return nil,"invalid_slot" end
            if not Contract.matches(args.sourceItem,actor,chest,args.source) then return nil,'stale_item' end
            local item=Inventory.value(actor,chest,args.source)
            local isWeapon=Inventory.isWeapon(item,catalog.weaponStats)
            local effect=catalog.itemEffects[item]
            local wearable=catalog.wearableItems[item]
            local fuel=item=="coal-chunk" or item=="coal-bucket"
            if not item or (command=="passenger.equip" and not isWeapon)
                or not (isWeapon or effect or wearable or fuel) then return nil,"item_not_accepted" end
            if args.source.kind=="wearable" and args.source.slot=="backpack"
                and not Inventory.canChangeBackpack(actor,nil,catalog.wearableItems) then return nil,"backpack_full" end
            local category=isWeapon and "weapon" or wearable and "gear" or fuel and "fuel"
                or (effect and effect.health and "medical" or effect and effect.food and "food" or effect and effect.water and "water" or "useful")
            return {scopes=scopes,apply=function()
                local instance=Items.get(actor,chest,args.source)
                local retired
                if isWeapon then
                    local field=passenger and "weapon" or "npcWeapon"
                    local instanceField=passenger and "weaponInstance" or "npcWeaponInstance"
                    retired=target[instanceField] and target[instanceField].id
                    target[field]=item
                    target[instanceField]=instance
                    if not passenger then
                        local key=Util.sceneKey(data.scene,data.location)
                            ..(data.scene=="house" and (":"..tostring(data.activeHouseDoor or 1)) or "")
                        local resident=SceneNPCs.find(data,args.npc,data.scene,data.activeHouseDoor)
                        if not resident and not SceneNPCs.hasResidents(data) then resident=data.npcStates and data.npcStates[key] end
                        -- npcStates stores the actor's presentation name. The
                        -- unique owned instance stays on the stop record.
                        if resident then resident.weapon=item end
                    end
                end
                Inventory.setValue(actor,chest,args.source,nil,catalog.wearableItems)
                if chest and chest.mailbox then chest.mailUnread=false end
                if chest and chest.expeditionChest then chest.opened=true end
                local result=Relationships.recordGift(data,passenger and target or args.npc,item,category)
                result.ok=true
                result.item=item; result.npc=args.npc; result.equipped=isWeapon
                result.itemId=instance and instance.id
                -- Legacy gift rules replace the ally's previous weapon. That
                -- retired item is a sink, never a second copy or free trade.
                result.retiredItemId=retired
                return result
            end}
        end)
    end
    for _,command in ipairs({'npc.chatter','passenger.chatter'}) do
        authority:register(command,function(data,actorId,args,transaction)
            for key in pairs(args) do if key~='targetId' and key~='npc' then return nil,'invalid_arguments' end end
            local actor=Players.forActor(data,actorId)
            local recipient=Access.find(actor,args.targetId,args.npc,actorState(actorId))
            if not recipient or (command=='passenger.chatter')~=(recipient.kind=='passenger') then return nil,'recipient_unavailable' end
            -- Only the user-approved regular pool is eligible here. No story,
            -- quest or legacy passenger branch is reachable through chatter.
            local lines=catalog.dialogueLines
            if type(lines)~='table' or #lines==0 or #lines>128 then return nil,'chatter_unavailable' end
            return {scopes={'entity:'..args.targetId,'relationships'},apply=function()
                local rng=Random.range(Random.generator(data,transaction.randomSeed))
                local line,status
                if recipient.kind=='passenger' then line,status=Relationships.passengerDialogue(data,recipient.target,lines,rng)
                else line,status=Relationships.npcDialogue(data,args.npc,lines,rng) end
                local index; for i,text in ipairs(lines) do if text==line then index=i; break end end
                return {ok=true,npc=args.npc,lineIndex=assert(index),status=status}
            end}
        end)
    end
end

return Gifts
