-- Read-only selectors and revision scopes shared by the guest and authority.
local Inventory=require('game.inventory')
local Items=require('game.item_instances')
local P=require('game.net.protocol')
local Entities=require('game.coop_entities')
local Contract={}
function Contract.selection(data,chest,ref)
    local name=Inventory.value(data,chest,ref)
    if not name then return false end
    local item=Items.get(data,chest,ref)
    return {name=name,id=item and item.id or false}
end
function Contract.matches(expected,data,chest,ref)
    if expected==nil then return true end -- Existing local-host callers.
    local current=Contract.selection(data,chest,ref)
    if expected==false then return current==false end
    return P.fields(expected,{name=true,id=true}) and P.text(expected.name,128)
        and (expected.id==false or P.text(expected.id,32)) and current~=false
        and expected.name==current.name and expected.id==current.id
end
function Contract.expected(data,actorId,name,args,catalog)
    local scopes={'player:'..actorId}
    if name=='inventory.give' or name=='ammo.give' then scopes={'player:host','player:companion','presence:host','presence:companion'} end
    if args.entityId then scopes[#scopes+1]='entity:'..args.entityId end
    if args.containerId then scopes[#scopes+1]='entity:'..args.containerId end
    if args.containerId and(name=='inventory.swap'or name=='storage.transfer'or name=='mailbox.collect')then
        local chest=Entities.find(data,args.containerId)
        if chest and chest.name=='mailbox-reward'and chest.scene=='train'then scopes[#scopes+1]='world:rewardDelivery'end
    end
    if name=='inventory.consume' then
        local actor=data.players[actorId]
        local chest=args.containerId and Entities.find(data,args.containerId)
        local item=Inventory.value(actor,chest,args.source)
        local effect=catalog.itemEffects[item]
        if effect and not effect.potion and (effect.food or effect.water or effect.oil) then
            scopes[#scopes+1]='resources'; scopes[#scopes+1]='train'
        end
    end
    local expected={}
    for _,scope in ipairs(scopes) do expected[scope]=data.coop.revisions[scope] or 0 end
    return expected
end
return Contract
