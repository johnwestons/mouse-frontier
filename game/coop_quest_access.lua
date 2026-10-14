-- Read-only assistance eligibility and revision dependencies. No reward rolls.
local Players=require('game.coop_players')
local Entities=require('game.coop_entities')
local Recipients=require('game.coop_recipient_access')
local Inventory=require('game.inventory')
local Contract=require('game.coop_item_contract')
local House=require('game.house')
local P=require('game.net.protocol')
local Progression=require('game.quest_progression')
local Access={}
function Access.recipient(actor,state,targetId,npc)
    local found=Recipients.find(actor,targetId,npc,state)
    return found and found.kind=='resident' and found or nil
end
function Access.nearest(actor,state)
    local data=Players.campaignOf(actor); local layout=data.stopLayouts[tostring(data.location)]
    return layout and layout.entityId and Access.recipient(actor,state,layout.entityId,data.currentNPC) or nil
end
function Access.itemQuest(actor,target,npc)
    local data=Players.campaignOf(actor); local request=target.helpRequests and target.helpRequests[npc]
    local quest=request and data.helpQuestSessions and data.helpQuestSessions[request.sessionId]
    if not request or request.kind~='item' or request.accepted~=true or request.complete or not quest
        or not P.text(quest.id,74) or quest.state=='offered' or quest.state=='resolved' or quest.source~='item-request'
        or quest.npc~=npc or quest.location~=data.location or request.story or request.storyHandIn or request.branch or request.sceneTransition
        or quest.story or quest.storyHandIn or quest.branch or quest.sceneTransition then return nil end
    return request,quest
end
function Access.delivery(actor,id,npc)
    local data=Players.campaignOf(actor); local quest,entry=Entities.find(data,id)
    if not quest or (entry.kind~='mailQuest' and entry.kind~='supplyQuest') or quest.complete or quest.accepted==false or quest.state=='offered'
        or quest.destination~=data.location or entry.kind=='mailQuest' and quest.recipient~=npc then return nil,'quest_unavailable' end
    if quest.story or quest.storyHandIn or quest.branch or quest.sceneTransition then return nil,'story_hand_in' end
    return quest,entry.kind
end
function Access.rewardContainer(actor,catalog)
    local data=Players.campaignOf(actor)
    if Inventory.firstEmptySlot(actor) then return nil end
    for _,item in ipairs(data.droppedItems or {}) do
        if item.name=='mailbox-reward' and item.scene=='train' then
            for i=1,catalog.storageCapacities[item.name] or 20 do if not (item.storage or {})[i] then return item end end
        end
    end
    return House.lootDestination(data,catalog,data.location)
end
function Access.scopes(actor,id,command,quest,targetId,catalog,recipientIds)
    if command=='quest.help' then return {'entity:'..targetId,'quest:'..quest.id,'player:'..id,'relationships'} end
    local data=Players.campaignOf(actor)
    local result={'entity:'..quest.entityId,'resources','relationships','rng','world:rewardDelivery'}
    for _,playerId in ipairs(recipientIds or {'host','companion'}) do
        if data.players[playerId] then result[#result+1]='player:'..playerId end
    end
    -- Lock the possible overflow destination regardless of the hidden roll.
    -- Cargo can free a backpack slot, but the same displayed dependency is
    -- retained until the hand-in is accepted or rejected.
    local container=Access.rewardContainer(actor,catalog)
    if container then result[#result+1]='entity:'..container.entityId end
    return result
end
function Access.expected(actor,id,command,quest,targetId,catalog)
    local data=Players.campaignOf(actor); local result={}
    for _,scope in ipairs(Access.scopes(actor,id,command,quest,targetId,catalog)) do result[scope]=data.coop.revisions[scope] or 0 end
    return result
end
function Access.offers(actor,recipient,catalog)
    local result={}; local data=Players.campaignOf(actor)
    local request,quest=Access.itemQuest(actor,recipient.target,recipient.npc)
    if request then
        local count=#result
        for i=1,actor.inventoryCapacity do if actor.inventory[i]==request.item then
            local source={kind='inventory',index=i}
            result[#result+1]={command='quest.help',item=request.item,slot=i,questId=quest.id,
                args={targetId=recipient.targetId,npc=recipient.npc,source=source,selected=Contract.selection(actor,nil,source)},
                available=true,expected=Access.expected(actor,'companion','quest.help',quest,recipient.targetId,catalog)}
        end end
        if #result==count then result[#result+1]={command='quest.help',item=request.item,questId=quest.id,available=false} end
    end
    for _,collection in ipairs({data.mailQuests,data.supplyQuests}) do
        for _,q in ipairs(collection or {}) do
            local valid,kind=Access.delivery(actor,q.entityId,recipient.npc)
            if valid then
                local cargo=kind=='supplyQuest' and Progression.cargoPlan(actor,catalog,q) or nil
                if cargo then
                    cargo.items={}; for _,slot in ipairs(cargo.slots) do cargo.items[#cargo.items+1]={slot=slot,name=actor.inventory[slot]} end
                end
                result[#result+1]={command='quest.deliver',questId=q.entityId,kind=kind=='mailQuest' and 'mail' or q.cargoKind or 'food',
                cargo=cargo,available=not cargo or cargo.completed,
                args={targetId=recipient.targetId,npc=recipient.npc,questId=q.entityId},
                expected=Access.expected(actor,'companion','quest.deliver',q,recipient.targetId,catalog)} end
        end
    end
    return result
end
return Access
