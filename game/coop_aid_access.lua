-- Read-only patient, supply and scope facts for host and guest treatment.
local Players=require('game.coop_players')
local Entities=require('game.coop_entities')
local Contract=require('game.coop_item_contract')
local P=require('game.net.protocol')
local Access={}
local function finite(value) return type(value)=='number' and value==value and value>-math.huge and value<math.huge end
function Access.patient(actor,state,targetId,npc,cleanup)
    local data=Players.campaignOf(actor)
    if not cleanup and (actor.health<=0 or not state or state.screen~='game' or state.scene~=data.scene
        or (data.scene~='stop' and data.scene~='house') or state.traveling or state.changingCar or state.encounterActive
        or state.activityBlocked and state.activeActivity~='firstAid') then return nil,'activity_unavailable' end
    local target,entry=Entities.find(data,targetId)
    local story=data.conversations and data.conversations.active
    if not cleanup and story and story.phase=='prompt' and story.sceneEpoch==data.coop.sceneEpoch
        and story.targetId==targetId and story.npc==npc then return nil,'activity_busy' end
    if not target or entry.kind~='stop' or target~=data.stopLayouts[tostring(data.location)]
        or not P.text(npc,128) then return nil,'patient_unavailable' end
    local resident=state and state.npc
    if not cleanup and (data.currentNPC~=npc or not resident or resident.id~=npc
        or not finite(state.x) or not finite(state.y) or not finite(resident.x) or not finite(resident.y)
        or (state.x-resident.x)^2+(state.y-resident.y)^2>=95^2) then return nil,'patient_unavailable' end
    local request=target.helpRequests and target.helpRequests[npc]
    local quest=request and data.helpQuestSessions and data.helpQuestSessions[request.sessionId]
    if not request or request.kind~='aid' or request.accepted~=true or request.complete
        or not quest or not P.text(quest.id,62) or quest.state=='offered' or quest.state=='resolved'
        or quest.npc~=npc or quest.location~=data.location or quest.source~='first-aid' then return nil,'quest_unavailable' end
    return {target=target,request=request,quest=quest,targetId=targetId,npc=npc}
end
function Access.nearest(actor,state)
    local data=Players.campaignOf(actor); local layout=data.stopLayouts[tostring(data.location)]
    if not layout or not layout.entityId then return nil end
    return Access.patient(actor,state,layout.entityId,data.currentNPC)
end
function Access.supplies(actor,catalog)
    local result={}
    for index=1,actor.inventoryCapacity do
        local name=actor.inventory[index]; local effect=name and catalog.itemEffects[name]
        if effect and effect.health then
            local source={kind='inventory',index=index}
            result[#result+1]={name=name,source=source,selected=Contract.selection(actor,nil,source)}
        end
    end
    return result
end
function Access.expected(actor,id,command,questId,targetId)
    local data=Players.campaignOf(actor); local scopes={'activity:firstAid:'..questId,'quest:'..questId}
    if command=='firstAid.acquire' or command=='firstAid.complete' then scopes[#scopes+1]='player:'..id end
    if command=='firstAid.complete' then scopes[#scopes+1]='relationships'; scopes[#scopes+1]='entity:'..targetId end
    if command=='activity.release' then scopes={'activity:firstAid:'..questId} end
    local result={}; for _,scope in ipairs(scopes) do result[scope]=data.coop.revisions[scope] or 0 end
    return result
end
return Access
