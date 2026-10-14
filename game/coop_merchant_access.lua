-- Merchant identity and reach checks shared by host commands and replica UI.
-- Read-only sources never normalize campaign records or install rule writers.
local Entities=require('game.coop_entities')
local Trade=require('game.merchant_trade')
local Area=require('game.crow_caravan_area')
local Players=require('game.coop_players')
local Access={}
local function near(state,x,y,radius)
    return type(state.x)=='number' and type(state.y)=='number' and type(x)=='number' and type(y)=='number'
        and (state.x-x)^2+(state.y-y)^2<=radius^2
end
function Access.find(data,targetId,merchantId,state,catalog,readOnly)
    if not state or state.screen~='game' or state.scene~=data.scene then return nil,'unavailable' end
    local target,record=Entities.find(data,targetId)
    if not target then return nil,'missing_merchant' end
    local source
    if record.kind=='stop' then
        if state.scene~='stop' and state.scene~='house' then return nil,'wrong_scene' end
        local npc=state.npc
        if not data.stopLayouts or data.stopLayouts[tostring(data.location)]~=target or merchantId~=data.currentNPC
            or not npc or npc.id~=merchantId or not near(state,npc.x,npc.y,95)
            or not target.npcOffers or target.npcOffers[merchantId]~='trade' then return nil,'merchant_unavailable' end
        source=Trade.stopSource(target,merchantId,nil,readOnly)
    elseif record.kind=='caravan' then
        local root=data.crowCaravans
        if state.scene~='caravan' or target.stop~=data.location or not root or root.activeCampId~=target.id then return nil,'wrong_scene' end
        local position
        for _,definition in ipairs(Area.merchantDefinitions) do if definition.id==merchantId then position=definition; break end end
        if not position or not near(state,position.x,position.y,position.radius) then return nil,'merchant_unavailable' end
        source=Trade.caravanSource(data,catalog,target,merchantId,readOnly)
    else return nil,'invalid_merchant' end
    if not source then return nil,'missing_merchant' end
    source.targetId=targetId; source.merchantId=merchantId
    return source
end
function Access.nearest(data,state,catalog)
    if not data or not state then return nil end
    if state.scene=='stop' or state.scene=='house' then
        local target=data.stopLayouts and data.stopLayouts[tostring(data.location)]
        if target and target.entityId then return Access.find(data,target.entityId,data.currentNPC,state,catalog,true) end
    elseif state.scene=='caravan' then
        for _,record in ipairs(Entities.records(data)) do
            if record.kind=='caravan' and record.value.id==data.crowCaravans.activeCampId then
                for _,definition in ipairs(Area.merchantDefinitions) do
                    local source=Access.find(data,record.value.entityId,definition.id,state,catalog,true)
                    if source then return source end
                end
            end
        end
    end
end
function Access.expected(data,actorId,source,command,index,catalog)
    local scopes={'player:'..actorId,'entity:'..source.targetId,'resources','relationships'}
    if source.mailboxOverflow and command=='merchant.buy' then
        local actor=Players.forActor(Players.campaignOf(data),actorId)
        local name,entry=Trade.stockItem(source,index)
        local _,_,mailbox=Trade.deliveryTarget(actor,catalog or require('game.catalog'),source,name,entry)
        if mailbox then scopes[#scopes+1]='entity:'..mailbox.entityId end
    end
    local expected={}
    for _,scope in ipairs(scopes) do expected[scope]=data.coop.revisions[scope] or 0 end
    return expected
end
return Access
