-- Give owned items to the other connected traveler through one saved transaction.
local Players=require('game.coop_players')
local Presence=require('game.coop_presence')
local Inventory=require('game.inventory')
local Items=require('game.item_instances')
local Contract=require('game.coop_item_contract')
local Refs=require('game.coop_inventory')
local P=require('game.net.protocol')
local Sharing={}
function Sharing.recipient(data,id)
    local other=id=='host' and 'companion' or 'host'
    if not data.players or not data.players[other] or not Presence.same(Players.campaignOf(data),id,other) then return end
    local a,b=data.players[id],data.players[other]
    if a.travelIdentity and a.travelIdentity.status~='active' or b.travelIdentity and b.travelIdentity.status~='active' then return end
    if Players.forActor(data,id).scene=='train' and a.activeCar~=b.activeCar then return end
    return other
end
function Sharing.install(authority,context)
    for _,name in ipairs({'inventory.give','ammo.give'}) do
        local command=name
        authority:register(command,function(data,id,args)
            local ammo=command=='ammo.give'
            if not P.fields(args,ammo and {recipient=true,ammo=true,amount=true} or {recipient=true,source=true,sourceItem=true}) then
                return nil,'invalid_arguments'
            end
            if not authority.bindings.companion then return nil,'recipient_offline' end
            local other=Sharing.recipient(data,id)
            if not other or args.recipient~=other then return nil,'recipient_unavailable' end
            local actor,recipient=Players.forActor(data,id),Players.forActor(data,other)
            local a,b=context.actorState(id),context.actorState(other)
            for _,state in ipairs({a or {},b or {}}) do
                if state.screen~='game' or state.traveling or state.changingCar or state.encounterActive or state.activityBlocked then return nil,'unavailable' end
                if not P.clock(state.x) or not P.clock(state.y) then return nil,'unavailable' end
            end
            if actor.health<=0 or recipient.health<=0 then return nil,'unavailable' end
            if (a.x-b.x)^2+(a.y-b.y)^2>140^2 then return nil,'recipient_out_of_reach' end
            local item,instance,destination
            if ammo then
                if not context.catalog.ammoPickupAmounts[args.ammo] or not P.integer(args.amount,1,1000000) then return nil,'invalid_ammo' end
                if (actor.ammo[args.ammo] or 0)<args.amount then return nil,'not_enough_ammo' end
                if (recipient.ammo[args.ammo] or 0)+args.amount>1000000000 then return nil,'ammo_full' end
            else
                if not Refs.validRef(args.source,actor,nil,context.catalog) or args.source.kind=='chest' then return nil,'invalid_slot' end
                if not args.sourceItem or not Contract.matches(args.sourceItem,actor,nil,args.source) then return nil,'stale_item' end
                item=Inventory.value(actor,nil,args.source); if not item then return nil,'empty_slot' end
                if args.source.kind=='wearable' and args.source.slot=='backpack'
                    and not Inventory.canChangeBackpack(actor,nil,context.catalog.wearableItems) then return nil,'backpack_full' end
                destination=Inventory.firstEmptySlot(recipient); if not destination then return nil,'recipient_full' end
                instance=Items.get(actor,nil,args.source)
            end
            return {scopes={'player:host','player:companion','presence:host','presence:companion'},apply=function()
                if ammo then
                    actor.ammo[args.ammo]=actor.ammo[args.ammo]-args.amount
                    recipient.ammo[args.ammo]=(recipient.ammo[args.ammo] or 0)+args.amount
                else
                    Inventory.setValue(actor,nil,args.source,nil,context.catalog.wearableItems)
                    Inventory.setValue(recipient,nil,{kind='inventory',index=destination},item,context.catalog.wearableItems,instance)
                end
                return {recipient=other,item=ammo and args.ammo or item,amount=ammo and args.amount or 1}
            end}
        end)
    end
end
return Sharing
